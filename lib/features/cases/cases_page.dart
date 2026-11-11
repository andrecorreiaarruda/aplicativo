import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/service_case.dart';
import '../../shared/widgets/archive_confirmation.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/record_list.dart';
import '../../shared/widgets/responsive_dialog.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/status_chip.dart';
import '../service_orders/service_order_archive.dart';
import '../service_orders/service_order_dialog.dart';
import '../shell/service_log_controller.dart';
import 'case_form.dart';

/// Texto de busca de cada atendimento, montado uma vez por objeto.
///
/// Atendimentos são imutáveis: um atendimento editado chega como objeto
/// novo, e o texto antigo sai junto com o objeto antigo. Antes o texto era
/// remontado para todos a cada letra digitada na busca.
final _searchText = Expando<String>('textoDeBusca');

String _haystack(ServiceCase item) => _searchText[item] ??= [
  item.caseNumber.toString(),
  item.activityLabel,
  item.equipmentLabel,
  item.reportedFailure,
  item.observedSymptoms,
  item.errorCode,
  item.subsystem,
  item.solutionDetails,
  for (final entry in item.progressEntries) entry.description,
].whereType<String>().join(' ').toLowerCase();

class CasesPage extends StatefulWidget {
  const CasesPage({super.key, required this.controller});
  final ServiceLogController controller;

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

  // Resultado do último filtro, reaproveitado enquanto nada mudou. A tela
  // é reconstruída a cada aviso do controlador — inclusive os de
  // sincronização, que não mexem na lista.
  List<ServiceCase>? _sourceSeen;
  String? _filterKey;
  List<ServiceCase> _filtered = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final archive = ServiceOrderScope.maybeOf(context);
    if (archive != _archive) {
      _archive = archive;
      _loadServiceOrders();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
    );
    if (issued && mounted) await _loadServiceOrders();
  }

  Future<void> _archiveCase(ServiceCase item) async {
    final confirmado = await confirmArchive(
      context,
      tipo: 'atendimento',
      nome: 'OS ${item.caseNumber} · ${item.reportedFailure}',
    );
    if (!confirmado || !mounted) return;
    final ok = await widget.controller.archiveCase(item.id);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.controller.errorMessage ?? 'Não foi possível arquivar.',
        ),
      ),
    );
  }

  Future<void> openForm([ServiceCase? item]) async {
    await showResponsiveDialog<bool>(
      context: context,
      maxWidth: 980,
      child: CaseForm(controller: widget.controller, initialCase: item),
    );
  }

  List<ServiceCase> _visibleCases() {
    final source = widget.controller.cases;
    final key = '$_filter|$_activityFilter|${_query.toLowerCase()}';
    if (identical(source, _sourceSeen) && key == _filterKey) return _filtered;
    final query = _query.trim().toLowerCase();
    _sourceSeen = source;
    _filterKey = key;
    _filtered = source
        .where((item) {
          final matchesStatus =
              _filter == 'all' ||
              (_filter == 'active' && !item.isResolved) ||
              (_filter == 'resolved' && item.isResolved);
          if (!matchesStatus) return false;
          if (_activityFilter != 'all' &&
              item.activityType != _activityFilter) {
            return false;
          }
          return query.isEmpty || _haystack(item).contains(query);
        })
        .toList(growable: false);
    return _filtered;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final items = _visibleCases();
    final hasEquipment = controller.equipment.isNotEmpty;
    final total = controller.cases.length;
    final active = controller.cases.where((item) => !item.isResolved).length;

    return RecordList(
      onRefresh: controller.load,
      header: [
        SectionHeader(
          title: 'Atendimentos',
          subtitle: total == 0
              ? null
              : '$active em aberto · ${total - active} concluídos',
          action: FilledButton.icon(
            onPressed: hasEquipment ? () => openForm() : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Novo atendimento'),
          ),
        ),
        const SizedBox(height: 16),
        _Filters(
          search: _search,
          query: _query,
          filter: _filter,
          activity: _activityFilter,
          onQuery: (value) => setState(() => _query = value),
          onFilter: (value) => setState(() => _filter = value),
          onActivity: (value) => setState(() => _activityFilter = value),
        ),
        const SizedBox(height: 12),
      ],
      itemCount: hasEquipment ? items.length : 0,
      empty: !hasEquipment
          ? const EmptyState(
              icon: Icons.precision_manufacturing_outlined,
              title: 'Cadastre um equipamento primeiro',
              message:
                  'Todo atendimento fica ligado a um equipamento. Cadastre-o '
                  'em Equipamentos.',
            )
          : EmptyState(
              icon: Icons.assignment_outlined,
              title: _query.isEmpty
                  ? 'Nenhum atendimento aqui'
                  : 'Nada encontrado para "$_query"',
              message: _query.isEmpty
                  ? (_filter == 'active'
                        ? 'Não há atendimentos em aberto.'
                        : 'Nenhum atendimento neste filtro.')
                  : 'Tente outro termo ou mude o filtro.',
              action: _query.isEmpty && total == 0
                  ? FilledButton(
                      onPressed: () => openForm(),
                      child: const Text('Abrir atendimento'),
                    )
                  : null,
            ),
      itemBuilder: (context, index) {
        final item = items[index];
        return _CaseRow(
          item: item,
          hasServiceOrder: _withServiceOrder.contains(item.id),
          onTap: () => openForm(item),
          onArchive: () => _archiveCase(item),
          onServiceOrder: _archive == null
              ? null
              : () => _openServiceOrder(item),
        );
      },
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.search,
    required this.query,
    required this.filter,
    required this.activity,
    required this.onQuery,
    required this.onFilter,
    required this.onActivity,
  });

  final TextEditingController search;
  final String query;
  final String filter;
  final String activity;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onActivity;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: search,
      onChanged: onQuery,
      decoration: InputDecoration(
        hintText: 'Buscar por número, equipamento, falha, código…',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar busca',
                onPressed: () {
                  search.clear();
                  onQuery('');
                },
                icon: const Icon(Icons.close, size: 18),
              ),
      ),
    );
    final status = SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'active', label: Text('Em aberto')),
        ButtonSegment(value: 'resolved', label: Text('Concluídos')),
        ButtonSegment(value: 'all', label: Text('Todos')),
      ],
      selected: {filter},
      onSelectionChanged: (values) => onFilter(values.first),
    );
    final activityMenu = DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: activity,
        borderRadius: BorderRadius.circular(OrionTheme.radius),
        items: const [
          DropdownMenuItem(value: 'all', child: Text('Todas as atividades')),
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
          if (value != null) onActivity(value);
        },
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [status, activityMenu],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 12),
            status,
            const SizedBox(width: 12),
            activityMenu,
          ],
        );
      },
    );
  }
}

