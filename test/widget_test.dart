import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/theme/orion_theme.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/features/shell/service_log_workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    required Size surfaceSize,
  }) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: OrionTheme.light(),
        home: ServiceLogWorkspace(
          repository: DemoServiceLogRepository.seeded(),
          profile: const WorkspaceProfile(
            fullName: 'Técnico ORION',
            role: 'Engenheiro',
            organizationName: 'ORION',
          ),
          demoMode: true,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('workspace ORION apresenta o dashboard em largura média',
      (tester) async {
    await pumpWorkspace(
      tester,
      surfaceSize: const Size(800, 600),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Visão operacional'), findsOneWidget);
    expect(find.text('Equipamentos'), findsWidgets);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsWidgets);
  });

  testWidgets('workspace ORION não apresenta overflow em desktop',
      (tester) async {
    await pumpWorkspace(
      tester,
      surfaceSize: const Size(1280, 800),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Visão operacional'), findsOneWidget);
    expect(find.text('ServiceLog AI'), findsOneWidget);
  });

  testWidgets('navegação abre a área dedicada de clientes', (tester) async {
    await pumpWorkspace(
      tester,
      surfaceSize: const Size(1280, 800),
    );

    await tester.tap(find.text('Clientes').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
        find.text('Base para preenchimento automático da OS'), findsOneWidget);
    expect(find.text('Novo cliente'), findsOneWidget);
  });
}
