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
    // Um leitor por download: as revisões são coletadas pelas próprias
    // consultas, e um leitor compartilhado misturaria as de dois
    // downloads que se cruzassem.
    final reader = SupabaseServiceLogRepository(client: _client);
    final values = await Future.wait<dynamic>([
      reader.fetchEquipments(),
      reader.fetchCases(),
      reader.fetchEquipmentCatalog(),
    ]);

    return RemoteSyncSnapshot(
      equipment: values[0],
      cases: values[1],
      catalog: values[2],
      revisions: reader.takeRevisions(),
      serverTime: DateTime.now().toUtc(),
    );
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
