import '../models/equipment.dart';
import '../models/service_case.dart';
import '../sync/sync_conflict.dart';
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

  /// Arquivamento. O registro sai das listagens mas permanece no banco,
  /// preservando o histórico técnico vinculado a ele. Lança [StateError]
  /// com a contagem de dependentes quando o arquivamento é recusado.
  Future<void> archiveCustomer(String id);
  Future<void> archiveEquipment(String id);
  Future<void> archiveCase(String id);

  Future<void> restoreCustomer(String id);
  Future<void> restoreEquipment(String id);
  Future<void> restoreCase(String id);

  Future<ArchivedRecords> fetchArchived();

  /// Exclusão definitiva, a partir de Arquivados. Ao contrário do
  /// arquivamento, não tem volta: a linha sai do banco.
  ///
  /// Só se aplica a registro já arquivado e sem nenhum dependente —
  /// inclusive dependentes arquivados, que o arquivamento ignora mas cuja
  /// remoção em cascata deixaria histórico órfão. Lança [StateError] com
  /// a contagem quando é recusada.
  Future<void> purgeCustomer(String id);
  Future<void> purgeEquipment(String id);
  Future<void> purgeCase(String id);

  Future<void> signOut();
}

abstract class SyncAwareRepository {
  Future<SyncStatusSnapshot> fetchSyncStatus();
  Future<void> syncPendingChanges();

  /// Operações paradas na fila por divergência de revisão. Enquanto
  /// houver uma, o download não é aplicado: a fila pendente protege as
  /// alterações locais de serem sobrepostas, então um conflito não
  /// resolvido congela a entrada de novidades do servidor.
  Future<List<SyncConflict>> fetchConflicts();

  /// Aplica a decisão do usuário sobre um conflito. Não sincroniza: a
  /// tela decide quando enviar, para poder resolver vários de uma vez.
  Future<void> resolveConflict(
    String operationId,
    ConflictResolution resolution,
  );
}
