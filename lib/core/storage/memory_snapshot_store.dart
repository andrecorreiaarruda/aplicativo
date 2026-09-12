import '../../data/sync/sync_operation.dart';
import 'local_snapshot_store.dart';
import 'outbox_mutation.dart';
import 'async_mutex.dart';

class MemorySnapshotStore implements LocalSnapshotStore {
  final _mutex = AsyncMutex();
  final Map<String, String> _snapshots = {};
  final Map<String, SyncOperation> _operations = {};
  final Map<String, String> _metadata = {};

  @override
  String get storageLabel => 'Memória temporária';

  @override
  Future<String?> readSnapshot(String namespace) async => _snapshots[namespace];

  @override
  Future<void> writeSnapshot(String namespace, String value) async {
    _snapshots[namespace] = value;
  }

  @override
  Future<void> removeSnapshot(String namespace) async {
    _snapshots.remove(namespace);
  }

  @override
  Future<void> commitMutation({
    required String namespace,
    String? snapshot,
    List<SyncOperation> operations = const [],
    SyncOperation? completed,
    int? revision,
  }) => _mutex.run(() async {
    final next = mutateOutbox(
      await pendingOperations(namespace),
      namespace,
      operations,
      completed,
      revision,
    );
    if (snapshot != null) _snapshots[namespace] = snapshot;
    _operations.removeWhere((_, item) => item.namespace == namespace);
    for (final item in next) {
      _operations[item.id] = SyncOperation.fromRow(item.toRow());
    }
  });

  @override
  Future<SyncOperation?> claimOperation(String operationId) =>
      _mutex.run(() async {
        final item = _operations[operationId];
        if (item == null) return null;
        final claimed = item.copyWith(
          attemptCount: item.attemptCount + 1,
          lastAttemptAt: DateTime.now(),
        );
        _operations[operationId] = claimed;
        return claimed;
      });

  @override
  Future<void> enqueue(SyncOperation operation) =>
      commitMutation(namespace: operation.namespace, operations: [operation]);

  @override
  Future<List<SyncOperation>> pendingOperations(String namespace) async {
    final result =
        _operations.values.where((item) => item.namespace == namespace).toList()
          ..sort((a, b) => a.queueOrder.compareTo(b.queueOrder));
    return result.map((item) => SyncOperation.fromRow(item.toRow())).toList();
  }

  @override
  Future<int> pendingCount(String namespace) async =>
      _operations.values.where((item) => item.namespace == namespace).length;

  @override
  Future<void> recordFailure(
    String operationId, {
    required String? error,
  }) async {
    final current = _operations[operationId];
    if (current == null) return;
    _operations[operationId] = SyncOperation(
      id: current.id,
      namespace: current.namespace,
      entityType: current.entityType,
      entityId: current.entityId,
      operation: current.operation,
      payload: current.payload,
      createdAt: current.createdAt,
      attemptCount: current.attemptCount,
      queueOrder: current.queueOrder,
      lastAttemptAt: DateTime.now(),
      lastError: error,
    );
  }

  @override
  Future<void> removeOperation(String operationId) async {
    _operations.remove(operationId);
  }

  @override
  Future<String?> readMetadata(String namespace, String key) async =>
      _metadata['$namespace::$key'];

  @override
  Future<void> writeMetadata(String namespace, String key, String value) async {
    _metadata['$namespace::$key'] = value;
  }

  @override
  Future<void> close() async {}
}
