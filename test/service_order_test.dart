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
import 'package:servicelog_ai/features/service_orders/service_order_files.dart';
import 'package:servicelog_ai/features/service_orders/service_order_files_native.dart';
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

ServiceOrder _assemble(ServiceCase item, {bool withCatalog = true}) =>
    ServiceOrder.assemble(
      item: item,
      equipment: withCatalog ? _equipment : null,
      site: withCatalog ? _site : null,
      customer: withCatalog ? _customer : null,
      organizationName: 'ORION',
      issuerName: 'André Leite',
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
    test('cliente, local e equipamento saem do cadastro', () {
      final order = _assemble(_case());

      expect(_fields(order.customerFields), {
        'Cliente': 'Hospital Central',
        'CNPJ / CPF': '12.345.678/0001-90',
        'Local': 'Hemodinâmica — Campinas / SP',
        'Endereço': 'Rua das Flores, 100 — São Paulo / SP',
        'Contato': 'Maria Souza',
        'Telefone': '(19) 3333-4444',
        'E-mail': 'engenharia@hospital.example',
      });
      expect(_fields(order.equipmentFields), {
        'Equipamento': 'Philips Azurion 7',
        'Modalidade': 'Angiografia',
        'Número de série': 'AZ-001',
        'Versão de software': '2.1',
      });
      expect(order.statusLabel, 'Concluído');
      expect(order.activityLabel, 'Manutenção');
    });

    test('usa os nomes de campo do formulário, sem o "(opcional)"', () {
      final order = _assemble(_case(subsystem: 'Gerador'));
      final chamado = _fields(order.sections.first.fields);

      expect(order.sections.map((s) => s.title), [
        'Chamado',
        'Diagnóstico',
        'Conclusão',
      ]);
      expect(chamado['Falha relatada'], 'Tubo não emite raios X');
      expect(chamado['Código de erro'], 'E-1234');
      expect(chamado['Subsistema'], 'Gerador');
      expect(chamado['Impacto operacional'], 'Parada total');
      expect(
        _fields(order.sections.last.fields)['Condição final do equipamento'],
        'Operacional',
      );
    });

    test('instalação usa os nomes da instalação', () {
      final order = _assemble(
        _case(activityType: ServiceActivityType.installation),
      );
      final chamado = _fields(order.sections.first.fields);

      expect(chamado.keys, contains('Escopo da instalação'));
      expect(chamado['Projeto / OS / referência'], 'E-1234');
      expect(order.sections[1].title, 'Execução');
      expect(
        _fields(order.sections.last.fields).keys,
        contains('Configuração e serviços concluídos'),
      );
    });

    test('campos vazios ficam fora', () {
      final order = _assemble(_case(errorCode: '  '));
      final labels = [
        for (final section in order.sections)
          for (final field in section.fields) field.label,
      ];

      expect(labels, isNot(contains('Código de erro')));
      expect(labels, isNot(contains('Subsistema')));
      expect(labels, isNot(contains('Retorno ou acompanhamento')));
    });

    test('retorno pedido sem plano ainda aparece', () {
      final order = _assemble(_case(requiresFollowUp: true));

      expect(
        _fields(order.sections.last.fields)['Retorno ou acompanhamento'],
        'Necessário, a combinar.',
      );
    });

    test('sem cadastro, o equipamento vem da etiqueta do atendimento', () {
      final order = _assemble(_case(), withCatalog: false);

      expect(order.customerFields, isEmpty);
      expect(_fields(order.equipmentFields), {
        'Equipamento': 'Philips Azurion 7 · AZ-001',
      });
    });

    test('sessões em ordem cronológica e tempo técnico só das encerradas', () {
      final order = _assemble(
        _case(
          entries: [
            ServiceProgressEntry(
              id: 'b',
              occurredAt: DateTime(2026, 9, 21, 13),
              endedAt: DateTime(2026, 9, 21, 17, 5),
              description: 'Troca do gerador',
            ),
            ServiceProgressEntry(
              id: 'a',
              occurredAt: DateTime(2026, 9, 20, 9),
              endedAt: DateTime(2026, 9, 20, 11, 30),
              description: 'Diagnóstico',
            ),
            ServiceProgressEntry(
              id: 'c',
              occurredAt: DateTime(2026, 9, 22, 8),
              description: 'Retorno',
            ),
          ],
        ),
      );

      expect(order.sessions.map((s) => s.description), [
        'Diagnóstico',
        'Troca do gerador',
        'Retorno',
      ]);
      expect(order.serviceMinutes, 150 + 245);
      expect(order.sessions.last.minutes, isNull);
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
          for (var i = 0; i < 30; i++)
            ServiceProgressEntry(
              id: '$i',
              occurredAt: DateTime(2026, 9, 1 + i % 20, 8),
              endedAt: DateTime(2026, 9, 1 + i % 20, 9),
              description: longo,
            ),
        ],
      ),
    );

    final bytes = await buildServiceOrderPdf(order, assets);

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
