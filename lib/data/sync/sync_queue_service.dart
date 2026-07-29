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
    final queued = await pending();
    final sameEntity = queued
        .where(
          (item) => item.entityType == entityType && item.entityId == entityId,
        )
        .toList(growable: false);

    var createdAt = DateTime.now();
    var baseRevision = (payload['_base_revision'] as num?)?.toInt() ?? 0;
    if (sameEntity.isNotEmpty) {
      sameEntity.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      createdAt = sameEntity.first.createdAt;
      baseRevision = sameEntity.first.expectedRevision;
      for (final previous in sameEntity) {
        await _store.removeOperation(previous.id);
      }
    }

    final compactedPayload = <String, dynamic>{
      ...payload,
      '_base_revision': baseRevision,
    };
    final item = SyncOperation(
      id: _uuid.v4(),
      namespace: _namespace,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: compactedPayload,
      createdAt: createdAt,
    );
    await _store.enqueue(item);
    return item;
  }

  Future<List<SyncOperation>> pending() => _store.pendingOperations(_namespace);

  Future<int> pendingCount() => _store.pendingCount(_namespace);

  Future<void> markFailed(SyncOperation operation, Object error) =>
      _store.markAttempt(operation.id, error: error.toString());

  Future<void> markCompleted(SyncOperation operation) =>
      _store.removeOperation(operation.id);
}
