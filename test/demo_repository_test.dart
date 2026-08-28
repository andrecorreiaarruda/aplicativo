import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/data/models/equipment.dart';
import 'package:servicelog_ai/data/models/service_case.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';

void main() {
  test('busca local prioriza código exato e solução validada', () async {
    final repository = DemoServiceLogRepository.seeded(
      storage: MemorySnapshotStore(),
    );
    final results = await repository.searchSimilarCases(
      const SimilarCaseQuery(
        text: 'aquisição interrompida após aquecimento do sistema',
        errorCode: 'XPER-ACQ-42',
        subsystem: 'Cadeia de aquisição',
      ),
    );

    expect(results, isNotEmpty);
    expect(results.first.serviceCase.errorCode, 'XPER-ACQ-42');
    expect(results.first.score, greaterThan(0.5));
  });

  test('novo atendimento fica disponível na listagem', () async {
    final repository = DemoServiceLogRepository.seeded(
      storage: MemorySnapshotStore(),
    );
    await repository.saveCase(
      const ServiceCaseDraft(
        equipmentId: 'eq-allura-001',
        reportedFailure: 'Falha de teste',
        status: 'open',
        operationalImpact: 'degraded',
        solutionConfidence: 'unconfirmed',
      ),
    );

    final cases = await repository.fetchCases();
    expect(
      cases.any((item) => item.reportedFailure == 'Falha de teste'),
      isTrue,
    );
  });

  test(
    'cadastros rápidos aceitam cliente e modelo com dados mínimos',
    () async {
      final repository = DemoServiceLogRepository.seeded(
        storage: MemorySnapshotStore(),
      );

      final modelId = await repository.createEquipmentModel(
        const EquipmentModelDraft(
          manufacturer: 'Siemens Healthineers',
          model: 'Artis zee',
          modality: '',
        ),
      );
      final customerId = await repository.createCustomer(
        const CustomerDraft(name: 'Hospital de Teste'),
      );
      final siteId = await repository.createSite(
        SiteDraft(customerId: customerId, siteName: 'Hemodinâmica'),
      );
      await repository.createEquipment(
        EquipmentDraft(
          modelId: modelId,
          serialNumber: 'ARTIS-001',
          siteId: siteId,
          status: 'operational',
        ),
      );

      final catalog = await repository.fetchEquipmentCatalog();
      final equipment = await repository.fetchEquipments();
      final model = catalog.models.firstWhere((item) => item.id == modelId);
      final customer = catalog.customers.firstWhere(
        (item) => item.id == customerId,
      );

      expect(model.family, isEmpty);
      expect(model.modality, 'Não informada');
      expect(customer.taxId, isNull);
      expect(catalog.sites.any((item) => item.id == siteId), isTrue);
      expect(equipment.any((item) => item.serialNumber == 'ARTIS-001'), isTrue);
    },
  );
  test(
    'dados opcionais do cliente e do local podem ser preenchidos depois',
    () async {
      final repository = DemoServiceLogRepository.seeded(
        storage: MemorySnapshotStore(),
      );
      final customerId = await repository.createCustomer(
        const CustomerDraft(name: 'Clínica sem cadastro completo'),
      );
      final siteId = await repository.createSite(
        SiteDraft(customerId: customerId, siteName: 'Sala 1'),
      );

      await repository.updateCustomer(
        customerId,
        const CustomerDraft(
          name: 'Clínica sem cadastro completo',
          taxId: '00.000.000/0001-00',
          email: 'engenharia@clinica.test',
          phone: '(41) 99999-0000',
        ),
      );
      await repository.updateSite(
        siteId,
        SiteDraft(
          customerId: customerId,
          siteName: 'Hemodinâmica 1',
          city: 'Curitiba',
          state: 'PR',
        ),
      );

      final catalog = await repository.fetchEquipmentCatalog();
      final customer = catalog.customers.firstWhere(
        (item) => item.id == customerId,
      );
      final site = catalog.sites.firstWhere((item) => item.id == siteId);

      expect(customer.taxId, '00.000.000/0001-00');
      expect(customer.email, 'engenharia@clinica.test');
      expect(site.site, 'Hemodinâmica 1');
      expect(site.locationLabel, 'Curitiba / PR');
    },
  );

  test(
    'atendimento de instalação mantém diário de andamento no mesmo registro',
    () async {
      final repository = DemoServiceLogRepository.seeded(
        storage: MemorySnapshotStore(),
      );
      final firstEntry = ServiceProgressEntry(
        id: 'progress-1',
        occurredAt: DateTime(2026, 7, 27, 9),
        description: 'Posicionamento mecânico concluído.',
      );

      await repository.saveCase(
        ServiceCaseDraft(
          equipmentId: 'eq-azurion-002',
          activityType: ServiceActivityType.installation,
          reportedFailure: 'Instalação e comissionamento do sistema.',
          status: 'diagnosing',
          operationalImpact: 'none',
          solutionConfidence: 'unconfirmed',
          progressEntries: [firstEntry],
        ),
      );

      final cases = await repository.fetchCases();
      final item = cases.firstWhere(
        (value) =>
            value.reportedFailure == 'Instalação e comissionamento do sistema.',
      );

      expect(item.activityType, ServiceActivityType.installation);
      expect(item.activityLabel, 'Instalação');
      expect(item.progressEntries, hasLength(1));
      expect(
        item.progressEntries.first.description,
        'Posicionamento mecânico concluído.',
      );
    },
  );

  test(
    'novo diário atualiza o mesmo atendimento em vez de criar outro',
    () async {
      final repository = DemoServiceLogRepository.seeded(
        storage: MemorySnapshotStore(),
      );
      await repository.saveCase(
        ServiceCaseDraft(
          equipmentId: 'eq-versa-003',
          activityType: ServiceActivityType.deinstallation,
          reportedFailure: 'Desinstalação para transporte.',
          status: 'diagnosing',
          operationalImpact: 'none',
          solutionConfidence: 'unconfirmed',
          progressEntries: [
            ServiceProgressEntry(
              id: 'day-1',
              occurredAt: DateTime(2026, 7, 27, 8),
              description: 'Sistema desenergizado e cabos identificados.',
            ),
          ],
        ),
      );

      final firstLoad = await repository.fetchCases();
      final original = firstLoad.firstWhere(
        (item) => item.reportedFailure == 'Desinstalação para transporte.',
      );

      await repository.saveCase(
        ServiceCaseDraft(
          id: original.id,
          equipmentId: original.equipmentId,
          activityType: original.activityType,
          reportedFailure: original.reportedFailure,
          status: 'diagnosing',
          operationalImpact: original.operationalImpact,
          solutionConfidence: original.solutionConfidence,
          progressEntries: [
            ...original.progressEntries,
            ServiceProgressEntry(
              id: 'day-2',
              occurredAt: DateTime(2026, 7, 28, 8),
              description: 'Gantry desmontada e volumes conferidos.',
            ),
          ],
        ),
      );

      final secondLoad = await repository.fetchCases();
      final matching = secondLoad
          .where(
            (item) => item.reportedFailure == 'Desinstalação para transporte.',
          )
          .toList();
      expect(matching, hasLength(1));
      expect(matching.single.progressEntries, hasLength(2));
    },
  );

  test('edição de equipamento atualiza a etiqueta no histórico', () async {
    final repository = DemoServiceLogRepository.seeded(
      storage: MemorySnapshotStore(),
    );

    final equipamentos = await repository.fetchEquipments();
    final alvo = equipamentos.first;
    final atendimentos = await repository.fetchCases();
    final vinculado = atendimentos.firstWhere(
      (item) => item.equipmentId == alvo.id,
    );
    // Antes da edição, a etiqueta carrega o número de série original.
    expect(vinculado.equipmentLabel, contains(alvo.serialNumber));

    await repository.updateEquipment(
      alvo.id,
      EquipmentDraft(
        modelId: alvo.modelId,
        serialNumber: 'SERIE-TROCADA-001',
        siteId: alvo.siteId,
        status: 'maintenance',
        notes: 'Editado no teste',
      ),
    );

    final editado = (await repository.fetchEquipments()).firstWhere(
      (item) => item.id == alvo.id,
    );
    expect(editado.serialNumber, 'SERIE-TROCADA-001');
    expect(editado.status, 'maintenance');
    expect(editado.notes, 'Editado no teste');

    // O atendimento vinculado precisa refletir o novo número de série,
    // porque a etiqueta é desnormalizada para exibição.
    final apos = (await repository.fetchCases()).firstWhere(
      (item) => item.id == vinculado.id,
    );
    expect(apos.equipmentLabel, contains('SERIE-TROCADA-001'));
  });

  test(
    'edição recusa número de série já usado por outro equipamento',
    () async {
      final repository = DemoServiceLogRepository.seeded(
        storage: MemorySnapshotStore(),
      );

      final equipamentos = await repository.fetchEquipments();
      final primeiro = equipamentos[0];
      final segundo = equipamentos[1];

      await expectLater(
        repository.updateEquipment(
          primeiro.id,
          EquipmentDraft(
            modelId: primeiro.modelId,
            serialNumber: segundo.serialNumber,
            siteId: primeiro.siteId,
            status: primeiro.status,
          ),
        ),
        throwsStateError,
      );
    },
  );

  test('arquivar cliente é bloqueado enquanto houver histórico', () async {
    final repository = DemoServiceLogRepository.seeded(
      storage: MemorySnapshotStore(),
    );
    final catalogo = await repository.fetchEquipmentCatalog();
    final cliente = catalogo.customers.first;

    // O cliente semeado tem equipamentos e atendimentos: deve recusar.
    await expectLater(
      repository.archiveCustomer(cliente.id),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'mensagem',
          allOf(contains('equipamento'), contains('atendimento')),
        ),
      ),
    );

    // E continua visível, porque nada foi arquivado.
    final depois = await repository.fetchEquipmentCatalog();
    expect(depois.customers.any((item) => item.id == cliente.id), isTrue);
  });

  test('arquivar segue a ordem atendimento, equipamento, cliente', () async {
    final repository = DemoServiceLogRepository.seeded(
      storage: MemorySnapshotStore(),
    );

    final equipamento = (await repository.fetchEquipments()).first;
    final atendimentos = (await repository.fetchCases())
        .where((item) => item.equipmentId == equipamento.id)
        .toList();
    expect(atendimentos, isNotEmpty);

    // Equipamento com atendimento é recusado.
    await expectLater(
      repository.archiveEquipment(equipamento.id),
      throwsStateError,
    );

    // Atendimento é folha: sempre arquivável.
    for (final item in atendimentos) {
      await repository.archiveCase(item.id);
    }
    expect(
      (await repository.fetchCases()).any(
        (item) => item.id == atendimentos.first.id,
      ),
      isFalse,
    );

    // Sem atendimentos, o equipamento libera.
    await repository.archiveEquipment(equipamento.id);
    final ativos = await repository.fetchEquipments();
    expect(ativos.any((item) => item.id == equipamento.id), isFalse);

    // Arquivar não apaga: o registro aparece na lista de arquivados.
    final arquivados = await repository.fetchArchived();
    expect(
      arquivados.equipment.any((item) => item.id == equipamento.id),
      isTrue,
    );
    expect(arquivados.cases, hasLength(atendimentos.length));
  });

  test('restaurar devolve o registro às listagens', () async {
    final repository = DemoServiceLogRepository.seeded(
      storage: MemorySnapshotStore(),
    );
    final atendimento = (await repository.fetchCases()).first;

    await repository.archiveCase(atendimento.id);
    expect(
      (await repository.fetchCases()).any((item) => item.id == atendimento.id),
      isFalse,
    );

    await repository.restoreCase(atendimento.id);
    expect(
      (await repository.fetchCases()).any((item) => item.id == atendimento.id),
      isTrue,
    );
    expect((await repository.fetchArchived()).cases, isEmpty);
  });

  test('arquivamento sobrevive à reabertura do aplicativo', () async {
    final storage = MemorySnapshotStore();
    final primeira = DemoServiceLogRepository.seeded(
      storage: storage,
      namespace: 'arquivo-persistente',
      journalChanges: true,
    );
    final atendimento = (await primeira.fetchCases()).first;
    await primeira.archiveCase(atendimento.id);

    // Mesmo armazenamento, instância nova: simula reabrir o aplicativo.
    final segunda = DemoServiceLogRepository.seeded(
      storage: storage,
      namespace: 'arquivo-persistente',
      journalChanges: true,
    );
    expect(
      (await segunda.fetchCases()).any((item) => item.id == atendimento.id),
      isFalse,
    );
    expect((await segunda.fetchArchived()).cases, hasLength(1));
  });

  test('estado local é reidratado pelo armazenamento persistente', () async {
    final store = MemorySnapshotStore();
    final firstRepository = DemoServiceLogRepository.seeded(
      storage: store,
      namespace: 'persistence-test',
    );

    await firstRepository.createCustomer(
      const CustomerDraft(name: 'Hospital Persistente'),
    );

    final secondRepository = DemoServiceLogRepository.seeded(
      storage: store,
      namespace: 'persistence-test',
    );
    final catalog = await secondRepository.fetchEquipmentCatalog();

    expect(
      catalog.customers.any((item) => item.name == 'Hospital Persistente'),
      isTrue,
    );
  });

  test('alterações locais entram na fila de sincronização', () async {
    final store = MemorySnapshotStore();
    final repository = DemoServiceLogRepository.seeded(
      storage: store,
      namespace: 'sync-test',
      journalChanges: true,
    );

    await repository.createCustomer(
      const CustomerDraft(name: 'Cliente offline'),
    );

    final status = await repository.fetchSyncStatus();
    expect(status.pendingCount, 1);
  });
}
