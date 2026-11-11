import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/dashboard_snapshot.dart';
import '../../data/models/service_case.dart';
import '../../shared/widgets/record_list.dart';
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
    final open = controller.cases.where((item) => !item.isResolved).take(6);
    final closed = controller.cases.where((item) => item.isResolved).take(5);

    return ListView(
      key: const PageStorageKey('dashboard-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        SectionHeader(
          title: 'Visão geral',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenAssistant,
                icon: const Icon(Icons.manage_search, size: 18),
                label: const Text('Buscar no histórico'),
              ),
              FilledButton.icon(
                onPressed: onOpenCases,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo atendimento'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(snapshot: snapshot),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            final openList = _CaseGroup(
              title: 'Em aberto',
              cases: open.toList(),
              emptyText: 'Nenhum atendimento em aberto.',
              onMore: onOpenCases,
            );
            final closedList = _CaseGroup(
              title: 'Concluídos recentemente',
              cases: closed.toList(),
              emptyText: 'Nenhum atendimento concluído ainda.',
              onMore: onOpenCases,
            );
            if (constraints.maxWidth < 980) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [openList, const SizedBox(height: 28), closedList],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: openList),
                const SizedBox(width: 24),
                Expanded(child: closedList),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Os números do período numa faixa só.
class _Metrics extends StatelessWidget {
  const _Metrics({required this.snapshot});
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Equipamentos',
        '${snapshot.totalEquipment}',
        snapshot.stoppedEquipment == 0
            ? 'nenhum parado'
            : '${snapshot.stoppedEquipment} parado'
                  '${snapshot.stoppedEquipment == 1 ? '' : 's'}',
      ),
      (
        'Em aberto',
        '${snapshot.openCases}',
        '${snapshot.resolvedCases} concluídos',
      ),
      (
        'Tempo técnico médio',
        _duration(snapshot.averageServiceMinutes.round()),
        'por atendimento concluído',
      ),
      (
        'Indisponibilidade',
        _duration(snapshot.totalDowntimeMinutes),
        _coverage(snapshot, 'somada nos concluídos'),
      ),
      (
        'Parada ÷ tempo técnico',
        _ratio(snapshot.downtimeToServiceRatio),
        snapshot.downtimeToServiceRatio == null
            ? 'ainda sem base'
            : _coverage(snapshot, 'horas paradas por hora de trabalho'),
      ),
    ];

    final palette = context.orion;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 5
            : constraints.maxWidth >= 600
            ? 3
            : 2;
        // Linhas de altura igual: num Wrap, cada célula teria a altura
        // do próprio texto e as divisórias ficariam desencontradas.
        final rows = [
          for (var i = 0; i < items.length; i += columns)
            items.sublist(i, (i + columns).clamp(0, items.length)),
        ];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(OrionTheme.radiusLarge),
          ),
          child: Column(
            children: [
              for (final (rowIndex, row) in rows.indexed) ...[
                if (rowIndex > 0) const Divider(height: 1),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) const VerticalDivider(width: 1),
                        Expanded(
                          child: column < row.length
                              ? _MetricCell(
                                  label: row[column].$1,
                                  value: row[column].$2,
                                  detail: row[column].$3,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _duration(int minutes) {
    if (minutes <= 0) return '0 min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '$minutes min';
    return '${hours}h ${remainder.toString().padLeft(2, '0')}';
  }

  static String _ratio(double? value) {
    if (value == null) return '—';
    return '${value.toStringAsFixed(1).replaceAll('.', ',')}×';
  }

  /// Avisa quando parte dos atendimentos resolvidos ainda não teve a
  /// indisponibilidade apurada pelo servidor. Sem isso, o número aparenta
  /// cobrir todo o histórico quando na verdade ignora os casos concluídos
  /// offline e ainda não sincronizados.
  static String _coverage(DashboardSnapshot snapshot, String fallback) {
    final pending = snapshot.casesAwaitingDowntime;
    if (pending <= 0) return fallback;
    return pending == 1
        ? '1 atendimento aguardando sincronização'
        : '$pending atendimentos aguardando sincronização';
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.orion;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: palette.textMuted, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: palette.emphasis,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          MetaText(detail, maxLines: 2),
        ],
      ),
    );
  }
}

class _CaseGroup extends StatelessWidget {
  const _CaseGroup({
    required this.title,
    required this.cases,
    required this.emptyText,
    required this.onMore,
  });

  final String title;
  final List<ServiceCase> cases;
  final String emptyText;
  final VoidCallback onMore;

  static final _date = DateFormat('dd/MM');

  @override
  Widget build(BuildContext context) {
    final palette = context.orion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            TextButton(onPressed: onMore, child: const Text('Ver todos')),
          ],
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(OrionTheme.radiusLarge),
          ),
          child: cases.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: MetaText(emptyText),
                )
              : Column(
                  children: [
                    for (final (index, item) in cases.indexed) ...[
                      if (index > 0) const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${item.caseNumber}',
                                style: TextStyle(color: palette.textMuted),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.reportedFailure,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  MetaText(
                                    '${item.equipmentLabel} · '
                                    '${_date.format(item.openedAt)}',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            StatusChip(value: item.status, compact: true),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
