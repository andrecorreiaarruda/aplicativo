import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/equipment.dart';
import '../models/service_case.dart';
import '../repositories/supabase_service_log_repository.dart';
import 'offline_sync_remote.dart';
import 'sync_operation.dart';

class SupabaseSyncGateway implements OfflineSyncRemote {
  SupabaseSyncGateway({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client,
      _repository = SupabaseServiceLogRepository(
        client: client ?? Supabase.instance.client,
      );

  final SupabaseClient _client;
  final SupabaseServiceLogRepository _repository;

  @override
  Future<SyncApplyResult> applyOperation(SyncOperation operation) async {
    final response = await _client.rpc(
      'apply_offline_operation',
      params: {
        'p_operation_id': operation.id,
        'p_entity_type': operation.entityType,
        'p_entity_id': operation.entityId,
        'p_operation': operation.operation,
        'p_payload': operation.payload,
        'p_expected_revision': operation.expectedRevision,
      },
    );
    return SyncApplyResult.fromJson(_map(response));
  }

  @override
  Future<RemoteSyncSnapshot> pullSnapshot() async {
    final values = await Future.wait<dynamic>([
      _repository.fetchEquipments(),
      _repository.fetchCases(),
      _repository.fetchEquipmentCatalog(),
      _revisionRows('customers'),
      _revisionRows('sites'),
      _revisionRows('equipment_models'),
      _revisionRows('equipments'),
      _revisionRows('service_cases'),
    ]);

    final revisions = <String, int>{};
    _appendRevisions(revisions, 'customer', values[3]);
    _appendRevisions(revisions, 'site', values[4]);
    _appendRevisions(revisions, 'equipment_model', values[5]);
    _appendRevisions(revisions, 'equipment', values[6]);
    _appendRevisions(revisions, 'service_case', values[7]);

    return RemoteSyncSnapshot(
      equipment: values[0],
      cases: values[1],
      catalog: values[2],
      revisions: revisions,
      serverTime: DateTime.now().toUtc(),
    );
  }

  Future<List<dynamic>> _revisionRows(String table) async {
    final response = await _client
        .from(table)
        .select('id, sync_revision')
        .isFilter('deleted_at', null);
    return response as List<dynamic>;
  }

  static void _appendRevisions(
    Map<String, int> target,
    String entityType,
    dynamic rows,
  ) {
    if (rows is! List) return;
    for (final row in rows) {
      final json = _map(row);
      final id = json['id'] as String?;
      if (id == null) continue;
      target['$entityType:$id'] = (json['sync_revision'] as num?)?.toInt() ?? 1;
    }
  }

  @override
  Future<List<SimilarCaseResult>> searchSimilarCases(SimilarCaseQuery query) =>
      _repository.searchSimilarCases(query);

  @override
  Future<void> indexResolvedCase(String serviceCaseId) =>
      _repository.indexResolvedCase(serviceCaseId);

  @override
  Future<ArchivedRecords> fetchArchived() => _repository.fetchArchived();

  @override
  Future<void> signOut() => _client.auth.signOut();

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) return _map(value.first);
    return <String, dynamic>{};
  }
}
