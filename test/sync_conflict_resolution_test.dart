import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/data/models/equipment.dart';
import 'package:servicelog_ai/data/models/service_case.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/data/repositories/offline_first_service_log_repository.dart';
import 'package:servicelog_ai/data/sync/offline_sync_remote.dart';
import 'package:servicelog_ai/data/sync/sync_conflict.dart';
import 'package:servicelog_ai/data/sync/sync_operation.dart';

void main() {
  late MemorySnapshotStore store;
  late DemoServiceLogRepository local;
  late _RevisionAwareRemote remote;
  late OfflineFirstServiceLogRepository repository;

  setUp(() {
    store = MemorySnapshotStore();
    local = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'conflitos',
    );
    remote = _RevisionAwareRemote();
    repository = OfflineFirstServiceLogRepository(
      local: local,
      remote: remote,
      store: store,
      namespace: 'conflitos',
    );
  });

  /// Cria um cliente, sincroniza, e faz o servidor avançar de revisão por
  /// baixo. A edição seguinte carrega a revisão antiga e conflita — que é
  /// exatamente a sequência de dois dispositivos editando o mesmo registro.
  Future<String> criarConflito() async {
    final id = await repository.createCustomer(
      const CustomerDraft(name: 'Hospital Central'),
    );
    remote.snapshotFor(id, 'Hospital Central', revision: 1);
    await repository.syncPendingChanges();
    expect((await repository.fetchSyncStatus()).pendingCount, 0);

    remote.revisions['customer:$id'] = 7;
    await repository.updateCustomer(
      id,
      const CustomerDraft(name: 'Hospital Central — nome local'),
    );
    await expectLater(repository.syncPendingChanges(), throwsA(anything));
    return id;
  }

  test('conflito aparece na lista com o registro identificado', () async {
    final id = await criarConflito();

    final conflitos = await repository.fetchConflicts();
    expect(conflitos, hasLength(1));
    final conflito = conflitos.single;
    expect(conflito.entityId, id);
    expect(conflito.entityLabel, 'Cliente');
    expect(conflito.actionLabel, 'Edição');
    expect(conflito.recordLabel, 'Hospital Central — nome local');
    expect(conflito.message, 'O cliente foi alterado em outro dispositivo.');
    expect(conflito.message, isNot(startsWith(conflictErrorPrefix)));
    expect((await repository.fetchSyncStatus()).conflictCount, 1);
  });

  test('manter a versão local sobrescreve o servidor', () async {
    final id = await criarConflito();
    final conflito = (await repository.fetchConflicts()).single;

    await repository.resolveConflict(
      conflito.operationId,
      ConflictResolution.keepLocal,
    );
    expect(
      await repository.fetchConflicts(),
      isEmpty,
      reason: 'resolver tira o conflito da lista antes mesmo de enviar',
    );

    remote.snapshotFor(id, 'Hospital Central — nome local', revision: 8);
    await repository.syncPendingChanges();

    final status = await repository.fetchSyncStatus();
    expect(status.pendingCount, 0);
    expect(status.conflictCount, 0);
    expect(remote.storedNames[id], 'Hospital Central — nome local');
  });

  test('descartar a versão local devolve o que está no servidor', () async {
    final id = await criarConflito();
    final conflito = (await repository.fetchConflicts()).single;
    final tentativasAntes = remote.applyCount;

    await repository.resolveConflict(
      conflito.operationId,
      ConflictResolution.discardLocal,
    );

    remote.snapshotFor(id, 'Hospital Central', revision: 7);
    await repository.syncPendingChanges();

    expect(
      remote.applyCount,
      tentativasAntes,
      reason: 'a alteração descartada não pode chegar ao servidor',
    );
    expect((await repository.fetchSyncStatus()).pendingCount, 0);
    expect(
      (await repository.fetchEquipmentCatalog()).customers.single.name,
      'Hospital Central',
      reason: 'com a fila vazia, o download volta a ser aplicado',
    );
  });

  test('conflito não resolvido impede o download de ser aplicado', () async {
    final id = await criarConflito();

    remote.snapshotFor(id, 'Nome vindo do servidor', revision: 7);
    await expectLater(repository.syncPendingChanges(), throwsA(anything));

    expect(
      (await repository.fetchEquipmentCatalog()).customers.single.name,
      'Hospital Central — nome local',
      reason:
          'enquanto a fila tem pendências, o espelho preserva a edição local',
    );
  });

  group('SyncConflict.fromOperation', () {
    SyncOperation operacao({String? erro}) => SyncOperation(
      id: 'op-1',
      namespace: 'n',
      entityType: 'equipment',
      entityId: 'eq-1',
      operation: 'archive',
      payload: const {'id': 'eq-1'},
      createdAt: DateTime.utc(2026, 9, 18),
      lastError: erro,
    );

    test('ignora operação sem erro', () {
      expect(SyncConflict.fromOperation(operacao(), recordLabel: 'x'), isNull);
    });

    test('ignora falha técnica que não é conflito', () {
      expect(
        SyncConflict.fromOperation(
          operacao(erro: 'SocketException: sem rede'),
          recordLabel: 'x',
        ),
        isNull,
      );
    });

    test('nomeia a ação de arquivamento em vez de chamá-la edição', () {
      final conflito = SyncConflict.fromOperation(
        operacao(erro: '$conflictErrorPrefix Alterado em outro dispositivo.'),
        recordLabel: 'Philips Azurion · AZ-1',
      );
      expect(conflito, isNotNull);
      expect(conflito!.actionLabel, 'Arquivamento');
      expect(conflito.keepLocalLabel, 'Arquivar assim mesmo');
      expect(conflito.entityLabel, 'Equipamento');
      expect(conflito.message, 'Alterado em outro dispositivo.');
    });
  });
}

