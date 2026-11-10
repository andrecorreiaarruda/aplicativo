import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/data/models/equipment.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/data/sync/sync_operation.dart';

/// Armazenamento que recusa a próxima gravação, como um disco cheio.
class _FailingStore extends MemorySnapshotStore {
  bool failNext = false;

  @override
  Future<void> commitMutation({
    required String namespace,
    String? snapshot,
    List<SyncOperation> operations = const [],
    SyncOperation? completed,
    int? revision,
  }) {
    if (failNext) {
      failNext = false;
      throw StateError('disco cheio');
    }
    return super.commitMutation(
      namespace: namespace,
      snapshot: snapshot,
      operations: operations,
      completed: completed,
      revision: revision,
    );
  }
}

void main() {
  test('gravação recusada desfaz a alteração em memória', () async {
    final store = _FailingStore();
    final repository = DemoServiceLogRepository.offlineMirror(
      storage: store,
      namespace: 'rollback',
    );
    await repository.createCustomer(const CustomerDraft(name: 'Gravado'));

    store.failNext = true;
    await expectLater(
      repository.createCustomer(const CustomerDraft(name: 'Perdido')),
      throwsStateError,
    );

    final names = (await repository.fetchEquipmentCatalog()).customers.map(
      (item) => item.name,
    );
    expect(names, ['Gravado']);
    expect(await store.pendingCount('rollback'), 1);

    // E o repositório continua utilizável depois da falha.
    await repository.createCustomer(const CustomerDraft(name: 'Depois'));
    expect(
      (await repository.fetchEquipmentCatalog()).customers.map((c) => c.name),
      containsAll(['Gravado', 'Depois']),
    );
  });
}
