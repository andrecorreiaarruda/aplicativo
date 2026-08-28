import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/data/models/equipment.dart';
import 'package:servicelog_ai/data/models/service_case.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/data/repositories/offline_first_service_log_repository.dart';
import 'package:servicelog_ai/data/sync/offline_sync_remote.dart';
import 'package:servicelog_ai/data/sync/sync_operation.dart';

void main() {
  test('grava localmente e esvazia a fila após sincronização', () async {
    final store = MemorySnapshotStore();
    final local = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'test-sync',
    );
    final remote = _FakeRemote();
    final repository = OfflineFirstServiceLogRepository(
      local: local,
      remote: remote,
      store: store,
      namespace: 'test-sync',
    );

    final customerId = await repository.createCustomer(
      const CustomerDraft(name: 'Hospital Offline'),
    );
    expect((await repository.fetchSyncStatus()).pendingCount, 1);

    remote.snapshot = RemoteSyncSnapshot(
      equipment: const [],
      cases: const [],
      catalog: EquipmentCatalog(
        models: const [],
        customers: [CustomerOption(id: customerId, name: 'Hospital Offline')],
        sites: const [],
      ),
      revisions: {'customer:$customerId': 1},
      serverTime: DateTime.utc(2026, 7, 27),
    );

    await repository.syncPendingChanges();

    final status = await repository.fetchSyncStatus();
    expect(status.pendingCount, 0);
    expect(status.lastSuccessfulSync, isNotNull);
    expect(
      (await repository.fetchEquipmentCatalog()).customers.single.name,
      'Hospital Offline',
    );
  });

  test('reabre offline preservando registros e fila local', () async {
    final store = MemorySnapshotStore();
    final firstLocal = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'test-reopen',
    );
    final firstRepository = OfflineFirstServiceLogRepository(
      local: firstLocal,
      remote: _FakeRemote(),
      store: store,
      namespace: 'test-reopen',
    );

    await firstRepository.createCustomer(
      const CustomerDraft(name: 'Hospital persistido offline'),
    );

    final secondLocal = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'test-reopen',
    );
    final secondRepository = OfflineFirstServiceLogRepository(
      local: secondLocal,
      remote: _FakeRemote(),
      store: store,
      namespace: 'test-reopen',
    );

    final catalog = await secondRepository.fetchEquipmentCatalog();
    final status = await secondRepository.fetchSyncStatus();
    expect(catalog.customers.single.name, 'Hospital persistido offline');
    expect(status.pendingCount, 1);
  });

  test(
    'indexa por IA um atendimento resolvido após sincronizar com sucesso',
    () async {
      final store = MemorySnapshotStore();
      final local = DemoServiceLogRepository.offlineMirror(
        storage: store,
        namespace: 'test-index-resolved',
      );
      final remote = _FakeRemote();
      final repository = OfflineFirstServiceLogRepository(
        local: local,
        remote: remote,
        store: store,
        namespace: 'test-index-resolved',
      );

      final modelId = await repository.createEquipmentModel(
        const EquipmentModelDraft(
          manufacturer: 'Philips',
          model: 'Allura Xper FD10',
          modality: 'Angiografia',
        ),
      );
      await repository.createEquipment(
        EquipmentDraft(
          modelId: modelId,
          serialNumber: 'SN-TESTE-001',
          status: 'operational',
        ),
      );
      final equipmentId = (await repository.fetchEquipments()).single.id;

      await repository.saveCase(
        ServiceCaseDraft(
          equipmentId: equipmentId,
          reportedFailure: 'Falha resolvida em teste',
          status: 'resolved',
          operationalImpact: 'none',
          solutionConfidence: 'confirmed',
        ),
      );

      // O id precisa ser lido ANTES de sincronizar: o pull substitui o
      // estado local pelo snapshot remoto, e o fake devolve um snapshot
      // vazio.
      final caseId = (await repository.fetchCases()).single.id;

      await repository.syncPendingChanges();

      expect(remote.indexedCaseIds, [caseId]);
    },
  );

  test('não aciona indexação por IA para atendimentos ainda abertos', () async {
    final store = MemorySnapshotStore();
    final local = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'test-index-open',
    );
    final remote = _FakeRemote();
    final repository = OfflineFirstServiceLogRepository(
      local: local,
      remote: remote,
      store: store,
      namespace: 'test-index-open',
    );

    final modelId = await repository.createEquipmentModel(
      const EquipmentModelDraft(
        manufacturer: 'Philips',
        model: 'Allura Xper FD10',
        modality: 'Angiografia',
      ),
    );
    await repository.createEquipment(
      EquipmentDraft(
        modelId: modelId,
        serialNumber: 'SN-TESTE-002',
        status: 'operational',
      ),
    );
    final equipmentId = (await repository.fetchEquipments()).single.id;

    await repository.saveCase(
      ServiceCaseDraft(
        equipmentId: equipmentId,
        reportedFailure: 'Falha ainda em diagnóstico',
        status: 'diagnosing',
        operationalImpact: 'degraded',
        solutionConfidence: 'unconfirmed',
      ),
    );

    await repository.syncPendingChanges();

    expect(remote.indexedCaseIds, isEmpty);
  });

  test(
    'falha de indexação por IA não impede a sincronização do atendimento',
    () async {
      final store = MemorySnapshotStore();
      final local = DemoServiceLogRepository.offlineMirror(
        storage: store,
        namespace: 'test-index-failure',
      );
      final remote = _FakeRemote(failIndexing: true);
      final repository = OfflineFirstServiceLogRepository(
        local: local,
        remote: remote,
        store: store,
        namespace: 'test-index-failure',
      );

      final modelId = await repository.createEquipmentModel(
        const EquipmentModelDraft(
          manufacturer: 'Philips',
          model: 'Allura Xper FD10',
          modality: 'Angiografia',
        ),
      );
      await repository.createEquipment(
        EquipmentDraft(
          modelId: modelId,
          serialNumber: 'SN-TESTE-003',
          status: 'operational',
        ),
      );
      final equipmentId = (await repository.fetchEquipments()).single.id;

      await repository.saveCase(
        ServiceCaseDraft(
          equipmentId: equipmentId,
          reportedFailure: 'Falha resolvida com indexação indisponível',
          status: 'resolved',
          operationalImpact: 'none',
          solutionConfidence: 'confirmed',
        ),
      );

      await repository.syncPendingChanges();

      final status = await repository.fetchSyncStatus();
      expect(status.pendingCount, 0);
      expect(remote.indexedCaseIds, isEmpty);
    },
  );

  test(
    'mantém a operação na fila quando o servidor informa conflito',
    () async {
      final store = MemorySnapshotStore();
      final local = DemoServiceLogRepository.offlineMirror(
        storage: store,
        namespace: 'test-conflict',
      );
      final remote = _FakeRemote(conflict: true);
      final repository = OfflineFirstServiceLogRepository(
        local: local,
        remote: remote,
        store: store,
        namespace: 'test-conflict',
      );

      await repository.createCustomer(
        const CustomerDraft(name: 'Cliente em conflito'),
      );

      await expectLater(
        repository.syncPendingChanges(),
        throwsA(isA<SyncConflictException>()),
      );

      final status = await repository.fetchSyncStatus();
      expect(status.pendingCount, 1);
      expect(status.conflictCount, 1);
    },
  );

  test('uma operação recusada não impede as demais nem o pull', () async {
    final store = MemorySnapshotStore();
    final local = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'test-partial',
    );
    final remote = _FakeRemote();
    final repository = OfflineFirstServiceLogRepository(
      local: local,
      remote: remote,
      store: store,
      namespace: 'test-partial',
    );

    // Duas entidades independentes na mesma fila. O identificador é gerado
    // no dispositivo, então a recusa só pode ser configurada depois.
    final recusado = await repository.createCustomer(
      const CustomerDraft(name: 'Cliente recusado'),
    );
    final seguinte = await repository.createCustomer(
      const CustomerDraft(name: 'Cliente seguinte'),
    );
    remote.rejectedEntityIds.add(recusado);

    remote.snapshot = RemoteSyncSnapshot(
      equipment: const [],
      cases: const [],
      catalog: EquipmentCatalog(
        models: const [],
        customers: [CustomerOption(id: seguinte, name: 'Cliente seguinte')],
        sites: const [],
      ),
      revisions: {'customer:$seguinte': 1},
      serverTime: DateTime.utc(2026, 8, 26),
    );

    // A falha continua sendo reportada à interface.
    await expectLater(repository.syncPendingChanges(), throwsStateError);

    // Mas a operação seguinte foi enviada mesmo assim: antes da correção o
    // laço abortava na primeira recusa e esta nunca chegava ao servidor.
    expect(remote.appliedEntityIds, contains(seguinte));

    // E o pull ocorreu, apesar da recusa.
    final status = await repository.fetchSyncStatus();
    expect(status.lastSuccessfulSync, isNotNull);
    expect(status.lastError, isNotNull);

    // Só a operação recusada permanece na fila.
    final pendentes = await store.pendingOperations('test-partial');
    expect(pendentes.map((item) => item.entityId).toList(), [recusado]);
  });
}

