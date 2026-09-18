import 'sync_operation.dart';

/// Prefixo gravado em `last_error` quando o servidor recusa a operação por
/// divergência de revisão. É o que distingue um conflito — que espera
/// decisão do usuário — de uma falha técnica, que o próximo envio repete.
const String conflictErrorPrefix = 'CONFLICT:';

/// Como o usuário resolveu a divergência.
enum ConflictResolution {
  /// Reenvia a alteração local sem exigir revisão, sobrescrevendo o que
  /// está no servidor.
  keepLocal,

  /// Descarta a alteração local. O próximo download traz a versão do
  /// servidor por cima.
  discardLocal,
}

/// Uma operação parada na fila porque o registro mudou no servidor entre a
/// última sincronização e a edição feita aqui.
class SyncConflict {
  const SyncConflict({
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.recordLabel,
    required this.message,
    this.detectedAt,
    this.attemptCount = 0,
  });

  final String operationId;
  final String entityType;
  final String entityId;
  final String operation;

  /// Descrição do registro resolvida no espelho local — o payload sozinho
  /// não serve: uma operação de arquivamento carrega apenas o id.
  final String recordLabel;

  /// Texto devolvido pelo servidor, já sem o prefixo de conflito.
  final String message;

  final DateTime? detectedAt;
  final int attemptCount;

  /// Constrói o conflito a partir da operação parada, ou devolve nulo se
  /// ela não estiver em conflito.
  static SyncConflict? fromOperation(
    SyncOperation operation, {
    required String recordLabel,
  }) {
    final error = operation.lastError;
    if (error == null || !error.startsWith(conflictErrorPrefix)) return null;
    return SyncConflict(
      operationId: operation.id,
      entityType: operation.entityType,
      entityId: operation.entityId,
      operation: operation.operation,
      recordLabel: recordLabel,
      message: error.substring(conflictErrorPrefix.length).trim(),
      detectedAt: operation.lastAttemptAt,
      attemptCount: operation.attemptCount,
    );
  }

  /// Nome do tipo de registro, para o cabeçalho do cartão.
  String get entityLabel => switch (entityType) {
    'customer' => 'Cliente',
    'site' => 'Local',
    'equipment' => 'Equipamento',
    'equipment_model' => 'Modelo',
    'service_case' => 'Atendimento',
    _ => 'Registro',
  };

  /// O que a alteração local pretendia fazer.
  String get actionLabel => switch (operation) {
    'archive' => 'Arquivamento',
    'restore' => 'Restauração',
    _ => 'Edição',
  };

  /// Texto do botão que mantém a versão local, nomeando a ação em vez de
  /// dizer "manter" — arquivar e restaurar não são edições de conteúdo.
  String get keepLocalLabel => switch (operation) {
    'archive' => 'Arquivar assim mesmo',
    'restore' => 'Restaurar assim mesmo',
    _ => 'Manter a minha versão',
  };
}
