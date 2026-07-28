import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/equipment.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/responsive_dialog.dart';
import '../../shared/widgets/section_header.dart';
import '../equipment/equipment_form.dart';
import '../shell/service_log_controller.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, required this.controller});

  final ServiceLogController controller;

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<String?> _newCustomer() {
    return showResponsiveDialog<String>(
      context: context,
      maxWidth: 720,
      child: CustomerForm(controller: widget.controller),
    );
  }

  Future<void> _editCustomer(CustomerOption customer) async {
    await showResponsiveDialog<String>(
      context: context,
      maxWidth: 720,
      child: CustomerForm(
        controller: widget.controller,
        customer: customer,
      ),
    );
  }

  Future<void> _newSite([String? customerId]) async {
    var selectedCustomerId = customerId;
    if (widget.controller.catalog.customers.isEmpty) {
      selectedCustomerId = await _newCustomer();
      if (selectedCustomerId == null || !mounted) return;
    }

    await showResponsiveDialog<String>(
      context: context,
      maxWidth: 660,
      child: SiteForm(
        controller: widget.controller,
        initialCustomerId: selectedCustomerId,
      ),
    );
  }

  Future<void> _editSite(SiteOption site) async {
    await showResponsiveDialog<String>(
      context: context,
      maxWidth: 660,
      child: SiteForm(
        controller: widget.controller,
        site: site,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final customers = widget.controller.catalog.customers.where((customer) {
      if (normalizedQuery.isEmpty) return true;
      final sites = widget.controller.catalog.sites
          .where((site) => site.customerId == customer.id)
          .map((site) => '${site.site} ${site.city ?? ''} ${site.state ?? ''}')
          .join(' ');
      final haystack = [
        customer.name,
        customer.taxId,
        customer.contactName,
        customer.email,
        customer.phone,
        customer.addressLine,
        customer.city,
        customer.state,
        customer.notes,
        sites,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(normalizedQuery);
    }).toList();

    return RefreshIndicator(
      onRefresh: widget.controller.load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SectionHeader(
            title: 'Clientes',
            subtitle:
                'Cadastro rápido de hospitais, clínicas, contatos e locais de instalação.',
            action: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _newSite(),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Novo local'),
                ),
                FilledButton.icon(
                  onPressed: _newCustomer,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Novo cliente'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _ServiceOrderFoundationCard(
            customerCount: widget.controller.catalog.customers.length,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Pesquisar por cliente, contato, cidade ou local...',
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
          if (customers.isEmpty)
            EmptyState(
              icon: Icons.apartment_rounded,
              title: normalizedQuery.isEmpty
                  ? 'Nenhum cliente cadastrado'
                  : 'Nenhum cliente encontrado',
              message: normalizedQuery.isEmpty
                  ? 'Cadastre apenas o nome agora. Os demais dados podem ser preenchidos quando estiverem disponíveis.'
                  : 'Revise os termos da pesquisa.',
              action: normalizedQuery.isEmpty
                  ? FilledButton.icon(
                      onPressed: _newCustomer,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Cadastrar cliente'),
                    )
                  : null,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1160
                    ? 3
                    : constraints.maxWidth >= 720
                        ? 2
                        : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 14) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final customer in customers)
                      SizedBox(
                        width: width,
                        child: _CustomerCard(
                          customer: customer,
                          sites: widget.controller.catalog.sites
                              .where((site) => site.customerId == customer.id)
                              .toList(),
                          equipmentCount: widget.controller.equipment
                              .where((item) => item.customer == customer.name)
                              .length,
                          onAddSite: () => _newSite(customer.id),
                          onEditCustomer: () => _editCustomer(customer),
                          onEditSite: _editSite,
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

class _ServiceOrderFoundationCard extends StatelessWidget {
  const _ServiceOrderFoundationCard({required this.customerCount});

  final int customerCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: OrionColors.paleCyan,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OrionColors.cyan.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: OrionColors.blue,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Base para preenchimento automático da OS',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: OrionColors.navy,
                          ),
                    ),
                    const Chip(label: Text('Próxima etapa')),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Os dados opcionais de contato e endereço já ficam organizados por cliente. '
                  'Na etapa de ordens de serviço, cada cliente poderá ter um modelo salvo e o atendimento concluído fornecerá falha, diagnóstico, solução, tempos e validação para preenchimento automático.',
                  style: const TextStyle(
                    color: OrionColors.muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  customerCount == 1
                      ? '1 cliente disponível para essa futura integração.'
                      : '$customerCount clientes disponíveis para essa futura integração.',
                  style: const TextStyle(
                    color: OrionColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.sites,
    required this.equipmentCount,
    required this.onAddSite,
    required this.onEditCustomer,
    required this.onEditSite,
  });

  final CustomerOption customer;
  final List<SiteOption> sites;
  final int equipmentCount;
  final VoidCallback onAddSite;
  final VoidCallback onEditCustomer;
  final ValueChanged<SiteOption> onEditSite;

  @override
  Widget build(BuildContext context) {
    final contactLines = <Widget>[
      if (customer.taxId?.isNotEmpty == true)
        _InfoLine(
          icon: Icons.badge_outlined,
          text: 'CNPJ / ID: ${customer.taxId}',
        ),
      if (customer.contactName?.isNotEmpty == true)
        _InfoLine(
          icon: Icons.person_outline_rounded,
          text: customer.contactName!,
        ),
      if (customer.phone?.isNotEmpty == true)
        _InfoLine(icon: Icons.phone_outlined, text: customer.phone!),
      if (customer.email?.isNotEmpty == true)
        _InfoLine(icon: Icons.email_outlined, text: customer.email!),
      if (customer.addressLine?.isNotEmpty == true)
        _InfoLine(
          icon: Icons.home_work_outlined,
          text: customer.addressLine!,
        ),
      if (customer.locationLabel.isNotEmpty)
        _InfoLine(
          icon: Icons.location_city_outlined,
          text: customer.locationLabel,
        ),
    ];

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
                    Icons.apartment_rounded,
                    color: OrionColors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        sites.length == 1
                            ? '$equipmentCount equipamento${equipmentCount == 1 ? '' : 's'} · 1 local'
                            : '$equipmentCount equipamento${equipmentCount == 1 ? '' : 's'} · ${sites.length} locais',
                        style: const TextStyle(color: OrionColors.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Editar cliente',
                  onPressed: onEditCustomer,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            if (contactLines.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...contactLines,
            ],
            const SizedBox(height: 14),
            Text(
              'Locais de instalação',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: OrionColors.navy,
                  ),
            ),
            const SizedBox(height: 8),
            if (sites.isEmpty)
              const Text(
                'Nenhum local cadastrado.',
                style: TextStyle(color: OrionColors.muted),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final site in sites)
                    Tooltip(
                      message: site.locationLabel.isEmpty
                          ? 'Editar ${site.site}'
                          : 'Editar ${site.site} · ${site.locationLabel}',
                      child: ActionChip(
                        avatar: const Icon(
                          Icons.location_on_outlined,
                          size: 17,
                        ),
                        label: Text(site.site),
                        onPressed: () => onEditSite(site),
                      ),
                    ),
                ],
              ),
            if (customer.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(
                customer.notes!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: OrionColors.muted, height: 1.4),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddSite,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Adicionar local'),
              ),
            ),
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
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: OrionColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
