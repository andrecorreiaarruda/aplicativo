import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/data/models/equipment.dart';
import 'package:servicelog_ai/data/models/service_case.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/data/repositories/offline_first_service_log_repository.dart';
import 'package:servicelog_ai/data/sync/offline_sync_remote.dart';
import 'package:servicelog_ai/data/sync/sync_operation.dart';

OfflineFirstServiceLogRepository _repo(
  MemorySnapshotStore store,
  _Remote remote,
) => OfflineFirstServiceLogRepository(
  local: DemoServiceLogRepository.offlineMirror(storage: store, namespace: 'a'),
  store: store,
  namespace: 'a',
  remote: remote,
);

void main() {
  test(
    'edição durante envio não espera rede e sucessora recebe revisão confirmada',
    () async {
      final store = MemorySnapshotStore();
      final remote = _Remote()..pauseApply = Completer<void>();
      final repository = _repo(store, remote);
      final id = await repository.createCustomer(
        const CustomerDraft(name: 'Original'),
      );
      final sync = repository.syncPendingChanges();
      await remote.applyStarted.future;
      await repository.updateCustomer(
        id,
        const CustomerDraft(name: 'Última edição'),
      );
      expect(await store.pendingCount('a'), 2);
      remote.pauseApply!.complete();
      await sync;
      expect(
        (await repository.fetchEquipmentCatalog()).customers.single.name,
        'Última edição',
      );
      expect((await store.pendingOperations('a')).single.expectedRevision, 1);
      await repository.syncPendingChanges();
      expect(remote.calls.last.expectedRevision, 1);
      expect(remote.names[id], 'Última edição');
      expect(await store.pendingCount('a'), 0);
    },
  );

  test(
    'timeout após aplicação remota repete mesmo ID antes de enviar sucessora',
    () async {
      final store = MemorySnapshotStore();
      final remote = _Remote()..loseResponse = true;
      var repository = _repo(store, remote);
      final id = await repository.createCustomer(
        const CustomerDraft(name: 'Original'),
      );
      await expectLater(repository.syncPendingChanges(), throwsStateError);
      final original = (await store.pendingOperations('a')).single;
      repository = _repo(store, remote);
      await repository.updateCustomer(
        id,
        const CustomerDraft(name: 'Depois do timeout'),
      );
      await repository.syncPendingChanges();
      expect(remote.calls[1].id, original.id);
      expect(remote.calls[1].payloadJson, original.payloadJson);
      expect(remote.revisions[id], 2);
      expect(remote.names[id], 'Depois do timeout');
      expect(await store.pendingCount('a'), 0);
    },
  );

  test(
    'alteração durante pull permanece visível e sobrevive nova abertura',
    () async {
      final store = MemorySnapshotStore();
      final remote = _Remote()..pausePull = Completer<void>();
      final repository = _repo(store, remote);
      final sync = repository.syncPendingChanges();
      await remote.pullStarted.future;
      await repository.createCustomer(
        const CustomerDraft(name: 'Durante pull'),
      );
      remote.pausePull!.complete();
      await sync;
      expect(
        (await _repo(
          store,
          remote,
        ).fetchEquipmentCatalog()).customers.single.name,
        'Durante pull',
      );
      expect(await store.pendingCount('a'), 1);
      await repository.syncPendingChanges();
      expect(remote.names.values.single, 'Durante pull');
      expect(await store.pendingCount('a'), 0);
    },
  );
}

class _Remote implements OfflineSyncRemote {
  final applyStarted = Completer<void>();
  final pullStarted = Completer<void>();
  Completer<void>? pauseApply;
  Completer<void>? pausePull;
  bool loseResponse = false;
  final calls = <SyncOperation>[];
  final receipts = <String, int>{};
  final revisions = <String, int>{};
  final names = <String, String>{};

  @override
  Future<SyncApplyResult> applyOperation(SyncOperation operation) async {
    calls.add(operation);
    if (!applyStarted.isCompleted) applyStarted.complete();
    final duplicate = receipts[operation.id];
    if (duplicate != null) {
      return SyncApplyResult(status: 'duplicate', revision: duplicate);
    }
    final oldRevision = revisions[operation.entityId] ?? 0;
    if (operation.expectedRevision != oldRevision) {
      return SyncApplyResult(status: 'conflict', revision: oldRevision);
    }
    names[operation.entityId] = operation.payload['name'] as String;
    receipts[operation.id] = oldRevision + 1;
    revisions[operation.entityId] = oldRevision + 1;
    await pauseApply?.future;
    if (loseResponse) {
      loseResponse = false;
      throw StateError('Response lost');
    }
    return SyncApplyResult(status: 'applied', revision: oldRevision + 1);
  }

  @override
  Future<RemoteSyncSnapshot> pullSnapshot() async {
    if (!pullStarted.isCompleted) pullStarted.complete();
    final snapshot = RemoteSyncSnapshot(
      equipment: const [],
      cases: const [],
      catalog: EquipmentCatalog(
        models: const [],
        sites: const [],
        customers: names.entries
            .map((e) => CustomerOption(id: e.key, name: e.value))
            .toList(),
      ),
      revisions: revisions.map(
        (key, value) => MapEntry('customer:$key', value),
      ),
      serverTime: DateTime.now(),
    );
    await pausePull?.future;
    return snapshot;
  }

  @override
  Future<void> indexResolvedCase(String id) async {}
  @override
  Future<List<SimilarCaseResult>> searchSimilarCases(
    SimilarCaseQuery query,
  ) async => [];
  @override
  Future<void> signOut() async {}
}
