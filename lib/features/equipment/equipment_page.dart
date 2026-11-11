import 'package:flutter/material.dart';

import '../../data/models/equipment.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/record_list.dart';
import '../../shared/widgets/responsive_dialog.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/archive_confirmation.dart';
import '../shell/service_log_controller.dart';
import 'equipment_form.dart';

class EquipmentPage extends StatefulWidget {
  const EquipmentPage({
    super.key,
    required this.controller,
    this.onOpenCustomers,
  });

  final ServiceLogController controller;
  final VoidCallback? onOpenCustomers;

  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}

class _EquipmentPageState extends State<EquipmentPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _newEquipment() async {
    await showResponsiveDialog<bool>(
      context: context,
      maxWidth: 760,
      child: EquipmentForm(controller: widget.controller),
    );
  }

  Future<void> _editEquipment(Equipment item) async {
    await showResponsiveDialog<bool>(
      context: context,
      maxWidth: 760,
      child: EquipmentForm(controller: widget.controller, equipment: item),
    );
  }

  Future<void> _archiveEquipment(Equipment item) async {
    final confirmado = await confirmArchive(
      context,
      tipo: 'equipamento',
      nome: item.displayName,
    );
    if (!confirmado || !mounted) return;
    final ok = await widget.controller.archiveEquipment(item.id);
    if (!mounted) return;
    if (!ok) {
      // A recusa por dependências chega aqui como mensagem do controller.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.errorMessage ?? 'Não foi possível arquivar.',
          ),
        ),
      );
    }
  }

  Future<void> _newModel() async {
    await showResponsiveDialog<String>(
      context: context,
      maxWidth: 660,
      child: EquipmentModelForm(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final all = widget.controller.equipment;
    final equipment = query.isEmpty
        ? all
        : all
              .where((item) {
                final haystack = [
                  item.manufacturer,
                  item.model,
                  item.family,
                  item.modality,
                  item.serialNumber,
                  item.customer,
                  item.site,
                ].join(' ').toLowerCase();
                return haystack.contains(query);
              })
              .toList(growable: false);
    final stopped = all.where((item) => item.status == 'stopped').length;

    return RecordList(
      onRefresh: widget.controller.load,
      header: [
        SectionHeader(
          title: 'Equipamentos',
          subtitle: all.isEmpty
              ? null
              : '${all.length} cadastrados'
                    '${stopped == 0 ? '' : ' · $stopped parado${stopped == 1 ? '' : 's'}'}',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _newModel,
                child: const Text('Fabricante / modelo'),
              ),
              if (widget.onOpenCustomers != null)
                OutlinedButton(
                  onPressed: widget.onOpenCustomers,
                  child: const Text('Clientes'),
                ),
              FilledButton.icon(
                onPressed: _newEquipment,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo equipamento'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Buscar por modelo, série, cliente ou local…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      itemCount: equipment.length,
      empty: EmptyState(
        icon: Icons.precision_manufacturing_outlined,
        title: query.isEmpty
            ? 'Nenhum equipamento cadastrado'
            : 'Nada encontrado para "$_query"',
        message: query.isEmpty
            ? 'O histórico de atendimentos fica ligado a cada equipamento.'
            : 'Tente outro termo.',
        action: query.isEmpty
            ? FilledButton(
                onPressed: _newEquipment,
                child: const Text('Cadastrar equipamento'),
              )
            : null,
      ),
      itemBuilder: (context, index) {
        final item = equipment[index];
        return _EquipmentRow(
          item: item,
          onEdit: () => _editEquipment(item),
          onArchive: () => _archiveEquipment(item),
        );
      },
    );
  }
}

class _EquipmentRow extends StatelessWidget {
  const _EquipmentRow({
    required this.item,
    required this.onEdit,
    required this.onArchive,
  });

  final Equipment item;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final versions = [
      if (item.softwareVersion?.trim().isNotEmpty == true)
        'SW ${item.softwareVersion!.trim()}',
      if (item.hardwareVersion?.trim().isNotEmpty == true)
        'HW ${item.hardwareVersion!.trim()}',
    ].join(' · ');
    final location = item.locationLabel.isEmpty
        ? 'Sem local'
        : item.locationLabel;

    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final identity = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 3),
                MetaText(
                  [
                    item.modality,
                    item.serialLabel,
                    if (versions.isNotEmpty) versions,
                  ].join(' · '),
                ),
              ],
            );
            final actions = [
              IconButton(
                tooltip: 'Editar equipamento',
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 19),
              ),
              IconButton(
                tooltip: 'Arquivar equipamento',
                onPressed: onArchive,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.inventory_2_outlined, size: 19),
              ),
            ];
            if (!wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        identity,
                        const SizedBox(height: 3),
                        MetaText(location),
                        const SizedBox(height: 6),
                        StatusChip(value: item.status, compact: true),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 5, child: identity),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: MetaText(location, maxLines: 2)),
                SizedBox(
                  width: 130,
                  child: StatusChip(value: item.status, compact: true),
                ),
                ...actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
