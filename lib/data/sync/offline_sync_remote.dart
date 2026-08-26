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

  /// Aciona a indexação semântica (embedding) de um atendimento já
  /// sincronizado e marcado como resolvido. É uma operação de
  /// enriquecimento best-effort: uma falha aqui não deve desfazer nem
  /// bloquear a sincronização do atendimento em si, que já foi
  /// confirmada pelo servidor antes desta chamada.
  Future<void> indexResolvedCase(String serviceCaseId);

  Future<void> signOut();
}
