import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/service_case.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/responsive_dialog.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/archive_confirmation.dart';
import '../service_orders/service_order_archive.dart';
import '../service_orders/service_order_dialog.dart';
import '../shell/service_log_controller.dart';
import 'case_form.dart';

class CasesPage extends StatefulWidget {
  const CasesPage({
    super.key,
    required this.controller,
    required this.organizationName,
    required this.issuerName,
  });
  final ServiceLogController controller;

  /// Vão no cabeçalho e no rodapé da ordem de serviço.
  final String organizationName;
  final String issuerName;

  @override
  State<CasesPage> createState() => _CasesPageState();
}

class _CasesPageState extends State<CasesPage> {
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'active';
  String _activityFilter = 'all';

  /// Atendimentos que já têm OS emitida neste computador.
  Set<String> _withServiceOrder = const {};
  ServiceOrderArchive? _archive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final archive = ServiceOrderScope.maybeOf(context);
    if (archive != _archive) {
      _archive = archive;
      _loadServiceOrders();
    }
  }

  Future<void> _loadServiceOrders() async {
    final archive = _archive;
    if (archive == null) return;
    try {
      final all = await archive.loadAll();
      if (!mounted) return;
      setState(() {
        _withServiceOrder = {
          for (final entry in all.entries)
            if (entry.value.isNotEmpty) entry.key,
        };
      });
    } catch (error) {
      // A marca é um atalho visual; sem ela a lista continua usável.
      debugPrint('ORION: não foi possível ler as OS emitidas: $error');
    }
  }

  Future<void> _openServiceOrder(ServiceCase item) async {
    final issued = await showServiceOrderDialog(
      context,
      controller: widget.controller,
      item: item,
      organizationName: widget.organizationName,
      issuerName: widget.issuerName,
    );
    if (issued && mounted) await _loadServiceOrders();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _archiveCase(ServiceCase item) async {
    final confirmado = await confirmArchive(
      context,
      tipo: 'atendimento',
      nome: 'OS ${item.caseNumber} · ${item.reportedFailure}',
    );
    if (!confirmado || !mounted) return;
    final ok = await widget.controller.archiveCase(item.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.errorMessage ?? 'Não foi possível arquivar.',
          ),
        ),
      );
    }
  }

  Future<void> openForm([ServiceCase? item]) async {
    await showResponsiveDialog<bool>(
      context: context,
      maxWidth: 980,
      child: CaseForm(controller: widget.controller, initialCase: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller.cases.where((item) {
      final matchesStatus =
          _filter == 'all' ||
          (_filter == 'active' && !item.isResolved) ||
          (_filter == 'resolved' && item.isResolved);
      final matchesActivity =
          _activityFilter == 'all' || item.activityType == _activityFilter;
      final progressText = item.progressEntries
          .map((entry) => entry.description)
          .join(' ');
      final haystack = [
        item.caseNumber.toString(),
        item.activityLabel,
        item.equipmentLabel,
        item.reportedFailure,
        item.observedSymptoms,
        item.errorCode,
        item.subsystem,
        item.solutionDetails,
        progressText,
      ].whereType<String>().join(' ').toLowerCase();
      return matchesStatus &&
          matchesActivity &&
          haystack.contains(_query.toLowerCase());
    }).toList();

    return RefreshIndicator(
      onRefresh: widget.controller.load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SectionHeader(
            title: 'Atendimentos técnicos',
            subtitle:
                'Manutenções, instalações e desinstalações com diário contínuo de execução.',
            action: FilledButton.icon(
              onPressed: widget.controller.equipment.isEmpty
                  ? null
                  : () => openForm(),
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Novo atendimento'),
            ),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText:
                      'Pesquisar equipamento, atividade, falha, escopo ou andamento...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                ),
              );
              final filters = Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'active', label: Text('Ativos')),
                      ButtonSegment(
                        value: 'resolved',
                        label: Text('Concluídos'),
                      ),
                      ButtonSegment(value: 'all', label: Text('Todos')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (values) =>
                        setState(() => _filter = values.first),
                  ),
                  DropdownButton<String>(
                    value: _activityFilter,
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('Todas as atividades'),
                      ),
                      DropdownMenuItem(
                        value: ServiceActivityType.maintenance,
                        child: Text('Manutenção'),
                      ),
                      DropdownMenuItem(
                        value: ServiceActivityType.installation,
                        child: Text('Instalação'),
                      ),
                      DropdownMenuItem(
                        value: ServiceActivityType.deinstallation,
                        child: Text('Desinstalação'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _activityFilter = value);
                      }
                    },
                  ),
                ],
              );
              if (constraints.maxWidth < 1100) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [search, const SizedBox(height: 12), filters],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 14),
                  filters,
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          if (widget.controller.equipment.isEmpty)
            const EmptyState(
              icon: Icons.precision_manufacturing_outlined,
              title: 'Cadastre um equipamento primeiro',
              message:
                  'Todo atendimento precisa estar vinculado a um equipamento físico.',
            )
          else if (items.isEmpty)
            EmptyState(
              icon: Icons.assignment_outlined,
              title: 'Nenhum atendimento encontrado',
              message: _query.isEmpty
                  ? 'Use o botão acima para abrir o primeiro atendimento.'
                  : 'Revise os termos ou os filtros selecionados.',
              action: _query.isEmpty && _filter == 'active'
                  ? FilledButton.icon(
                      onPressed: () => openForm(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Abrir atendimento'),
                    )
                  : null,
            )
          else
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CaseCard(
                  item: item,
                  hasServiceOrder: _withServiceOrder.contains(item.id),
                  onTap: () => openForm(item),
                  onArchive: () => _archiveCase(item),
                  onServiceOrder: _archive == null
                      ? null
                      : () => _openServiceOrder(item),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({
    required this.item,
    required this.hasServiceOrder,
    required this.onTap,
    required this.onArchive,
    required this.onServiceOrder,
  });
  final ServiceCase item;
  final bool hasServiceOrder;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback? onServiceOrder;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM/yyyy HH:mm').format(item.openedAt);
    final latestEntries = [...item.progressEntries]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final latest = latestEntries.isEmpty ? null : latestEntries.first;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '#${item.caseNumber}',
                        style: TextStyle(
                          color: context.orion.accent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      _ActivityTag(item.activityType),
                      StatusChip(value: item.status, compact: true),
                      if (item.errorCode?.isNotEmpty == true)
                        _TechnicalTag(item.errorCode!),
                      if (item.subsystem?.isNotEmpty == true)
                        _TechnicalTag(item.subsystem!),
                      if (onServiceOrder != null)
                        IconButton(
                          tooltip: hasServiceOrder
                              ? 'Ordem de serviço (já emitida)'
                              : 'Emitir ordem de serviço',
                          onPressed: onServiceOrder,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            hasServiceOrder
                                ? Icons.picture_as_pdf_rounded
                                : Icons.picture_as_pdf_outlined,
                            size: 18,
                            color: hasServiceOrder
                                ? context.orion.accent
                                : null,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Arquivar atendimento',
                        onPressed: onArchive,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.reportedFailure,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${item.equipmentLabel} · $date',
                    style: TextStyle(color: context.orion.textMuted),
                  ),
                  if (latest != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.orion.panel,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.orion.border),
                      ),
                      child: Text(
                        'Último andamento (${DateFormat('dd/MM HH:mm').format(latest.occurredAt)}): ${latest.description}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.4),
                      ),
                    ),
                  ] else if (item.observedSymptoms?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Text(
                      item.observedSymptoms!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(height: 1.4),
                    ),
                  ],
                  if (item.isResolved &&
                      item.solutionDetails?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.orion.success.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Conclusão: ${item.solutionDetails}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.4),
                      ),
                    ),
                  ],
                ],
              );
              if (constraints.maxWidth < 700) return content;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusChip(value: item.solutionConfidence, compact: true),
                      if (item.progressEntries.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${item.progressEntries.length} registros',
                          style: TextStyle(
                            color: context.orion.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: context.orion.textMuted,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ActivityTag extends StatelessWidget {
  const _ActivityTag(this.value);
  final String value;

  @override
  Widget build(BuildContext context) {
    final icon = switch (value) {
      ServiceActivityType.installation => Icons.install_desktop_outlined,
      ServiceActivityType.deinstallation => Icons.move_down_outlined,
      _ => Icons.build_outlined,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.orion.accentSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.orion.emphasis),
          const SizedBox(width: 5),
          Text(
            ServiceActivityType.label(value),
            style: TextStyle(
              color: context.orion.emphasis,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicalTag extends StatelessWidget {
  const _TechnicalTag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.orion.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.orion.border),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
