import 'service_case.dart';

/// Cálculos de tempo de um atendimento feitos no cliente.
///
/// Estes valores deixaram de ser digitados pelo técnico. A divisão de
/// responsabilidade é deliberada:
///
///  - **Tempo técnico** (aqui): soma das sessões encerradas do diário. É
///    aritmética pura, sem constante de calibração, então pode ser
///    calculada offline sem risco de divergir do servidor.
///  - **Indisponibilidade** (só no servidor, migration 0010): depende dos
///    pesos por impacto operacional, que são valores de calibração e
///    podem ser reajustados. Manter essa regra em um único lugar evita
///    que um reajuste feito de um lado só produza números divergentes
///    silenciosamente. O app não a reimplementa: exibe o valor que o
///    servidor gravou, ou indica que ainda será calculado.
class ServiceTimeMetrics {
  const ServiceTimeMetrics._();

  /// Tempo técnico: soma das sessões ENCERRADAS do diário.
  ///
  /// Sessões sem horário de fim têm duração indeterminada e são
  /// ignoradas — um atendimento não pode ser concluído nesse estado, então
  /// isso só afeta a exibição de um atendimento ainda em andamento.
  static int serviceMinutes(List<ServiceProgressEntry> entries) {
    var total = 0;
    for (final entry in entries) {
      final duration = entry.duration;
      if (duration != null) total += duration.inMinutes;
    }
    return total;
  }

  /// Quantos minutos de máquina parada para cada minuto de trabalho
  /// técnico, a partir dos valores já gravados. Nulo quando algum dos dois
  /// não está disponível — inclusive enquanto a indisponibilidade ainda
  /// não foi calculada pelo servidor — ou quando não há tempo técnico
  /// registrado, caso em que a razão seria indefinida, não zero.
  static double? downtimeToServiceRatio({
    required int? downtimeMinutes,
    required int? serviceMinutes,
  }) {
    if (downtimeMinutes == null) return null;
    if (serviceMinutes == null || serviceMinutes <= 0) return null;
    return downtimeMinutes / serviceMinutes;
  }
}
