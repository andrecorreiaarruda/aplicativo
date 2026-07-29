import '../models/equipment.dart';
import '../models/service_case.dart';
import 'sync_operation.dart';

class RemoteSyncSnapshot {
  const RemoteSyncSnapshot({
    required this.equipment,
    required this.cases,
    required this.catalog,
    required this.revisions,
    required this.serverTime,
  });

  final List<Equipment> equipment;
  final List<ServiceCase> cases;
  final EquipmentCatalog catalog;
  final Map<String, int> revisions;
  final DateTime serverTime;
}

abstract class OfflineSyncRemote {
  Future<SyncApplyResult> applyOperation(SyncOperation operation);
  Future<RemoteSyncSnapshot> pullSnapshot();
  Future<List<SimilarCaseResult>> searchSimilarCases(SimilarCaseQuery query);
  Future<void> signOut();
}
