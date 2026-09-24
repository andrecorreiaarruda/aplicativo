import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/repositories/service_log_repository.dart';
import '../../shared/widgets/orion_brand.dart';
import '../archive/archived_page.dart';
import '../assistant/assistant_page.dart';
import '../cases/cases_page.dart';
import '../customers/customers_page.dart';
import '../dashboard/dashboard_page.dart';
import '../equipment/equipment_page.dart';
import '../sync/conflicts_page.dart';
import '../../core/theme/appearance_controller.dart';
import 'appearance_dialog.dart';
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
    required this.storageLabel,
    this.demoMode = false,
    this.startupWarning,
  });

  final ServiceLogRepository repository;
  final WorkspaceProfile profile;
  final String storageLabel;
  final bool demoMode;
  final String? startupWarning;

  @override
  State<ServiceLogWorkspace> createState() => _ServiceLogWorkspaceState();
}

class _ServiceLogWorkspaceState extends State<ServiceLogWorkspace>
    with WidgetsBindingObserver {
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
    _Destination(
      label: 'Arquivados',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ServiceLogController(widget.repository);

    // A carga começa no initState, antes de o AnimatedBuilder registrar seu
    // listener. Assim evitamos setState manual durante callbacks de frame e
    // deixamos o ChangeNotifier conduzir as reconstruções subsequentes.
    _initialLoad = _controller.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.demoMode) {
      unawaited(_controller.syncNow(silent: true));
    }
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
      case 5:
        return ArchivedPage(
          key: const PageStorageKey('archived'),
          controller: _controller,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  String _storageStatusLabel() {
    if (_controller.syncing) return 'Sincronizando…';
    final status = _controller.syncStatus;
    final conflicts = status?.conflictCount ?? 0;
    if (conflicts > 0) {
      return '$conflicts conflito${conflicts == 1 ? '' : 's'}';
    }
    final pending = status?.pendingCount ?? 0;
    if (pending > 0) return '$pending pendente${pending == 1 ? '' : 's'}';
    return widget.demoMode ? widget.storageLabel : 'Sincronizado';
  }

  bool get _hasConflicts => (_controller.syncStatus?.conflictCount ?? 0) > 0;

  Future<void> _openConflicts() async {
    await showConflictsPage(context, _controller);
    if (mounted) await _controller.refreshSyncStatus();
  }

  Future<void> _showStorageDetails() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storage_rounded),
            SizedBox(width: 10),
            Text('Armazenamento e sincronização'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.storageLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _controller.syncStatus?.pendingCount == null
                    ? 'Fila local ainda não inicializada.'
                    : '${_controller.syncStatus!.pendingCount} alteração(ões) '
                          'aguardando sincronização.',
              ),
              const SizedBox(height: 10),
              Text(
                widget.demoMode
                    ? 'Os cadastros desta versão são gravados no SQLite local. '
                          'O modo demonstração não envia dados a um servidor.'
                    : 'O aplicativo grava primeiro no SQLite e sincroniza com '
                          'o Supabase quando existe conexão. Você pode continuar '
                          'trabalhando offline; alterações pendentes permanecem '
                          'na fila até o próximo envio bem-sucedido.',
              ),
              if (_controller.syncStatus?.lastSuccessfulSync != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Última sincronização: '
                  '${_controller.syncStatus!.lastSuccessfulSync!.toLocal()}',
                ),
              ],
              if (_controller.syncStatus?.lastError != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Último erro: ${_controller.syncStatus!.lastError}',
                  style: TextStyle(color: context.orion.danger),
                ),
              ],
              if (widget.startupWarning != null) ...[
                const SizedBox(height: 14),
                Text(
                  widget.startupWarning!,
                  style: TextStyle(color: context.orion.danger),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (_hasConflicts)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _openConflicts();
              },
              icon: const Icon(Icons.sync_problem_rounded),
              label: const Text('Resolver conflitos'),
            ),
          if (!widget.demoMode)
            FilledButton.icon(
              onPressed: _controller.syncing
                  ? null
                  : () async {
                      await _controller.syncNow();
                      if (context.mounted) Navigator.of(context).pop();
                    },
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sincronizar agora'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
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
            final showDemoChip = constraints.maxWidth >= 680;
            final showStorageChip = constraints.maxWidth >= 760;

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
                  if (widget.demoMode && showDemoChip)
                    Container(
                      margin: const EdgeInsets.symmetric(
                        vertical: 17,
                        horizontal: 8,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.orion.accentSoft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'DEMO LOCAL',
                        style: TextStyle(
                          color: context.orion.emphasis,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (showStorageChip)
                    ActionChip(
                      avatar: Icon(
                        _hasConflicts
                            ? Icons.sync_problem_rounded
                            : Icons.storage_rounded,
                        size: 18,
                        color: _hasConflicts ? context.orion.warning : null,
                      ),
                      label: Text(_storageStatusLabel()),
                      // Com conflito, o atalho leva direto a onde se
                      // resolve: o diálogo de armazenamento não tem o que
                      // oferecer enquanto a fila está travada.
                      onPressed: _hasConflicts
                          ? _openConflicts
                          : _showStorageDetails,
                    )
                  else
                    IconButton(
                      tooltip: _hasConflicts
                          ? 'Conflitos de sincronização'
                          : 'Armazenamento e sincronização',
                      onPressed: _hasConflicts
                          ? _openConflicts
                          : _showStorageDetails,
                      icon: Icon(
                        _hasConflicts
                            ? Icons.sync_problem_rounded
                            : Icons.storage_rounded,
                        color: _hasConflicts ? context.orion.warning : null,
                      ),
                    ),
                  IconButton(
                    tooltip: widget.demoMode
                        ? 'Atualizar dados locais'
                        : 'Sincronizar dados',
                    onPressed: _controller.loading || _controller.syncing
                        ? null
                        : widget.demoMode
                        ? _controller.load
                        : () => _controller.syncNow(),
                    icon: Icon(
                      widget.demoMode
                          ? Icons.refresh_rounded
                          : Icons.sync_rounded,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Conta',
                    onSelected: (value) {
                      if (value == 'appearance') showAppearanceDialog(context);
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
                      PopupMenuItem(
                        value: 'appearance',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.contrast_rounded),
                          title: const Text('Aparência'),
                          subtitle: Text(
                            appearanceLabel(
                              AppearanceScope.maybeOf(context)?.mode ??
                                  ThemeMode.system,
                            ),
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
                      backgroundColor: context.orion.emphasis,
                      foregroundColor: context.orion.onEmphasis,
                      child: Text(_initials(widget.profile.fullName)),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                bottom: _controller.loading || _controller.syncing
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
                      startupWarning: widget.startupWarning,
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
    this.startupWarning,
  });

  final ServiceLogController controller;
  final Future<void> initialLoad;
  final Widget selectedPage;
  final String? startupWarning;

  @override
  Widget build(BuildContext context) {
    final firstLoad =
        controller.loading &&
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
                Text('Carregando dados…'),
              ],
            ),
          );
        },
      );
    }

    return Column(
      children: [
        if (startupWarning != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.orion.warning.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.orion.warning.withValues(alpha: .55),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: context.orion.warning),
                const SizedBox(width: 10),
                Expanded(child: Text(startupWarning!)),
              ],
            ),
          ),
        if (controller.errorMessage != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.orion.danger.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.orion.danger),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: context.orion.danger),
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
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
