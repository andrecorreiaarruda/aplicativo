import 'dart:convert';

class SyncOperation {
  const SyncOperation({
    required this.id,
    required this.namespace,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.lastError,
  });

  final String id;
  final String namespace;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? lastError;

  int get expectedRevision => (payload['_base_revision'] as num?)?.toInt() ?? 0;

  String get payloadJson => jsonEncode(payload);

  factory SyncOperation.fromRow(Map<String, Object?> row) {
    return SyncOperation(
      id: row['id'] as String,
      namespace: row['namespace'] as String,
      entityType: row['entity_type'] as String,
      entityId: row['entity_id'] as String,
      operation: row['operation'] as String,
      payload: Map<String, dynamic>.from(
        jsonDecode(row['payload'] as String) as Map,
      ),
      createdAt: DateTime.parse(row['created_at'] as String),
      attemptCount: (row['attempt_count'] as num?)?.toInt() ?? 0,
      lastAttemptAt: _parseDate(row['last_attempt_at']),
      lastError: row['last_error'] as String?,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'namespace': namespace,
    'entity_type': entityType,
    'entity_id': entityId,
    'operation': operation,
    'payload': payloadJson,
    'created_at': createdAt.toUtc().toIso8601String(),
    'attempt_count': attemptCount,
    'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
    'last_error': lastError,
  };

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class SyncApplyResult {
  const SyncApplyResult({
    required this.status,
    this.revision,
    this.message,
    this.conflictId,
  });

  final String status;
  final int? revision;
  final String? message;
  final String? conflictId;

  bool get applied => status == 'applied' || status == 'duplicate';
  bool get conflict => status == 'conflict';

  factory SyncApplyResult.fromJson(Map<String, dynamic> json) {
    return SyncApplyResult(
      status: json['status'] as String? ?? 'error',
      revision: (json['revision'] as num?)?.toInt(),
      message: json['message'] as String?,
      conflictId: json['conflict_id'] as String?,
    );
  }
}

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.pendingCount,
    required this.storageLabel,
    this.conflictCount = 0,
    this.lastSuccessfulSync,
    this.lastError,
  });

  final int pendingCount;
  final int conflictCount;
  final String storageLabel;
  final DateTime? lastSuccessfulSync;
  final String? lastError;

  bool get hasPendingChanges => pendingCount > 0;
  bool get hasConflicts => conflictCount > 0;
}

class SyncConflictException implements Exception {
  const SyncConflictException(this.message, {this.conflictId});

  final String message;
  final String? conflictId;

  @override
  String toString() => message;
}
