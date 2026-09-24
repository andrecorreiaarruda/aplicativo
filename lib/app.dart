import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/runtime/app_runtime.dart';
import 'core/theme/appearance_controller.dart';
import 'core/theme/orion_theme.dart';
import 'data/repositories/demo_service_log_repository.dart';
import 'features/auth/auth_gate.dart';
import 'features/shell/service_log_workspace.dart';

class ServiceLogApp extends StatelessWidget {
  const ServiceLogApp({super.key, required this.runtime});

  final AppRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final appearance = runtime.appearance;
    return AppearanceScope(
      controller: appearance,
      child: ListenableBuilder(
        listenable: appearance,
        builder: (context, _) => _app(appearance.mode),
      ),
    );
  }

  Widget _app(ThemeMode mode) {
    return MaterialApp(
      title: 'ORION ServiceLog AI',
      debugShowCheckedModeBanner: false,
      theme: OrionTheme.light(),
      darkTheme: OrionTheme.dark(),
      themeMode: mode,
      home: AppConfig.isSupabaseConfigured
          ? AuthGate(runtime: runtime)
          : ServiceLogWorkspace(
              repository: DemoServiceLogRepository.seeded(
                storage: runtime.localStore,
                namespace: 'demo-local-v4',
                journalChanges: true,
              ),
              profile: const WorkspaceProfile(
                fullName: 'André Leite',
                role: 'Engenheiro responsável',
                organizationName: 'ORION',
              ),
              demoMode: true,
              storageLabel: runtime.localStore.storageLabel,
              startupWarning: runtime.storageWarning,
            ),
    );
  }
}
