import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/data/models/equipment.dart';
import 'package:servicelog_ai/data/models/service_case.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/features/service_orders/service_order.dart';
import 'package:servicelog_ai/features/service_orders/service_order_archive.dart';
import 'package:servicelog_ai/features/service_orders/service_order_details.dart';
import 'package:servicelog_ai/features/service_orders/service_order_files.dart';
import 'package:servicelog_ai/features/service_orders/service_order_files_native.dart';
import 'package:servicelog_ai/features/service_orders/service_order_issuer.dart';
import 'package:servicelog_ai/features/service_orders/service_order_pdf.dart';
import 'package:pdf/widgets.dart' as pw;

ServiceCase _case({
  String activityType = ServiceActivityType.maintenance,
  String status = 'resolved',
  List<ServiceProgressEntry> entries = const [],
  bool requiresFollowUp = false,
  String? followUpNotes,
  String? errorCode = 'E-1234',
  String? subsystem,
  String solutionDetails = 'Substituído o gerador de alta tensão.',
}) => ServiceCase(
  id: 'case-1',
  caseNumber: 1234,
  equipmentId: 'eq-1',
  equipmentLabel: 'Philips Azurion 7 · AZ-001',
  status: status,
  activityType: activityType,
  openedAt: DateTime(2026, 9, 20, 8, 30),
  closedAt: status == 'resolved' ? DateTime(2026, 9, 21, 17, 5) : null,
  reportedFailure: 'Tubo não emite raios X',
  operationalImpact: 'total_stop',
  solutionConfidence: 'confirmed',
  progressEntries: entries,
  errorCode: errorCode,
  subsystem: subsystem,
  observedSymptoms: 'Falha no início da exposição',
  solutionDetails: solutionDetails,
  validationResult: 'Exposições de teste aprovadas.',
  finalEquipmentStatus: 'operational',
  downtimeMinutes: 1440,
  requiresFollowUp: requiresFollowUp,
  followUpNotes: followUpNotes,
);

const _equipment = Equipment(
  id: 'eq-1',
  modelId: 'm-1',
  manufacturer: 'Philips',
  family: 'Azurion',
  model: 'Azurion 7',
  modality: 'Angiografia',
  serialNumber: 'AZ-001',
  customer: 'Hospital Central',
  site: 'Hemodinâmica',
  status: 'operational',
  siteId: 'site-1',
  softwareVersion: '2.1',
);

const _site = SiteOption(
  id: 'site-1',
  customerId: 'cust-1',
  customer: 'Hospital Central',
  site: 'Hemodinâmica',
  city: 'Campinas',
  state: 'SP',
);

const _customer = CustomerOption(
  id: 'cust-1',
  name: 'Hospital Central',
  taxId: '12.345.678/0001-90',
  contactName: 'Maria Souza',
  phone: '(19) 3333-4444',
  email: 'engenharia@hospital.example',
  addressLine: 'Rua das Flores, 100',
  city: 'São Paulo',
  state: 'SP',
);

const _issuer = ServiceOrderIssuer(
  companyName: 'Orion Serviços Eletrônicos',
  taxId: '00.000.000/0001-00',
  address: 'Rua Exemplo, 100 — Centro, Curitiba/PR',
  city: 'Curitiba/PR',
  responsibleName: 'Responsável Exemplo',
  responsibleTitle: 'Engenheiro Eletricista',
  registration: 'CREA-PR 000000/D',
  phone: '(41) 90000-0000',
  email: 'contato@example.com',
);

ServiceOrder _assemble(
  ServiceCase item, {
  bool withCatalog = true,
  ServiceOrderDetails details = const ServiceOrderDetails(),
}) => ServiceOrder.assemble(
  item: item,
  equipment: withCatalog ? _equipment : null,
  site: withCatalog ? _site : null,
  customer: withCatalog ? _customer : null,
  issuer: _issuer,
  details: details,
  issuedAt: DateTime(2026, 9, 24, 9, 7),
);

Map<String, String> _fields(List<ServiceOrderField> fields) => {
  for (final field in fields) field.label: field.value,
};

class _MemoryFiles implements ServiceOrderFiles {
  final written = <String, Uint8List>{};

