import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/data/models/equipment.dart';
import 'package:servicelog_ai/data/models/service_case.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('busca local prioriza código exato e solução validada', () async {
    final repository = DemoServiceLogRepository.seeded();
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
    final repository = DemoServiceLogRepository.seeded();
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
        cases.any((item) => item.reportedFailure == 'Falha de teste'), isTrue);
  });

  test('cadastros rápidos aceitam cliente e modelo com dados mínimos',
      () async {
    final repository = DemoServiceLogRepository.seeded();

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
      SiteDraft(
        customerId: customerId,
        siteName: 'Hemodinâmica',
      ),
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
    final customer =
        catalog.customers.firstWhere((item) => item.id == customerId);

    expect(model.family, isEmpty);
    expect(model.modality, 'Não informada');
    expect(customer.taxId, isNull);
    expect(catalog.sites.any((item) => item.id == siteId), isTrue);
    expect(equipment.any((item) => item.serialNumber == 'ARTIS-001'), isTrue);
  });
  test('dados opcionais do cliente e do local podem ser preenchidos depois',
      () async {
    final repository = DemoServiceLogRepository.seeded();
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
    final customer =
        catalog.customers.firstWhere((item) => item.id == customerId);
    final site = catalog.sites.firstWhere((item) => item.id == siteId);

    expect(customer.taxId, '00.000.000/0001-00');
    expect(customer.email, 'engenharia@clinica.test');
    expect(site.site, 'Hemodinâmica 1');
    expect(site.locationLabel, 'Curitiba / PR');
  });

  test('atendimento de instalação mantém diário de andamento no mesmo registro',
      () async {
    final repository = DemoServiceLogRepository.seeded();
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
    expect(item.progressEntries.first.description,
        'Posicionamento mecânico concluído.');
  });

  test('novo diário atualiza o mesmo atendimento em vez de criar outro',
      () async {
    final repository = DemoServiceLogRepository.seeded();
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
            (item) => item.reportedFailure == 'Desinstalação para transporte.')
        .toList();
    expect(matching, hasLength(1));
    expect(matching.single.progressEntries, hasLength(2));
  });
}