class _FakeRemote implements OfflineSyncRemote {
  _FakeRemote({
    this.conflict = false,
    this.failIndexing = false,
    Set<String>? rejectedEntityIds,
  }) : rejectedEntityIds = rejectedEntityIds ?? <String>{};

  final bool conflict;
  final bool failIndexing;

  /// Entidades que o servidor recusa. Permite exercitar uma fila em que
  /// parte das operações falha e parte deve seguir assim mesmo.
  final Set<String> rejectedEntityIds;

  final List<String> indexedCaseIds = [];
  final List<String> appliedEntityIds = [];
  RemoteSyncSnapshot snapshot = RemoteSyncSnapshot(
    equipment: const [],
    cases: const [],
    catalog: EquipmentCatalog.empty,
    revisions: const {},
    serverTime: DateTime.utc(2026, 7, 27),
  );

  @override
  Future<SyncApplyResult> applyOperation(SyncOperation operation) async {
    if (rejectedEntityIds.contains(operation.entityId)) {
      throw StateError('Falha simulada para ${operation.entityId}.');
    }
    appliedEntityIds.add(operation.entityId);
    if (conflict) {
      return const SyncApplyResult(
        status: 'conflict',
        message: 'Alterado em outro dispositivo.',
        conflictId: 'conflict-test',
        revision: 2,
      );
    }
    return const SyncApplyResult(status: 'applied', revision: 1);
  }

  @override
  Future<RemoteSyncSnapshot> pullSnapshot() async => snapshot;

  @override
  Future<List<SimilarCaseResult>> searchSimilarCases(
    SimilarCaseQuery query,
  ) async => const [];

  @override
  Future<void> indexResolvedCase(String serviceCaseId) async {
    if (failIndexing) {
      throw StateError('Falha simulada de indexação.');
    }
    indexedCaseIds.add(serviceCaseId);
  }

  @override
  Future<ArchivedRecords> fetchArchived() async => ArchivedRecords.empty;

  @override
  Future<void> signOut() async {}
}
