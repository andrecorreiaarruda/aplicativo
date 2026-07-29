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
}

class _FakeRemote implements OfflineSyncRemote {
  _FakeRemote({this.conflict = false});

  final bool conflict;
  RemoteSyncSnapshot snapshot = RemoteSyncSnapshot(
    equipment: const [],
    cases: const [],
    catalog: EquipmentCatalog.empty,
    revisions: const {},
    serverTime: DateTime.utc(2026, 7, 27),
  );

  @override
  Future<SyncApplyResult> applyOperation(SyncOperation operation) async {
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
  Future<void> signOut() async {}
}
