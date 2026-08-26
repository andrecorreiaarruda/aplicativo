import '../../core/storage/local_snapshot_store.dart';
import '../models/equipment.dart';
import '../models/service_case.dart';
import '../sync/offline_sync_remote.dart';
import '../sync/supabase_sync_gateway.dart';
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
        .where((item) => item.lastError?.startsWith('CONFLICT:') == true)
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
    try {
      final pending = await _queue.pending();
      for (final operation in pending) {
        try {
          final result = await _remote.applyOperation(operation);
          if (result.conflict) {
            final message =
                result.message ??
                'O registro foi alterado no servidor e requer revisão.';
            final error = 'CONFLICT: $message';
            await _store.markAttempt(operation.id, error: error);
            throw SyncConflictException(message, conflictId: result.conflictId);
          }
          if (!result.applied) {
            throw StateError(
              result.message ?? 'O servidor recusou a operação offline.',
            );
          }
          await _queue.markCompleted(operation);
          if (result.revision != null) {
            await _local.updateRemoteRevision(
              operation.entityType,
              operation.entityId,
              result.revision!,
            );
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
        } catch (error) {
          if (error is! SyncConflictException) {
            await _queue.markFailed(operation, error);
          }
          rethrow;
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
