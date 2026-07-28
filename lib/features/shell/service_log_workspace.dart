import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/repositories/service_log_repository.dart';
import '../../shared/widgets/orion_brand.dart';
import '../assistant/assistant_page.dart';
import '../cases/cases_page.dart';
import '../customers/customers_page.dart';
import '../dashboard/dashboard_page.dart';
import '../equipment/equipment_page.dart';
import 'service_log_controller.dart';

class WorkspaceProfile {
  const WorkspaceProfile({
    required this.fullName,
    required this.role,
    required this.organizationName,
  });

  final String fullName;
  final String role;
  final String organizationName;
}

class ServiceLogWorkspace extends StatefulWidget {
  const ServiceLogWorkspace({
    super.key,
    required this.repository,
    required this.profile,
    this.demoMode = false,
  });

  final ServiceLogRepository repository;
  final WorkspaceProfile profile;
  final bool demoMode;

  @override
  State<ServiceLogWorkspace> createState() => _ServiceLogWorkspaceState();
}

class _ServiceLogWorkspaceState extends State<ServiceLogWorkspace> {
  late final ServiceLogController _controller;
  late final Future<void> _initialLoad;
  int _selectedIndex = 0;

  static const _destinations = [
    _Destination(
      label: 'Dashboard',
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
    ),
    _Destination(
      label: 'Clientes',
      icon: Icons.apartment_outlined,
      selectedIcon: Icons.apartment_rounded,
    ),
    _Destination(
      label: 'Equipamentos',
      icon: Icons.precision_manufacturing_outlined,
      selectedIcon: Icons.precision_manufacturing_rounded,
    ),
    _Destination(
      label: 'Atendimentos',
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment_rounded,
    ),
    _Destination(
      label: 'Assistente',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = ServiceLogController(widget.repository);

    // A carga começa no initState, antes de o AnimatedBuilder registrar seu
    // listener. Assim evitamos setState manual durante callbacks de frame e
    // deixamos o ChangeNotifier conduzir as reconstruções subsequentes.
    _initialLoad = _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _selectedPage() {
    switch (_selectedIndex) {
      case 0:
        return DashboardPage(
          key: const PageStorageKey('dashboard'),
          controller: _controller,
          onOpenCases: () => setState(() => _selectedIndex = 3),
          onOpenAssistant: () => setState(() => _selectedIndex = 4),
        );
      case 1:
        return CustomersPage(
          key: const PageStorageKey('customers'),
          controller: _controller,
        );
      case 2:
        return EquipmentPage(
          key: const PageStorageKey('equipment'),
          controller: _controller,
          onOpenCustomers: () => setState(() => _selectedIndex = 1),
        );
      case 3:
        return CasesPage(
          key: const PageStorageKey('cases'),
          controller: _controller,
        );
      case 4:
        return AssistantPage(
          key: const PageStorageKey('assistant'),
          controller: _controller,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final rail = constraints.maxWidth >= 860;
            final extended = constraints.maxWidth >= 1220;
            final narrowPhone = constraints.maxWidth < 470;

            return Scaffold(
              appBar: AppBar(
                toolbarHeight: 68,
                leadingWidth: rail
                    ? (extended ? 246 : 86)
                    : narrowPhone
                        ? 66
                        : 190,
                leading: Padding(
                  padding: EdgeInsets.only(left: rail ? 18 : 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OrionBrand(
                      compact: (rail && !extended) || narrowPhone,
                      showProductDetails: rail && extended,
                      height: 36,
                    ),
                  ),
                ),
                title: rail
                    ? Text(
                        _destinations[_selectedIndex].label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      )
                    : null,
                actions: [
                  if (widget.demoMode && !narrowPhone)
                    Container(
                      margin: const EdgeInsets.symmetric(
                        vertical: 17,
                        horizontal: 8,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: OrionColors.paleCyan,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'DEMO LOCAL',
                        style: TextStyle(
                          color: OrionColors.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Atualizar dados',
                    onPressed: _controller.loading ? null : _controller.load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Conta',
                    onSelected: (value) {
                      if (value == 'logout') _controller.signOut();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        enabled: false,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 210),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.profile.fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${widget.profile.role} · '
                                '${widget.profile.organizationName}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!widget.demoMode)
                        const PopupMenuItem(
                          value: 'logout',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.logout_rounded),
                            title: Text('Sair'),
                          ),
                        ),
                    ],
                    icon: CircleAvatar(
                      radius: 17,
                      backgroundColor: OrionColors.navy,
                      foregroundColor: Colors.white,
                      child: Text(_initials(widget.profile.fullName)),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                bottom: _controller.loading
                    ? const PreferredSize(
                        preferredSize: Size.fromHeight(3),
                        child: LinearProgressIndicator(minHeight: 3),
                      )
                    : null,
              ),
              body: Row(
                children: [
                  if (rail)
                    NavigationRail(
                      extended: extended,
                      selectedIndex: _selectedIndex,
                      minWidth: 76,
                      minExtendedWidth: 232,
                      groupAlignment: -0.72,
                      onDestinationSelected: (value) =>
                          setState(() => _selectedIndex = value),
                      destinations: [
                        for (final destination in _destinations)
                          NavigationRailDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: Icon(destination.selectedIcon),
                            label: Text(destination.label),
                          ),
                      ],
                    ),
                  Expanded(
                    child: _WorkspaceContent(
                      controller: _controller,
                      initialLoad: _initialLoad,
                      selectedPage: _selectedPage(),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: rail
                  ? null
                  : NavigationBar(
                      labelBehavior:
                          NavigationDestinationLabelBehavior.onlyShowSelected,
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: (value) =>
                          setState(() => _selectedIndex = value),
                      destinations: [
                        for (final destination in _destinations)
                          NavigationDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: Icon(destination.selectedIcon),
                            label: destination.label,
                          ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'O';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _WorkspaceContent extends StatelessWidget {
  const _WorkspaceContent({
    required this.controller,
    required this.initialLoad,
    required this.selectedPage,
  });

  final ServiceLogController controller;
  final Future<void> initialLoad;
  final Widget selectedPage;

  @override
  Widget build(BuildContext context) {
    final firstLoad = controller.loading &&
        controller.equipment.isEmpty &&
        controller.cases.isEmpty;

    if (firstLoad) {
      return FutureBuilder<void>(
        future: initialLoad,
        builder: (context, snapshot) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Carregando dados demonstrativos…'),
              ],
            ),
          );
        },
      );
    }

    return Column(
      children: [
        if (controller.errorMessage != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDEA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OrionColors.danger),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: OrionColors.danger,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(controller.errorMessage!)),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: controller.clearError,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey<Type>(selectedPage.runtimeType),
            child: selectedPage,
          ),
        ),
      ],
    );
  }
}

class _Destination {
  const _Destination(
      {required this.label, required this.icon, required this.selectedIcon});
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
