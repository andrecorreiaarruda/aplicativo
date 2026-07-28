import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/theme/orion_theme.dart';
import 'data/repositories/demo_service_log_repository.dart';
import 'features/auth/auth_gate.dart';
import 'features/shell/service_log_workspace.dart';

class ServiceLogApp extends StatelessWidget {
  const ServiceLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ORION ServiceLog AI',
      debugShowCheckedModeBanner: false,
      theme: OrionTheme.light(),
      darkTheme: OrionTheme.dark(),
      themeMode: ThemeMode.light,
      home: AppConfig.isSupabaseConfigured
          ? const AuthGate()
          : ServiceLogWorkspace(
              repository: DemoServiceLogRepository.seeded(),
              profile: const WorkspaceProfile(
                fullName: 'André Leite',
                role: 'Engenheiro responsável',
                organizationName: 'ORION',
              ),
              demoMode: true,
            ),
    );
  }
}
