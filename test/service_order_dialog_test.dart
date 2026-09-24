import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/core/theme/orion_theme.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/features/service_orders/service_order_archive.dart';
import 'package:servicelog_ai/features/service_orders/service_order_files.dart';
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

void main() {
  testWidgets('emite a OS pelo cartão do atendimento e a abre', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MemorySnapshotStore();
    final files = _MemoryFiles();
    await tester.pumpWidget(
      ServiceOrderScope(
        archive: ServiceOrderArchive(store: store, files: files),
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
}
