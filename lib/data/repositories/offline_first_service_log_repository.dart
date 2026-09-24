import '../../core/storage/local_snapshot_store.dart';
import '../models/equipment.dart';
import '../models/service_case.dart';
import '../sync/offline_sync_remote.dart';
import '../sync/supabase_sync_gateway.dart';
import '../sync/sync_conflict.dart';
import '../sync/sync_operation.dart';
import '../sync/sync_queue_service.dart';
import 'demo_service_log_repository.dart';
import 'service_log_repository.dart';

class OfflineFirstServiceLogRepository
    implements ServiceLogRepository, SyncAwareRepository {
  OfflineFirstServiceLogRepository({
    required DemoServiceLogRepository local,
    required OfflineSyncRemote remote,
    required LocalSnapshotStore store,
    required String namespace,
  }) : _local = local,
       _remote = remote,
       _store = store,
       _namespace = namespace,
       _queue = SyncQueueService(store: store, namespace: namespace);

  factory OfflineFirstServiceLogRepository.supabase({
    required LocalSnapshotStore store,
    required String namespace,
  }) {
    return OfflineFirstServiceLogRepository(
      local: DemoServiceLogRepository.offlineMirror(
        storage: store,
        namespace: namespace,
      ),
      remote: SupabaseSyncGateway(),
      store: store,
      namespace: namespace,
    );
  }

  final DemoServiceLogRepository _local;
  final OfflineSyncRemote _remote;
  final LocalSnapshotStore _store;
  final String _namespace;
  final SyncQueueService _queue;
  Future<void>? _activeSync;

  @override
  bool get isDemo => false;

  @override
  Future<List<Equipment>> fetchEquipments() => _local.fetchEquipments();

  @override
  Future<List<ServiceCase>> fetchCases() => _local.fetchCases();

  @override
  Future<EquipmentCatalog> fetchEquipmentCatalog() =>
      _local.fetchEquipmentCatalog();

  @override
  Future<String> createEquipmentModel(EquipmentModelDraft draft) =>
      _local.createEquipmentModel(draft);

  @override
  Future<String> createCustomer(CustomerDraft draft) =>
      _local.createCustomer(draft);

  @override
  Future<void> updateCustomer(String id, CustomerDraft draft) =>
      _local.updateCustomer(id, draft);

  @override
  Future<String> createSite(SiteDraft draft) => _local.createSite(draft);

  @override
  Future<void> updateSite(String id, SiteDraft draft) =>
      _local.updateSite(id, draft);

  @override
  Future<String> createCustomerSite(CustomerSiteDraft draft) =>
      _local.createCustomerSite(draft);

  @override
  Future<void> createEquipment(EquipmentDraft draft) =>
      _local.createEquipment(draft);

  @override
  Future<void> updateEquipment(String id, EquipmentDraft draft) =>
      _local.updateEquipment(id, draft);

  @override
  Future<void> saveCase(ServiceCaseDraft draft) => _local.saveCase(draft);

  @override
  Future<List<SimilarCaseResult>> searchSimilarCases(
    SimilarCaseQuery query,
  ) async {
    try {
      return await _remote.searchSimilarCases(query);
    } catch (_) {
      return _local.searchSimilarCases(query);
    }
  }

  @override
  Future<void> archiveCustomer(String id) => _local.archiveCustomer(id);

  @override
  Future<void> archiveEquipment(String id) => _local.archiveEquipment(id);

  @override
  Future<void> archiveCase(String id) => _local.archiveCase(id);

  @override
  Future<void> restoreCustomer(String id) => _local.restoreCustomer(id);

  @override
  Future<void> restoreEquipment(String id) => _local.restoreEquipment(id);

  @override
  Future<void> restoreCase(String id) => _local.restoreCase(id);

  @override
  Future<ArchivedRecords> fetchArchived() async {
    // O pull descarta registros arquivados (filtra deleted_at is null),
    // então o espelho local só conhece os que foram arquivados neste
    // dispositivo e ainda não sincronizaram. A lista completa vive no
    // servidor; sem rede, mostra-se o que houver localmente.
    try {
      return await _remote.fetchArchived();
    } catch (_) {
      return _local.fetchArchived();
    }
  }

  /// Impedimentos à exclusão definitiva, sobre a visão completa.
  ///
  /// O espelho local guarda apenas os registros ativos: o download filtra
  /// `deleted_at is null`. Quem foi arquivado noutro dispositivo só
  /// aparece na lista vinda do servidor, e é justamente esse o dependente
  /// perigoso — sairia em cascata junto do pai, sem ninguém ver. Por isso
  /// a contagem junta as duas fontes antes de decidir.
  ///
  /// Sem rede, `fetchArchived` cai no espelho local e a conta fica
  /// incompleta. Não é problema: o servidor repete a verificação e recusa,
  /// e a recusa aparece na tela de conflitos.
  Future<void> _assertPurgeable(String entityType, String id) async {
    if (entityType == 'service_case') return; // Folha: nada depende dele.

    final arquivados = await fetchArchived();
    final ativos = await _local.fetchEquipments();
    final casosAtivos = await _local.fetchCases();

    final equipamentos = <Equipment>[...ativos, ...arquivados.equipment];
    // Ativo e arquivado chegam em tipos diferentes; o que interessa aos
    // dois é o equipamento a que o atendimento pertence.
    final donosDeAtendimento = <String>[
      ...casosAtivos.map((item) => item.equipmentId),
      ...arquivados.cases.map((item) => item.equipmentId),
    ];

    var equipamentosDependentes = 0;
    var atendimentosDependentes = 0;

    if (entityType == 'customer') {
      final locais = await _local.siteIdsOfCustomer(id);
      final doCliente = equipamentos
          .where((item) => locais.contains(item.siteId))
          .toList(growable: false);
      final idsDoCliente = doCliente.map((item) => item.id).toSet();
      equipamentosDependentes = doCliente.length;
      atendimentosDependentes = donosDeAtendimento
          .where(idsDoCliente.contains)
          .length;
    } else {
      atendimentosDependentes = donosDeAtendimento
          .where((dono) => dono == id)
          .length;
    }

    DemoServiceLogRepository.assertNoPurgeBlockers(
      entityType == 'customer' ? 'cliente' : 'equipamento',
      equipamentos: equipamentosDependentes,
      atendimentos: atendimentosDependentes,
    );
  }

  @override
  Future<void> purgeCustomer(String id) async {
    await _assertPurgeable('customer', id);
    await _local.purgeCustomer(id);
  }

  @override
  Future<void> purgeEquipment(String id) async {
    await _assertPurgeable('equipment', id);
    await _local.purgeEquipment(id);
  }

  @override
  Future<void> purgeCase(String id) => _local.purgeCase(id);

  @override
  Future<void> signOut() => _remote.signOut();

  @override
  Future<SyncStatusSnapshot> fetchSyncStatus() async {
    final pending = await _queue.pending();
    final lastSync = await _store.readMetadata(
      _namespace,
      'last_successful_sync',
    );
    final lastError = await _store.readMetadata(_namespace, 'last_sync_error');
    final conflicts = pending
        .where(
          (item) => item.lastError?.startsWith(conflictErrorPrefix) == true,
        )
        .length;
    return SyncStatusSnapshot(
      pendingCount: pending.length,
      conflictCount: conflicts,
      storageLabel: '${_store.storageLabel} + Supabase',
      lastSuccessfulSync: lastSync == null ? null : DateTime.tryParse(lastSync),
      lastError: lastError?.isEmpty == true ? null : lastError,
    );
  }

  @override
  Future<bool> isCaseNumberProvisional(String caseId) =>
      _local.isCaseNumberProvisional(caseId);

  @override
  Future<List<SyncConflict>> fetchConflicts() => _local.fetchConflicts();

  @override
  Future<void> resolveConflict(
    String operationId,
    ConflictResolution resolution,
  ) => _local.resolveConflict(operationId, resolution);

  @override
  Future<void> syncPendingChanges() {
    final running = _activeSync;
    if (running != null) return running;
    final future = _runSync();
    _activeSync = future;
    return future.whenComplete(() {
      if (identical(_activeSync, future)) _activeSync = null;
    });
  }

  Future<void> _runSync() async {
    // Cada operação é tentada de forma independente: uma entidade recusada
    // pelo servidor não pode impedir o envio das demais nem bloquear o pull.
    // O primeiro erro é preservado e relançado no fim, para a interface
    // continuar reportando a falha ao usuário.
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      final pending = await _queue.pending();
      for (final candidate in pending) {
        final operation = await _store.claimOperation(candidate.id);
        if (operation == null) continue;
        try {
          final result = await _remote.applyOperation(operation);
          if (result.conflict) {
            final message =
                result.message ??
                'O registro foi alterado no servidor e requer revisão.';
            final error = '$conflictErrorPrefix $message';
            await _store.recordFailure(operation.id, error: error);
            throw SyncConflictException(message, conflictId: result.conflictId);
          }
          if (!result.applied) {
            throw StateError(
              result.message ?? 'O servidor recusou a operação offline.',
            );
          }
          if (operation.operation == 'purge') {
            // Exclusão definitiva não devolve revisão utilizável: a linha
            // já não existe, e quando ela nem existia o servidor responde
            // sem revisão nenhuma.
            await _local.acknowledgePurge(operation);
          } else {
            final revision = result.revision;
            if (revision == null || revision < 1) {
              throw StateError('Servidor não informou a revisão da operação.');
            }
            await _local.acknowledge(operation, revision);
          }
          if (operation.entityType == 'service_case' &&
              operation.payload['status'] == 'resolved') {
            try {
              await _remote.indexResolvedCase(operation.entityId);
            } catch (_) {
              // Indexação por IA é best-effort: o atendimento já foi
              // confirmado pelo servidor e não deve voltar para a fila
              // só porque a indexação semântica falhou.
            }
          }
        } catch (error, stackTrace) {
          if (error is! SyncConflictException) {
            await _queue.markFailed(operation, error);
          }
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }

      final remoteSnapshot = await _remote.pullSnapshot();
      await _local.replaceFromRemote(
        equipment: remoteSnapshot.equipment,
        cases: remoteSnapshot.cases,
        catalog: remoteSnapshot.catalog,
        revisions: remoteSnapshot.revisions,
      );
      await _store.writeMetadata(
        _namespace,
        'last_successful_sync',
        remoteSnapshot.serverTime.toIso8601String(),
      );
      final failure = firstError;
      if (failure != null) {
        // O catch externo registra a falha em last_sync_error.
        Error.throwWithStackTrace(
          failure,
          firstStackTrace ?? StackTrace.current,
        );
      }
      await _store.writeMetadata(_namespace, 'last_sync_error', '');
    } catch (error) {
      await _store.writeMetadata(
        _namespace,
        'last_sync_error',
        error.toString(),
      );
      rethrow;
    }
  }
}
