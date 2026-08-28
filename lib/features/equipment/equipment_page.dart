import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/equipment.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/responsive_dialog.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/status_chip.dart';
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

  Future<void> _newModel() async {
    await showResponsiveDialog<String>(
      context: context,
      maxWidth: 660,
      child: EquipmentModelForm(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final equipment = widget.controller.equipment.where((item) {
      final haystack = [
        item.manufacturer,
        item.model,
        item.family,
        item.modality,
        item.serialNumber,
        item.customer,
        item.site,
      ].join(' ').toLowerCase();
      return haystack.contains(_query.toLowerCase());
    }).toList();

    return RefreshIndicator(
      onRefresh: widget.controller.load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SectionHeader(
            title: 'Equipamentos',
            subtitle:
                'Inventário técnico com configuração, localização e condição operacional.',
            action: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _newModel,
                  icon: const Icon(Icons.category_outlined),
                  label: const Text('Fabricante / modelo'),
                ),
                if (widget.onOpenCustomers != null)
                  OutlinedButton.icon(
                    onPressed: widget.onOpenCustomers,
                    icon: const Icon(Icons.apartment_outlined),
                    label: const Text('Clientes'),
                  ),
                FilledButton.icon(
                  onPressed: _newEquipment,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Novo equipamento'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Pesquisar por modelo, série, cliente ou local...',
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
          ),
          const SizedBox(height: 18),
          if (equipment.isEmpty)
            EmptyState(
              icon: Icons.precision_manufacturing_outlined,
              title: _query.isEmpty
                  ? 'Nenhum equipamento cadastrado'
                  : 'Nenhum resultado',
              message: _query.isEmpty
                  ? 'Cadastre o primeiro equipamento para iniciar o histórico técnico.'
                  : 'Revise os termos da pesquisa.',
              action: _query.isEmpty
                  ? FilledButton.icon(
                      onPressed: _newEquipment,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Cadastrar equipamento'),
                    )
                  : null,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1160
                    ? 3
                    : constraints.maxWidth >= 700
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 14) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final item in equipment)
                      SizedBox(
                        width: width,
                        child: _EquipmentCard(
                          item: item,
                          onEdit: () => _editEquipment(item),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.item, required this.onEdit});
  final Equipment item;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: OrionColors.paleCyan,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.precision_manufacturing_rounded,
                    color: OrionColors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        item.modality,
                        style: const TextStyle(color: OrionColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(value: item.status, compact: true),
                IconButton(
                  tooltip: 'Editar equipamento',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _InfoLine(icon: Icons.qr_code_2_rounded, text: item.serialNumber),
            if (item.locationLabel.isNotEmpty)
              _InfoLine(
                icon: Icons.location_on_outlined,
                text: item.locationLabel,
              ),
            if (item.softwareVersion?.isNotEmpty == true)
              _InfoLine(
                icon: Icons.memory_rounded,
                text: 'Software ${item.softwareVersion}',
              ),
            if (item.hardwareVersion?.isNotEmpty == true)
              _InfoLine(
                icon: Icons.developer_board_outlined,
                text: 'Hardware ${item.hardwareVersion}',
              ),
            if (item.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                item.notes!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: OrionColors.muted, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: OrionColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
