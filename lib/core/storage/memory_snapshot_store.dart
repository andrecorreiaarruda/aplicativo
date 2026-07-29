import '../../data/sync/sync_operation.dart';
import 'local_snapshot_store.dart';

class MemorySnapshotStore implements LocalSnapshotStore {
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
  Future<void> enqueue(SyncOperation operation) async {
    _operations[operation.id] = operation;
  }

  @override
  Future<List<SyncOperation>> pendingOperations(String namespace) async {
    final result =
        _operations.values.where((item) => item.namespace == namespace).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  @override
  Future<int> pendingCount(String namespace) async =>
      _operations.values.where((item) => item.namespace == namespace).length;

  @override
  Future<void> markAttempt(String operationId, {required String? error}) async {
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
      attemptCount: current.attemptCount + 1,
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
