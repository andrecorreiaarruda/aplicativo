import '../../data/sync/sync_operation.dart';

/// Shared semantics for SQLite transactions and the explicit demo/test store.
List<SyncOperation> mutateOutbox(
  List<SyncOperation> current,
  String namespace,
  List<SyncOperation> incoming,
  SyncOperation? completed,
  int? revision,
) {
  final result = [...current];
  if (completed != null) {
    if (completed.namespace != namespace || revision == null || revision < 1) {
      throw StateError('Confirmação remota inválida.');
    }
    final index = result.indexWhere((item) => item.id == completed.id);
    if (index < 0) throw StateError('Operação confirmada não encontrada.');
    result.removeAt(index);
    for (var i = 0; i < result.length; i++) {
      final item = result[i];
      if (item.entityType == completed.entityType &&
          item.entityId == completed.entityId &&
          item.attemptCount == 0) {
        result[i] = item.copyWith(
          payload: {...item.payload, '_base_revision': revision},
        );
      }
    }
  }
  for (final item in incoming) {
    if (item.namespace != namespace) throw StateError('Namespace inválido.');
    // Once a request may have reached the server, its ID and payload must
    // survive timeouts/restarts unchanged. Only never-attempted work compacts.
    final replaceable =
        result
            .where(
              (old) =>
                  old.entityType == item.entityType &&
                  old.entityId == item.entityId &&
                  old.attemptCount == 0,
            )
            .toList()
          ..sort((a, b) => a.queueOrder.compareTo(b.queueOrder));
    final next = replaceable.isEmpty
        ? item.copyWith(
            queueOrder:
                result.fold<int>(
                  0,
                  (maximum, old) =>
                      old.queueOrder > maximum ? old.queueOrder : maximum,
                ) +
                1,
          )
        : item.copyWith(
            createdAt: replaceable.first.createdAt,
            queueOrder: replaceable.first.queueOrder,
            payload: {
              ...item.payload,
              '_base_revision': replaceable.first.expectedRevision,
            },
          );
    result.removeWhere((old) => replaceable.any((r) => r.id == old.id));
    if (result.any((old) => old.id == next.id)) {
      throw StateError('ID de operação reutilizado.');
    }
    result.add(next);
  }
  return result;
}
