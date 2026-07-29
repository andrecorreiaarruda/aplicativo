import 'equipment.dart';
import 'service_case.dart';

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.totalEquipment,
    required this.openCases,
    required this.resolvedCases,
    required this.stoppedEquipment,
    required this.totalDowntimeMinutes,
    required this.averageServiceMinutes,
  });

  final int totalEquipment;
  final int openCases;
  final int resolvedCases;
  final int stoppedEquipment;
  final int totalDowntimeMinutes;
  final double averageServiceMinutes;

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

    return DashboardSnapshot(
      totalEquipment: equipment.length,
      openCases: cases.where((item) => !item.isResolved).length,
      resolvedCases: resolved.length,
      stoppedEquipment: equipment
          .where((item) => item.status == 'stopped')
          .length,
      totalDowntimeMinutes: resolved
          .map((item) => item.downtimeMinutes ?? 0)
          .fold(0, (a, b) => a + b),
      averageServiceMinutes: average,
    );
  }
}