class _CaseRow extends StatelessWidget {
  const _CaseRow({
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

  static final _date = DateFormat('dd/MM/yy');

  @override
  Widget build(BuildContext context) {
    final palette = context.orion;
    final meta = [
      item.equipmentLabel,
      if (item.activityType != ServiceActivityType.maintenance)
        item.activityLabel,
      if (item.errorCode?.isNotEmpty == true) item.errorCode!,
    ].join(' · ');

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onServiceOrder != null)
          IconButton(
            tooltip: hasServiceOrder
                ? 'Ordem de serviço (já emitida)'
                : 'Emitir ordem de serviço',
            onPressed: onServiceOrder,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              hasServiceOrder
                  ? Icons.picture_as_pdf
                  : Icons.picture_as_pdf_outlined,
              size: 19,
              color: hasServiceOrder ? palette.accent : null,
            ),
          ),
        IconButton(
          tooltip: 'Arquivar atendimento',
          onPressed: onArchive,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.inventory_2_outlined, size: 19),
        ),
      ],
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.reportedFailure,
                  maxLines: wide ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 3),
                MetaText(meta),
              ],
            );
            final number = SizedBox(
              width: 52,
              child: Text(
                '${item.caseNumber}',
                style: TextStyle(
                  color: palette.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
            if (!wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  number,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            StatusChip(value: item.status, compact: true),
                            const SizedBox(width: 12),
                            MetaText(_date.format(item.openedAt)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions,
                ],
              );
            }
            return Row(
              children: [
                number,
                Expanded(child: title),
                const SizedBox(width: 16),
                SizedBox(
                  width: 150,
                  child: StatusChip(value: item.status, compact: true),
                ),
                SizedBox(
                  width: 72,
                  child: MetaText(_date.format(item.openedAt)),
                ),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
