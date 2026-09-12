import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/runtime/app_runtime.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/features/recovery/storage_gate.dart';

void main() {
  testWidgets('não abre workspace sem armazenamento; retry recupera', (
    tester,
  ) async {
    var attempts = 0;
    var workspaceBuilt = false;
    await tester.pumpWidget(
      StorageGate(
        openRuntime: () async {
          if (++attempts == 1) throw StateError('SQLite unavailable');
          // Explicit test double; production openRuntime always opens SQLite.
          return AppRuntime(localStore: MemorySnapshotStore());
        },
        builder: (_) {
          workspaceBuilt = true;
          return const MaterialApp(home: Text('Workspace'));
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(workspaceBuilt, isFalse);
    expect(find.text('Armazenamento local indisponível'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(workspaceBuilt, isTrue);
    expect(find.text('Workspace'), findsOneWidget);
    expect(attempts, 2);
  });
}