  @override
  Future<String> folderPath() async => '/memoria/OS';

  @override
  Future<String> write(String fileName, Uint8List bytes) async {
    final path = '/memoria/OS/$fileName';
    written[path] = bytes;
    return path;
  }

  @override
  Future<bool> exists(String path) async => written.containsKey(path);

  @override
  Future<void> open(String path) async {}

  @override
  Future<void> openFolder() async {}
}

void main() {
  group('montagem da OS', () {
    test('dados do atendimento vêm do cadastro e dos complementos', () {
      final order = _assemble(
        _case(),
        details: const ServiceOrderDetails(
          requester: 'Enf. Carla',
          sector: 'Hemodinâmica 2',
          assetTag: 'PAT-0099',
        ),
      );

      expect(order.customer, 'Hospital Central');
      expect(order.address, 'Rua das Flores, 100 — São Paulo / SP');
      expect(order.sector, 'Hemodinâmica 2');
      expect(order.requester, 'Enf. Carla');
      expect(order.equipment, 'Angiografia');
      expect(order.serialAndTag, 'AZ-001 / PAT-0099');
      expect(order.manufacturerModel, 'Philips / Azurion 7');
    });

    test('abertura, início, término e parada', () {
      final order = _assemble(
        _case(
          entries: [
            ServiceProgressEntry(
              id: 'b',
              occurredAt: DateTime(2026, 9, 21, 13),
              endedAt: DateTime(2026, 9, 21, 17, 5),
              description: 'Troca',
            ),
            ServiceProgressEntry(
              id: 'a',
              occurredAt: DateTime(2026, 9, 20, 9),
              endedAt: DateTime(2026, 9, 20, 11, 30),
              description: 'Diagnóstico',
            ),
          ],
        ),
      );

      expect(order.openedAt, DateTime(2026, 9, 20, 8, 30));
      expect(order.startedAt, DateTime(2026, 9, 20, 9));
      expect(order.finishedAt, DateTime(2026, 9, 21, 17, 5));
      expect(order.downtimeMinutes, 1440);
    });

    test('sem conclusão, o término é o fim da última sessão', () {
      final order = _assemble(
        _case(
          status: 'diagnosing',
          entries: [
            ServiceProgressEntry(
              id: 'a',
              occurredAt: DateTime(2026, 9, 20, 9),
              endedAt: DateTime(2026, 9, 20, 11, 30),
              description: 'Diagnóstico',
            ),
            ServiceProgressEntry(
              id: 'b',
              occurredAt: DateTime(2026, 9, 22, 8),
              description: 'Em aberto',
            ),
          ],
        ),
      );

      expect(order.finishedAt, DateTime(2026, 9, 20, 11, 30));
    });

    test('manutenção usa os nomes do modelo de OS', () {
      final order = _assemble(_case());
      final narrative = _fields(order.narrative);

      expect(narrative.keys, [
        'Relato do cliente',
        'Causa identificada',
        'Procedimento executado',
      ]);
      expect(
        narrative['Relato do cliente'],
        'Tubo não emite raios X\nCódigo de erro: E-1234',
      );
      expect(
        narrative['Procedimento executado'],
        'Substituído o gerador de alta tensão.',
      );
      // Sem causa registrada, a casa sai vazia, mas sai.
      expect(narrative['Causa identificada'], '');
      expect(_fields(order.testNotes), {
        'Validação final': 'Exposições de teste aprovadas.',
      });
    });

    test('instalação usa os nomes do formulário da instalação', () {
      final order = _assemble(
        _case(activityType: ServiceActivityType.installation),
      );

      expect(order.narrative.map((field) => field.label), [
        'Escopo da instalação',
        'Pendências, desvios ou interferências',
        'Configuração e serviços concluídos',
      ]);
      expect(
        order.narrative.first.value,
        contains('Projeto / OS / referência: E-1234'),
      );
    });

    test('sem cadastro, o equipamento vem da etiqueta do atendimento', () {
      final order = _assemble(_case(), withCatalog: false);

      expect(order.customer, isEmpty);
      expect(order.manufacturerModel, 'Philips Azurion 7 · AZ-001');
    });

    test('materiais vazios ficam fora', () {
      final order = _assemble(
        _case(),
        details: const ServiceOrderDetails(
          materials: [
            ServiceOrderMaterial(description: 'Fusível 10 A', quantity: '2'),
            ServiceOrderMaterial(),
          ],
        ),
      );

      expect(order.materials.map((m) => m.description), ['Fusível 10 A']);
    });

    test('local e data por extenso', () {
      expect(
        _assemble(_case()).placeAndDate,
        'Curitiba/PR, 24 de setembro de 2026.',
      );
    });

    test('nome do arquivo leva número, data e hora da emissão', () {
      expect(_assemble(_case()).fileName, 'OS-1234_2026-09-24_0907.pdf');
    });

    test('formatação dos minutos', () {
      expect(ServiceOrder.formatMinutes(0), '0 min');
      expect(ServiceOrder.formatMinutes(45), '45 min');
      expect(ServiceOrder.formatMinutes(125), '2h 05min');
    });
  });

  group('complementos sugeridos', () {
    test('vêm do cadastro e da condição final', () {
      final details = ServiceOrderDetails.suggest(
        item: _case(
          requiresFollowUp: true,
          followUpNotes: 'Revisar em 30 dias',
        ),
        site: _site,
        customer: _customer,
        equipment: _equipment,
      );

      expect(details.requester, 'Maria Souza');
      expect(details.sector, 'Hemodinâmica');
      expect(details.situation, ServiceOrderSituation.released);
      expect(details.checks, {
        ServiceOrderCheck.functionalTest,
        ServiceOrderCheck.followUpNeeded,
      });
      expect(details.recommendations, 'Revisar em 30 dias');
    });

    test('aguardando peça vira "aguardando peça / aprovação"', () {
      expect(
        ServiceOrderDetails.suggestSituation(_case(status: 'waiting_parts')),
        ServiceOrderSituation.awaiting,
      );
    });

    test('ida e volta pelo JSON', () {
      const details = ServiceOrderDetails(
        requester: 'Carla',
        sector: 'UTI',
        assetTag: 'P-1',
        materials: [
          ServiceOrderMaterial(
            description: 'Sensor',
            partNumber: 'PN-9',
            quantity: '1',
            warranty: '90 dias',
          ),
        ],
        checks: {ServiceOrderCheck.calibration, ServiceOrderCheck.alarms},
        situation: ServiceOrderSituation.restricted,
        recommendations: 'Trocar filtro',
      );
      final back = ServiceOrderDetails.fromJson(
        jsonDecode(jsonEncode(details.toJson())) as Map,
      );

      expect(back.requester, 'Carla');
      expect(back.assetTag, 'P-1');
      expect(back.materials.single.partNumber, 'PN-9');
      expect(back.checks, details.checks);
      expect(back.situation, ServiceOrderSituation.restricted);
      expect(back.recommendations, 'Trocar filtro');
    });
  });

  group('emitente', () {
    test('linhas do rodapé e da assinatura', () {
      expect(
        _issuer.companyLine,
        'Orion Serviços Eletrônicos – CNPJ 00.000.000/0001-00 – '
        'Rua Exemplo, 100 — Centro, Curitiba/PR',
      );
      expect(
        _issuer.responsibleLine,
        'Responsável Exemplo — Engenheiro Eletricista, CREA-PR 000000/D – '
        '(41) 90000-0000 – contato@example.com',
      );
      expect(
        _issuer.signatureCaption,
        'Responsável Técnico — CREA-PR 000000/D',
      );
    });

    test('campos vazios não deixam separadores soltos', () {
      const issuer = ServiceOrderIssuer(
        companyName: 'Oficina',
        responsibleName: 'Fulano',
      );
      expect(issuer.companyLine, 'Oficina');
      expect(issuer.responsibleLine, 'Fulano');
      expect(issuer.isComplete, isTrue);
      expect(ServiceOrderIssuer.empty.isComplete, isFalse);
    });

    test('é guardado no banco local', () async {
      final archive = ServiceOrderArchive(
        store: MemorySnapshotStore(),
        files: _MemoryFiles(),
      );
      expect((await archive.loadIssuer()).isComplete, isFalse);

      await archive.saveIssuer(_issuer);

      expect((await archive.loadIssuer()).registration, 'CREA-PR 000000/D');
    });
  });

  test('texto longo é dividido em pedaços que cabem na página', () {
    final semQuebras = List.filled(500, 'palavra').join(' ');
    final pieces = splitForPages(semQuebras, maxLength: 1000);

    expect(pieces.length, greaterThan(1));
    expect(pieces.every((piece) => piece.length <= 1000), isTrue);
    expect(pieces.join(' '), semQuebras);
    expect(splitForPages('curto'), ['curto']);
  });

  test('gera um PDF válido com acentos e várias páginas', () async {
    final assets = ServiceOrderAssets(
      regular: pw.Font.ttf(
        File(
          'assets/fonts/Roboto-Regular.ttf',
        ).readAsBytesSync().buffer.asByteData(),
      ),
      bold: pw.Font.ttf(
        File(
          'assets/fonts/Roboto-Bold.ttf',
        ).readAsBytesSync().buffer.asByteData(),
      ),
      logo: File('assets/branding/orion-logo.jpg').readAsBytesSync(),
    );
    final longo = List.filled(
      40,
      'Ação corretiva — “calibração” 80 kV ±2%, 25 °C, 1,2 µGy, 10 Ω',
    ).join(' ');
    // Uma solução de mais de uma folha sozinha precisa continuar na
    // seguinte, e não estourar a página.
    final order = _assemble(
      _case(
        solutionDetails: List.filled(8, longo).join('\n\n'),
        entries: [
          for (var i = 0; i < 3; i++)
            ServiceProgressEntry(
              id: '$i',
              occurredAt: DateTime(2026, 9, 1 + i % 20, 8),
              endedAt: DateTime(2026, 9, 1 + i % 20, 9),
              description: longo,
            ),
        ],
      ),
    );

    final full = _assemble(
      _case(solutionDetails: List.filled(8, longo).join('\n\n')),
      details: ServiceOrderDetails(
        materials: [
          for (var i = 0; i < 12; i++)
            ServiceOrderMaterial(
              description: 'Item $i — $longo'.substring(0, 80),
              partNumber: 'PN-$i',
              quantity: '$i',
              warranty: '90 dias',
            ),
        ],
        checks: ServiceOrderCheck.values.toSet(),
        situation: ServiceOrderSituation.awaiting,
        recommendations: longo * 3,
      ),
    );
    expect(order.caseNumber, full.caseNumber);

    final bytes = await buildServiceOrderPdf(full, assets);

    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    final text = latin1.decode(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, greaterThan(1));
  });

  group('registro das OS emitidas', () {
    test(
      'guarda por atendimento, da mais recente para a mais antiga',
      () async {
        final files = _MemoryFiles();
        final archive = ServiceOrderArchive(
          store: MemorySnapshotStore(),
          files: files,
        );

        await archive.record(
          caseId: 'case-1',
          fileName: 'OS-1_a.pdf',
          bytes: Uint8List.fromList([1]),
          issuedAt: DateTime(2026, 9, 1),
        );
        await archive.record(
          caseId: 'case-1',
          fileName: 'OS-1_b.pdf',
          bytes: Uint8List.fromList([2]),
          issuedAt: DateTime(2026, 9, 2),
        );
        await archive.record(
          caseId: 'case-2',
          fileName: 'OS-2.pdf',
          bytes: Uint8List.fromList([3]),
          issuedAt: DateTime(2026, 9, 3),
        );

        final issued = await archive.issuedFor('case-1');
        expect(issued.map((item) => item.fileName), [
          'OS-1_b.pdf',
          'OS-1_a.pdf',
        ]);
        expect((await archive.loadAll()).keys, {'case-1', 'case-2'});
        expect(files.written, hasLength(3));
      },
    );

    test('índice ilegível recomeça vazio em vez de travar', () async {
      final store = MemorySnapshotStore();
      await store.writeMetadata('ordens-servico', 'emitidas', '{quebrado');
      final archive = ServiceOrderArchive(store: store, files: _MemoryFiles());

      expect(await archive.loadAll(), isEmpty);
    });
  });

  test('não sobrescreve uma OS já gravada com o mesmo nome', () async {
    final base = await Directory.systemTemp.createTemp('orion-os-');
    addTearDown(() => base.delete(recursive: true));
    final files = NativeServiceOrderFiles(baseDirectory: () async => base);

    final first = await files.write('OS-1.pdf', Uint8List.fromList([1]));
    final second = await files.write('OS-1.pdf', Uint8List.fromList([2]));

    expect(first, endsWith('OS-1.pdf'));
    expect(second, endsWith('OS-1 (2).pdf'));
    expect(File(first).readAsBytesSync(), [1]);
    expect(
      Directory(await files.folderPath()).listSync().map((e) => e.path),
      unorderedEquals([first, second]),
    );
  });

  group('número provisório', () {
    Future<(DemoServiceLogRepository, String)> criarAtendimento(
      DemoServiceLogRepository repository,
    ) async {
      await repository.createCustomerSite(
        const CustomerSiteDraft(customerName: 'Hospital', siteName: 'Sala'),
      );
      final site = (await repository.fetchEquipmentCatalog()).sites.single;
      final modelId = await repository.createEquipmentModel(
        const EquipmentModelDraft(
          manufacturer: 'GE',
          model: 'Revolution',
          modality: 'Tomografia',
        ),
      );
      await repository.createEquipment(
        EquipmentDraft(
          modelId: modelId,
          serialNumber: 'RV-1',
          status: 'operational',
          siteId: site.id,
        ),
      );
      final equipment = (await repository.fetchEquipments()).single;
      await repository.saveCase(
        ServiceCaseDraft(
          equipmentId: equipment.id,
          reportedFailure: 'Falha',
          status: 'open',
          operationalImpact: 'none',
          solutionConfidence: 'unconfirmed',
        ),
      );
      final created = (await repository.fetchCases()).single;
      return (repository, created.id);
    }

    test('atendimento criado offline é provisório até o download', () async {
      final store = MemorySnapshotStore();
      final (repository, caseId) = await criarAtendimento(
        DemoServiceLogRepository.offlineMirror(storage: store, namespace: 'n'),
      );

      expect(await repository.isCaseNumberProvisional(caseId), isTrue);

      // A marca sobrevive a reabrir o aplicativo.
      final reopened = DemoServiceLogRepository.offlineMirror(
        storage: store,
        namespace: 'n',
      );
      expect(await reopened.isCaseNumberProvisional(caseId), isTrue);

      // Editar não muda nada: o número continua o local.
      final item = (await reopened.fetchCases()).single;
      await reopened.saveCase(
        ServiceCaseDraft(
          id: item.id,
          equipmentId: item.equipmentId,
          reportedFailure: 'Falha revisada',
          status: 'open',
          operationalImpact: 'none',
          solutionConfidence: 'unconfirmed',
        ),
      );
      expect(await reopened.isCaseNumberProvisional(caseId), isTrue);

      // O download só é aplicado com a fila vazia, e traz o número do
      // servidor.
      for (final operation in await store.pendingOperations('n')) {
        await store.removeOperation(operation.id);
      }
      await reopened.replaceFromRemote(
        equipment: await reopened.fetchEquipments(),
        cases: await reopened.fetchCases(),
        catalog: await reopened.fetchEquipmentCatalog(),
        revisions: {'service_case:$caseId': 1},
      );
      expect(await reopened.isCaseNumberProvisional(caseId), isFalse);
    });

    test('na demonstração, sem servidor, o número já é o definitivo', () async {
      final repository = DemoServiceLogRepository.seeded(journalChanges: true);
      final equipment = (await repository.fetchEquipments()).first;
      await repository.saveCase(
        ServiceCaseDraft(
          equipmentId: equipment.id,
          reportedFailure: 'Falha nova',
          status: 'open',
          operationalImpact: 'none',
          solutionConfidence: 'unconfirmed',
        ),
      );
      final created = (await repository.fetchCases()).firstWhere(
        (item) => item.reportedFailure == 'Falha nova',
      );

      expect(await repository.isCaseNumberProvisional(created.id), isFalse);
    });
  });
}
