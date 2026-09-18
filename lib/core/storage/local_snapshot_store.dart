import '../../data/sync/sync_operation.dart';

abstract class LocalSnapshotStore {
  String get storageLabel;

  Future<String?> readSnapshot(String namespace);
  Future<void> writeSnapshot(String namespace, String value);
  Future<void> removeSnapshot(String namespace);

  /// Commits the visible state and its outbox as one indivisible operation.
  /// Acknowledgement also rebases unsent successors in the same transaction.
  Future<void> commitMutation({
    required String namespace,
    String? snapshot,
    List<SyncOperation> operations = const [],
    SyncOperation? completed,
    int? revision,
  });
  Future<SyncOperation?> claimOperation(String operationId);
  Future<void> enqueue(SyncOperation operation);
  Future<List<SyncOperation>> pendingOperations(String namespace);
  Future<int> pendingCount(String namespace);
  Future<void> recordFailure(String operationId, {required String? error});
  Future<void> removeOperation(String operationId);

  /// Troca a revisão de base de uma operação já enfileirada e limpa o erro
  /// registrado, devolvendo-a ao estado de "nunca tentada".
  ///
  /// É como um conflito é resolvido em favor da versão local: a base zero
  /// desliga a verificação de revisão no servidor, que então aceita a
  /// gravação sobrepondo o que estiver lá.
  Future<void> rebaseOperation(String operationId, {required int baseRevision});

  Future<String?> readMetadata(String namespace, String key);
  Future<void> writeMetadata(String namespace, String key, String value);

  Future<void> close();
}