/// Servidor que reproduz a regra da RPC: revisão de base zero grava sem
/// verificar, e qualquer outra precisa bater com a revisão corrente.
class _RevisionAwareRemote implements OfflineSyncRemote {
  final Map<String, int> revisions = {};
  final Map<String, String> storedNames = {};
  int applyCount = 0;

  RemoteSyncSnapshot snapshot = RemoteSyncSnapshot(
    equipment: const [],
    cases: const [],
    catalog: EquipmentCatalog.empty,
    revisions: const {},
    serverTime: DateTime.utc(2026, 9, 18),
  );

  void snapshotFor(String customerId, String name, {required int revision}) {
    revisions['customer:$customerId'] = revision;
    storedNames[customerId] = name;
    snapshot = RemoteSyncSnapshot(
      equipment: const [],
      cases: const [],
      catalog: EquipmentCatalog(
        models: const [],
        customers: [CustomerOption(id: customerId, name: name)],
        sites: const [],
      ),
      revisions: {'customer:$customerId': revision},
      serverTime: DateTime.utc(2026, 9, 18),
    );
  }

  @override
  Future<SyncApplyResult> applyOperation(SyncOperation operation) async {
    applyCount++;
    final key = '${operation.entityType}:${operation.entityId}';
    final current = revisions[key];
    final expected = operation.expectedRevision;
    if (current != null && expected > 0 && expected != current) {
      return const SyncApplyResult(
        status: 'conflict',
        message: 'O cliente foi alterado em outro dispositivo.',
        conflictId: 'conflict-1',
      );
    }
    final next = (current ?? 0) + 1;
    revisions[key] = next;
    final name = operation.payload['name'];
    if (name is String) storedNames[operation.entityId] = name;
    return SyncApplyResult(status: 'applied', revision: next);
  }

  @override
  Future<RemoteSyncSnapshot> pullSnapshot() async => snapshot;

  @override
  Future<List<SimilarCaseResult>> searchSimilarCases(
    SimilarCaseQuery query,
  ) async => const [];

  @override
  Future<void> indexResolvedCase(String serviceCaseId) async {}

  @override
  Future<ArchivedRecords> fetchArchived() async =>
      const ArchivedRecords(customers: [], equipment: [], cases: []);

  @override
  Future<void> signOut() async {}
}
