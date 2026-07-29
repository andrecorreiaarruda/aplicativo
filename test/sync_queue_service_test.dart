import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/data/sync/sync_queue_service.dart';

void main() {
  test('fila preserva alterações na ordem em que foram registradas', () async {
    final store = MemorySnapshotStore();
    final queue = SyncQueueService(
      store: store,
      namespace: 'organization-test',
    );

    final first = await queue.enqueue(
      entityType: 'customer',
      entityId: 'customer-1',
      operation: 'upsert',
      payload: {'name': 'Hospital A'},
    );
    final second = await queue.enqueue(
      entityType: 'equipment',
      entityId: 'equipment-1',
      operation: 'upsert',
      payload: {'serial_number': 'SERIAL-001'},
    );

    final pending = await queue.pending();
    expect(pending, hasLength(2));
    expect(pending.first.id, first.id);
    expect(pending.last.id, second.id);

    await queue.markCompleted(first);
    expect(await queue.pendingCount(), 1);
  });

  test(
    'fila compacta alterações repetidas e preserva a revisão-base',
    () async {
      final store = MemorySnapshotStore();
      final queue = SyncQueueService(
        store: store,
        namespace: 'organization-compact',
      );

      await queue.enqueue(
        entityType: 'customer',
        entityId: 'customer-1',
        operation: 'upsert',
        payload: {'name': 'Hospital A', '_base_revision': 4},
      );
      await queue.enqueue(
        entityType: 'customer',
        entityId: 'customer-1',
        operation: 'upsert',
        payload: {'name': 'Hospital A atualizado', '_base_revision': 9},
      );

      final pending = await queue.pending();
      expect(pending, hasLength(1));
      expect(pending.single.payload['name'], 'Hospital A atualizado');
      expect(pending.single.expectedRevision, 4);
    },
  );
}
