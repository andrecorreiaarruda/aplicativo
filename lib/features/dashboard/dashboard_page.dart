import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/dashboard_snapshot.dart';
import '../../data/models/service_case.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/status_chip.dart';
import '../shell/service_log_controller.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.controller,
    required this.onOpenCases,
    required this.onOpenAssistant,
  });

  final ServiceLogController controller;
  final VoidCallback onOpenCases;
  final VoidCallback onOpenAssistant;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.dashboard;
    final recentCases = controller.cases.take(5).toList();
    return ListView(
      key: const PageStorageKey('dashboard-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        SectionHeader(
          title: 'Visão operacional',
          subtitle:
              'Equipamentos, atendimentos ativos e conhecimento técnico consolidado.',
          action: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenAssistant,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Consultar assistente'),
              ),
              FilledButton.icon(
                onPressed: onOpenCases,
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('Novo atendimento'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _MetricGrid(snapshot: snapshot),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 940;
            final recent = _RecentCases(
              cases: recentCases,
              onOpenCases: onOpenCases,
            );
            final health = _OperationalPanel(
              snapshot: snapshot,
              totalCases: controller.cases.length,
            );
            if (!wide) {
              return Column(
                children: [recent, const SizedBox(height: 18), health],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: recent),
                const SizedBox(width: 18),
                Expanded(flex: 3, child: health),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.snapshot});
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricData(
        icon: Icons.precision_manufacturing_rounded,
        label: 'Equipamentos',
        value: '${snapshot.totalEquipment}',
        detail: '${snapshot.stoppedEquipment} parados',
        accent: OrionColors.blue,
      ),
      _MetricData(
        icon: Icons.build_circle_outlined,
        label: 'Atendimentos ativos',
        value: '${snapshot.openCases}',
        detail: '${snapshot.resolvedCases} resolvidos',
        accent: OrionColors.warning,
      ),
      _MetricData(
        icon: Icons.timer_outlined,
        label: 'Tempo médio técnico',
        value: _duration(snapshot.averageServiceMinutes.round()),
        detail: 'Casos resolvidos',
        accent: OrionColors.navy,
      ),
      _MetricData(
        icon: Icons.power_settings_new_rounded,
        label: 'Indisponibilidade',
        value: _duration(snapshot.totalDowntimeMinutes),
        detail: 'Acumulada no histórico',
        accent: OrionColors.danger,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final item in items)
              SizedBox(width: width, child: _MetricCard(data: item)),
          ],
        );
      },
    );
  }

  static String _duration(int minutes) {
    if (minutes <= 0) return '0 min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return hours == 0 ? '$minutes min' : '${hours}h ${remainder}min';
  }
}

class _MetricData {
  const _MetricData({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.accent,
  });
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color accent;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});
  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: data.accent.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(data.icon, color: data.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.label,
                      style: const TextStyle(color: OrionColors.muted)),
                  const SizedBox(height: 3),
                  Text(
                    data.value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Text(
                    data.detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: OrionColors.muted,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentCases extends StatelessWidget {
  const _RecentCases({required this.cases, required this.onOpenCases});
  final List<ServiceCase> cases;
  final VoidCallback onOpenCases;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Atendimentos recentes',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                TextButton(
                    onPressed: onOpenCases, child: const Text('Ver todos')),
              ],
            ),
            const SizedBox(height: 8),
            if (cases.isEmpty)
              const EmptyState(
                icon: Icons.assignment_outlined,
                title: 'Nenhum atendimento',
                message: 'Os atendimentos registrados aparecerão aqui.',
              )
            else
              ...cases.map((item) => _RecentCaseRow(item: item)),
          ],
        ),
      ),
    );
  }
}

class _RecentCaseRow extends StatelessWidget {
  const _RecentCaseRow({required this.item});
  final ServiceCase item;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM/yyyy HH:mm').format(item.openedAt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: OrionColors.paleCyan,
            foregroundColor: OrionColors.blue,
            child: Text('#${item.caseNumber}'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.reportedFailure,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.equipmentLabel} · $date',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: OrionColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(value: item.status, compact: true),
        ],
      ),
    );
  }
}

class _OperationalPanel extends StatelessWidget {
  const _OperationalPanel({required this.snapshot, required this.totalCases});
  final DashboardSnapshot snapshot;
  final int totalCases;

  @override
  Widget build(BuildContext context) {
    final resolutionRate =
        totalCases == 0 ? 0.0 : snapshot.resolvedCases / totalCases;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Qualidade da base',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 18),
            _ProgressLine(
              label: 'Casos encerrados',
              value: resolutionRate,
              caption: '${(resolutionRate * 100).round()}%',
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OrionColors.paleCyan,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined, color: OrionColors.blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Priorize causa-raiz, validação final e nível de confiança. Esses campos aumentam a utilidade da busca futura.',
                      style: TextStyle(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.value,
    required this.caption,
  });
  final String label;
  final double value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(caption, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: value,
          minHeight: 9,
          borderRadius: BorderRadius.circular(99),
        ),
      ],
    );
  }
}
