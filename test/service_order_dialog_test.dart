import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/core/theme/orion_theme.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/features/service_orders/service_order_archive.dart';
import 'package:servicelog_ai/features/service_orders/service_order_files.dart';
import 'package:servicelog_ai/features/service_orders/service_order_issuer.dart';
import 'package:servicelog_ai/features/shell/service_log_workspace.dart';

class _MemoryFiles implements ServiceOrderFiles {
  final written = <String, Uint8List>{};
  final opened = <String>[];

  @override
  Future<String> folderPath() async => '/memoria/Ordens de serviço';

  @override
  Future<String> write(String fileName, Uint8List bytes) async {
    final path = '/memoria/Ordens de serviço/$fileName';
    written[path] = bytes;
    return path;
  }

  @override
  Future<bool> exists(String path) async => written.containsKey(path);

  @override
  Future<void> open(String path) async => opened.add(path);

  @override
  Future<void> openFolder() async {}
}

Future<(ServiceOrderArchive, _MemoryFiles)> _pumpWorkspace(
  WidgetTester tester, {
  bool withIssuer = true,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = MemorySnapshotStore();
  final files = _MemoryFiles();
  final archive = ServiceOrderArchive(store: store, files: files);
  if (withIssuer) {
    await archive.saveIssuer(
      const ServiceOrderIssuer(
        companyName: 'Oficina Teste',
        responsibleName: 'Técnico ORION',
        city: 'Curitiba/PR',
      ),
    );
  }
  await tester.pumpWidget(
    ServiceOrderScope(
      archive: archive,
      child: MaterialApp(
        theme: OrionTheme.light(),
        home: ServiceLogWorkspace(
          repository: DemoServiceLogRepository.seeded(storage: store),
          profile: const WorkspaceProfile(
            fullName: 'Técnico ORION',
            role: 'Engenheiro',
            organizationName: 'ORION',
          ),
          demoMode: true,
          storageLabel: 'Memória de teste',
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Atendimentos').first);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Emitir ordem de serviço').first);
  await tester.pumpAndSettle();
  return (archive, files);
}

Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

void main() {
  testWidgets('emite a OS pelo cartão do atendimento e a abre', (tester) async {
    final (_, files) = await _pumpWorkspace(tester);

    expect(find.textContaining('Ordem de serviço · OS'), findsOneWidget);
    expect(
      find.text('Nenhuma OS emitida ainda para este atendimento.'),
      findsOneWidget,
    );

    // Gerar o PDF lê as fontes do pacote de recursos, que responde pelo
    // relógio simulado, e monta o documento, que leva tempo real. O laço
    // alterna os dois até a OS ser aberta.
    await tester.tap(find.text('Emitir OS'));
    for (var i = 0; i < 100 && files.opened.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    expect(files.written, hasLength(1));
    final path = files.written.keys.single;
    expect(path, matches(RegExp(r'OS-\d+_\d{4}-\d{2}-\d{2}_\d{4}\.pdf$')));
    expect(String.fromCharCodes(files.written[path]!.take(5)), '%PDF-');
    expect(files.opened, [path]);
    expect(find.text('Emitir nova versão'), findsOneWidget);

    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    // O cartão passa a indicar que a OS já existe.
    expect(find.byTooltip('Ordem de serviço (já emitida)'), findsOneWidget);
  });

  testWidgets('sem emitente, pede os dados antes de emitir', (tester) async {
    await _pumpWorkspace(tester, withIssuer: false);

    expect(
      find.textContaining('Preencha os dados do emitente'),
      findsOneWidget,
    );
    final emitir = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Emitir OS'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(emitir.onPressed, isNull);
  });

  testWidgets('complementos ficam guardados ao fechar', (tester) async {
    await _pumpWorkspace(tester);

    await tester.enterText(_field('Patrimônio'), 'PAT-123');
    await tester.tap(find.text('Calibração / aferição'));
    await tester.tap(find.text('Adicionar material'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Descrição'), 'Fusível 10 A');
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    // Reabre: o que foi digitado volta.
    await tester.tap(find.byTooltip('Emitir ordem de serviço').first);
    await tester.pumpAndSettle();
    expect(find.text('PAT-123'), findsOneWidget);
    expect(find.text('Fusível 10 A'), findsOneWidget);
    final chip = tester.widget<FilterChip>(
      find.ancestor(
        of: find.text('Calibração / aferição'),
        matching: find.byType(FilterChip),
      ),
    );
    expect(chip.selected, isTrue);
  });
}
