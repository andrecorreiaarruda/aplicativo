import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/equipment.dart';
import '../../shared/widgets/archive_confirmation.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/record_list.dart';
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

  Future<void> _archiveCustomer(CustomerOption customer) async {
    final confirmado = await confirmArchive(
      context,
      tipo: 'cliente',
      nome: customer.name,
    );
    if (!confirmado || !mounted) return;
    final ok = await widget.controller.archiveCustomer(customer.id);
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
      child: CustomerForm(controller: widget.controller, customer: customer),
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
      child: SiteForm(controller: widget.controller, site: site),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.controller.catalog;
    final sitesByCustomer = <String, List<SiteOption>>{};
    for (final site in catalog.sites) {
      (sitesByCustomer[site.customerId] ??= []).add(site);
    }
    // Pelo local, e não pelo nome do cliente: dois clientes com o mesmo
    // nome, ou um renomeado ainda não sincronizado, somavam errado.
    final customerOfSite = {
      for (final site in catalog.sites) site.id: site.customerId,
    };
    final equipmentByCustomer = <String, int>{};
    for (final item in widget.controller.equipment) {
      final customerId = customerOfSite[item.siteId];
      if (customerId == null) continue;
      equipmentByCustomer[customerId] =
          (equipmentByCustomer[customerId] ?? 0) + 1;
    }

    final query = _query.trim().toLowerCase();
    final customers = catalog.customers
        .where((customer) {
          if (query.isEmpty) return true;
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
            for (final site in sitesByCustomer[customer.id] ?? const [])
              '${site.site} ${site.city ?? ''} ${site.state ?? ''}',
          ].whereType<String>().join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);

    return RecordList(
      onRefresh: widget.controller.load,
      header: [
        SectionHeader(
          title: 'Clientes',
          subtitle: catalog.customers.isEmpty
              ? null
              : '${catalog.customers.length} clientes · '
                    '${catalog.sites.length} locais',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _newSite(),
                child: const Text('Novo local'),
              ),
              FilledButton.icon(
                onPressed: _newCustomer,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo cliente'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Buscar por cliente, contato, cidade ou local…',
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
      itemCount: customers.length,
      empty: EmptyState(
        icon: Icons.apartment_outlined,
        title: query.isEmpty
            ? 'Nenhum cliente cadastrado'
            : 'Nada encontrado para "$_query"',
        message: query.isEmpty
            ? 'Basta o nome para começar. Contato, CNPJ e endereço saem no '
                  'cabeçalho da OS e podem ser preenchidos depois.'
            : 'Tente outro termo.',
        action: query.isEmpty
            ? FilledButton(
                onPressed: _newCustomer,
                child: const Text('Cadastrar cliente'),
              )
            : null,
      ),
      itemBuilder: (context, index) {
        final customer = customers[index];
        return _CustomerRow(
          customer: customer,
          sites: sitesByCustomer[customer.id] ?? const [],
          equipmentCount: equipmentByCustomer[customer.id] ?? 0,
          onAddSite: () => _newSite(customer.id),
          onEditCustomer: () => _editCustomer(customer),
          onArchiveCustomer: () => _archiveCustomer(customer),
          onEditSite: _editSite,
        );
      },
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.sites,
    required this.equipmentCount,
    required this.onAddSite,
    required this.onEditCustomer,
    required this.onArchiveCustomer,
    required this.onEditSite,
  });

  final CustomerOption customer;
  final List<SiteOption> sites;
  final int equipmentCount;
  final VoidCallback onAddSite;
  final VoidCallback onEditCustomer;
  final VoidCallback onArchiveCustomer;
  final ValueChanged<SiteOption> onEditSite;

  @override
  Widget build(BuildContext context) {
    final palette = context.orion;
    final details = [
      if (customer.locationLabel.isNotEmpty) customer.locationLabel,
      if (customer.contactName?.trim().isNotEmpty == true)
        customer.contactName!.trim(),
      if (customer.phone?.trim().isNotEmpty == true) customer.phone!.trim(),
      equipmentCount == 1 ? '1 equipamento' : '$equipmentCount equipamentos',
    ].join(' · ');

    return InkWell(
      onTap: onEditCustomer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  MetaText(details, maxLines: 2),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        sites.isEmpty ? 'Sem locais' : 'Locais:',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      for (final site in sites)
                        TextButton(
                          onPressed: () => onEditSite(site),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 28),
                            textStyle: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                          ),
                          child: Text(site.site),
                        ),
                      TextButton.icon(
                        onPressed: onAddSite,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 28),
                          foregroundColor: palette.textMuted,
                          textStyle: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Adicionar local'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Editar cliente',
              onPressed: onEditCustomer,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 19),
            ),
            IconButton(
              tooltip: 'Arquivar cliente',
              onPressed: onArchiveCustomer,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.inventory_2_outlined, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}
