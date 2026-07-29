import '../../data/sync/sync_operation.dart';

abstract class LocalSnapshotStore {
  String get storageLabel;

  Future<String?> readSnapshot(String namespace);
  Future<void> writeSnapshot(String namespace, String value);
  Future<void> removeSnapshot(String namespace);

  Future<void> enqueue(SyncOperation operation);
  Future<List<SyncOperation>> pendingOperations(String namespace);
  Future<int> pendingCount(String namespace);
  Future<void> markAttempt(String operationId, {required String? error});
  Future<void> removeOperation(String operationId);

  Future<String?> readMetadata(String namespace, String key);
  Future<void> writeMetadata(String namespace, String key, String value);

  Future<void> close();
}
