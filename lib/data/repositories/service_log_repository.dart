import '../models/equipment.dart';
import '../models/service_case.dart';
import '../sync/sync_operation.dart';

abstract class ServiceLogRepository {
  bool get isDemo;

  Future<List<Equipment>> fetchEquipments();
  Future<List<ServiceCase>> fetchCases();
  Future<EquipmentCatalog> fetchEquipmentCatalog();

  Future<String> createEquipmentModel(EquipmentModelDraft draft);
  Future<String> createCustomer(CustomerDraft draft);
  Future<void> updateCustomer(String id, CustomerDraft draft);
  Future<String> createSite(SiteDraft draft);
  Future<void> updateSite(String id, SiteDraft draft);
  Future<String> createCustomerSite(CustomerSiteDraft draft);
  Future<void> createEquipment(EquipmentDraft draft);
  Future<void> updateEquipment(String id, EquipmentDraft draft);
  Future<void> saveCase(ServiceCaseDraft draft);
  Future<List<SimilarCaseResult>> searchSimilarCases(SimilarCaseQuery query);
  Future<void> signOut();
}

abstract class SyncAwareRepository {
  Future<SyncStatusSnapshot> fetchSyncStatus();
  Future<void> syncPendingChanges();
}
