import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/core/theme/appearance_controller.dart';
import 'package:servicelog_ai/core/theme/orion_theme.dart';

void main() {
  test('sem escolha salva, segue o sistema', () async {
    final controller = await AppearanceController.load(MemorySnapshotStore());
    expect(controller.mode, ThemeMode.system);
  });

  test('a escolha sobrevive a uma nova abertura', () async {
    final store = MemorySnapshotStore();
    final primeira = await AppearanceController.load(store);
    await primeira.setMode(ThemeMode.dark);

    final segunda = await AppearanceController.load(store);
    expect(segunda.mode, ThemeMode.dark);
  });

  test('valor desconhecido no banco cai em Sistema', () {
    expect(AppearanceController.parse('roxo'), ThemeMode.system);
    expect(AppearanceController.parse(null), ThemeMode.system);
    expect(AppearanceController.parse('light'), ThemeMode.light);
  });

  test('avisa a interface só quando a escolha muda', () async {
    final controller = AppearanceController(store: MemorySnapshotStore());
    var avisos = 0;
    controller.addListener(() => avisos++);
    await controller.setMode(ThemeMode.light);
    await controller.setMode(ThemeMode.light);
    expect(avisos, 1);
  });

  test('os dois temas registram a paleta ORION', () {
    expect(OrionTheme.light().extension<OrionPalette>(), OrionPalette.light);
    expect(OrionTheme.dark().extension<OrionPalette>(), OrionPalette.dark);
    expect(OrionTheme.dark().brightness, Brightness.dark);
  });

  testWidgets('o seletor troca o tema do aplicativo na hora', (tester) async {
    final aparencia = AppearanceController(store: MemorySnapshotStore());
    await tester.pumpWidget(
      AppearanceScope(
        controller: aparencia,
        child: ListenableBuilder(
          listenable: aparencia,
          builder: (context, _) => MaterialApp(
            theme: OrionTheme.light(),
            darkTheme: OrionTheme.dark(),
            themeMode: aparencia.mode,
            home: Builder(
              builder: (context) => Text(
                Theme.of(context).brightness.name,
                textDirection: TextDirection.ltr,
              ),
            ),
          ),
        ),
      ),
    );
    await aparencia.setMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(find.text('dark'), findsOneWidget);

    await aparencia.setMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(find.text('light'), findsOneWidget);
  });
}
