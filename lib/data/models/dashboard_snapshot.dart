import 'equipment.dart';
import 'service_case.dart';
import 'service_time_metrics.dart';

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.totalEquipment,
    required this.openCases,
    required this.resolvedCases,
    required this.stoppedEquipment,
    required this.totalDowntimeMinutes,
    required this.averageServiceMinutes,
    required this.totalServiceMinutes,
    required this.downtimeToServiceRatio,
    required this.casesAwaitingDowntime,
  });

  final int totalEquipment;
  final int openCases;
  final int resolvedCases;
  final int stoppedEquipment;
  final int totalDowntimeMinutes;
  final double averageServiceMinutes;

  /// Tempo técnico acumulado nos atendimentos encerrados.
  final int totalServiceMinutes;

  /// Minutos de equipamento parado para cada minuto de trabalho técnico.
  /// Calculada apenas sobre atendimentos que já têm AMBOS os tempos, para
  /// que numerador e denominador cubram exatamente o mesmo conjunto de
  /// casos. Nula quando ainda não há base suficiente.
  final double? downtimeToServiceRatio;

  /// Atendimentos resolvidos cuja indisponibilidade ainda não foi
  /// calculada pelo servidor (tipicamente concluídos offline e ainda não
  /// sincronizados). Ficam de fora dos totais de indisponibilidade e da
  /// razão: contá-los como zero faria a base parecer completa quando não
  /// está.
  final int casesAwaitingDowntime;

  factory DashboardSnapshot.from({
    required List<Equipment> equipment,
    required List<ServiceCase> cases,
  }) {
    final resolved = cases.where((item) => item.isResolved).toList();
    final serviceDurations = resolved
        .map((item) => item.serviceMinutes)
        .whereType<int>()
        .toList();
    final average = serviceDurations.isEmpty
        ? 0.0
        : serviceDurations.reduce((a, b) => a + b) / serviceDurations.length;

    final totalService = serviceDurations.fold(0, (a, b) => a + b);

    // Indisponibilidade nula significa "ainda não calculada pelo
    // servidor", não "zero minutos parado". Tratá-la como zero
    // subestimaria o total e, pior, a razão abaixo — cujo denominador
    // contaria o tempo técnico de casos que o numerador ignora.
    final withDowntime = resolved
        .where((item) => item.downtimeMinutes != null)
        .toList();
    final totalDowntime = withDowntime
        .map((item) => item.downtimeMinutes!)
        .fold(0, (a, b) => a + b);
    final serviceForRatio = withDowntime
        .map((item) => item.serviceMinutes)
        .whereType<int>()
        .fold(0, (a, b) => a + b);

    return DashboardSnapshot(
      totalEquipment: equipment.length,
      openCases: cases.where((item) => !item.isResolved).length,
      resolvedCases: resolved.length,
      stoppedEquipment: equipment
          .where((item) => item.status == 'stopped')
          .length,
      totalDowntimeMinutes: totalDowntime,
      averageServiceMinutes: average,
      totalServiceMinutes: totalService,
      downtimeToServiceRatio: withDowntime.isEmpty
          ? null
          : ServiceTimeMetrics.downtimeToServiceRatio(
              downtimeMinutes: totalDowntime,
              serviceMinutes: serviceForRatio,
            ),
      casesAwaitingDowntime: resolved.length - withDowntime.length,
    );
  }
}
