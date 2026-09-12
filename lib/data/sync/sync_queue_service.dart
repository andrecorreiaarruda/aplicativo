import 'package:uuid/uuid.dart';

import '../../core/storage/local_snapshot_store.dart';
import 'sync_operation.dart';

class SyncQueueService {
  SyncQueueService({
    required LocalSnapshotStore store,
    required String namespace,
    Uuid? uuid,
  }) : _store = store,
       _namespace = namespace,
       _uuid = uuid ?? const Uuid();

  final LocalSnapshotStore _store;
  final String _namespace;
  final Uuid _uuid;

  Future<SyncOperation> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final item = SyncOperation(
      id: _uuid.v4(),
      namespace: _namespace,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
      createdAt: DateTime.now(),
    );
    await _store.commitMutation(namespace: _namespace, operations: [item]);
    return item;
  }

  Future<List<SyncOperation>> pending() => _store.pendingOperations(_namespace);

  Future<int> pendingCount() => _store.pendingCount(_namespace);

  Future<void> markFailed(SyncOperation operation, Object error) =>
      _store.recordFailure(operation.id, error: error.toString());

  Future<void> markCompleted(SyncOperation operation) =>
      _store.removeOperation(operation.id);
}
