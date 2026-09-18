import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/core/theme/orion_theme.dart';
import 'package:servicelog_ai/data/models/equipment.dart';
import 'package:servicelog_ai/data/models/service_case.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/data/repositories/offline_first_service_log_repository.dart';
import 'package:servicelog_ai/data/sync/offline_sync_remote.dart';
import 'package:servicelog_ai/data/sync/sync_operation.dart';
import 'package:servicelog_ai/features/shell/service_log_controller.dart';
import 'package:servicelog_ai/features/sync/conflicts_page.dart';

void main() {
  /// O cenário é montado dentro de cada teste, e não em `setUp`: futuros
  /// criados fora da zona assíncrona do `testWidgets` não completam dentro
  /// dela, e a tela ficaria eternamente no indicador de carregamento.
  ({
    OfflineFirstServiceLogRepository repository,
    ServiceLogController controller,
    _ConflictingRemote remote,
  })
  montar() {
    final store = MemorySnapshotStore();
    final remote = _ConflictingRemote();
    final repository = OfflineFirstServiceLogRepository(
      local: DemoServiceLogRepository.offlineMirror(
        storage: store,
        namespace: 'ui',
      ),
      remote: remote,
      store: store,
      namespace: 'ui',
    );
    final controller = ServiceLogController(repository);
    addTearDown(controller.dispose);
    return (repository: repository, controller: controller, remote: remote);
  }

  /// Prepara o conflito no mesmo relógio simulado do teste.
  ///
  /// Duas armadilhas se cruzam aqui. O repositório simula latência com
  /// `Future.delayed`, que só dispara quando o teste avança o tempo — daí
  /// o `pump` enquanto a preparação corre. E um futuro criado noutra zona
  /// (em `setUp` ou dentro de `runAsync`) nunca completa aqui dentro, o
  /// que deixaria a tela presa no indicador de carregamento; por isso tudo
  /// nasce e termina dentro do corpo do teste.
  Future<void> criarConflito(
    WidgetTester tester,
    OfflineFirstServiceLogRepository repository,
    _ConflictingRemote remote,
    ServiceLogController controller,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final preparo = () async {
      await repository.createCustomer(const CustomerDraft(name: 'Hospital X'));
      remote.conflitando = true;
      try {
        await repository.syncPendingChanges();
      } catch (_) {
        // O conflito é relançado pelo repositório; aqui interessa só o
        // estado que ele deixa na fila.
      }
      await controller.refreshSyncStatus();
    }();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await preparo;
  }

  Future<void> abrir(
    WidgetTester tester,
    ServiceLogController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OrionTheme.light(),
        home: ConflictsPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sem conflitos mostra estado vazio', (tester) async {
    final cenario = montar();
    await abrir(tester, cenario.controller);
    expect(find.text('Nenhum conflito'), findsOneWidget);
  });

  testWidgets('lista o conflito com o registro e as duas saídas', (
    tester,
  ) async {
    final cenario = montar();
    await criarConflito(
      tester,
      cenario.repository,
      cenario.remote,
      cenario.controller,
    );
    await abrir(tester, cenario.controller);

    expect(find.text('Hospital X'), findsOneWidget);
    expect(find.text('Cliente · Edição'), findsOneWidget);
    expect(find.text('Manter a minha versão'), findsOneWidget);
    expect(find.text('Descartar a minha versão'), findsOneWidget);
    expect(
      find.textContaining('nenhuma novidade do servidor entra'),
      findsOneWidget,
      reason: 'o usuário precisa saber que a fila travada bloqueia o download',
    );
  });

  testWidgets('descartar pede confirmação antes de aplicar', (tester) async {
    final cenario = montar();
    await criarConflito(
      tester,
      cenario.repository,
      cenario.remote,
      cenario.controller,
    );
    await abrir(tester, cenario.controller);

    await tester.tap(find.text('Descartar a minha versão'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar sua alteração?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(
      await cenario.repository.fetchConflicts(),
      hasLength(1),
      reason: 'cancelar não pode mexer na fila',
    );

    await tester.tap(find.text('Descartar a minha versão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();

    expect(await cenario.repository.fetchConflicts(), isEmpty);
    expect((await cenario.repository.fetchSyncStatus()).pendingCount, 0);
  });

  testWidgets('manter a versão local reenvia a operação', (tester) async {
    final cenario = montar();
    await criarConflito(
      tester,
      cenario.repository,
      cenario.remote,
      cenario.controller,
    );
    await abrir(tester, cenario.controller);

    await tester.tap(find.text('Manter a minha versão'));
    await tester.pumpAndSettle();
    expect(find.text('Sobrescrever o servidor?'), findsOneWidget);

    cenario.remote.conflitando = false;
    await tester.tap(find.text('Sobrescrever'));
    await tester.pumpAndSettle();

    expect(await cenario.repository.fetchConflicts(), isEmpty);
    expect(cenario.remote.aceitas, hasLength(1));
    expect(
      cenario.remote.basesRecebidas.last,
      0,
      reason: 'base zero é o que faz o servidor aceitar sobrepondo',
    );
  });
}

class _ConflictingRemote implements OfflineSyncRemote {
  bool conflitando = false;
  final List<String> aceitas = [];
  final List<int> basesRecebidas = [];

  @override
  Future<SyncApplyResult> applyOperation(SyncOperation operation) async {
    basesRecebidas.add(operation.expectedRevision);
    if (conflitando) {
      return const SyncApplyResult(
        status: 'conflict',
        message: 'O cliente foi alterado em outro dispositivo.',
      );
    }
    aceitas.add(operation.entityId);
    return const SyncApplyResult(status: 'applied', revision: 3);
  }

  @override
  Future<RemoteSyncSnapshot> pullSnapshot() async => RemoteSyncSnapshot(
    equipment: const [],
    cases: const [],
    catalog: EquipmentCatalog.empty,
    revisions: const {},
    serverTime: DateTime.utc(2026, 9, 18),
  );

  @override
  Future<List<SimilarCaseResult>> searchSimilarCases(
    SimilarCaseQuery query,
  ) async => const [];

  @override
  Future<void> indexResolvedCase(String serviceCaseId) async {}

  @override
  Future<ArchivedRecords> fetchArchived() async =>
      const ArchivedRecords(customers: [], equipment: [], cases: []);

  @override
  Future<void> signOut() async {}
}
