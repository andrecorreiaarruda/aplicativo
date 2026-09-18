import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/storage/memory_snapshot_store.dart';
import 'package:servicelog_ai/data/models/equipment.dart';
import 'package:servicelog_ai/data/models/service_case.dart';
import 'package:servicelog_ai/data/repositories/demo_service_log_repository.dart';
import 'package:servicelog_ai/data/repositories/offline_first_service_log_repository.dart';
import 'package:servicelog_ai/data/sync/offline_sync_remote.dart';
import 'package:servicelog_ai/data/sync/sync_operation.dart';

void main() {
  group('repositório local', () {
    late MemorySnapshotStore store;
    late DemoServiceLogRepository repository;

    setUp(() {
      store = MemorySnapshotStore();
      repository = DemoServiceLogRepository.offlineMirror(
        storage: store,
        namespace: 'purge',
      );
    });

    Future<String> criarCliente(String nome) =>
        repository.createCustomer(CustomerDraft(name: nome));

    test('recusa excluir registro que ainda está ativo', () async {
      final id = await criarCliente('Hospital Ativo');
      await expectLater(
        repository.purgeCustomer(id),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'mensagem',
            contains('Só registros arquivados'),
          ),
        ),
      );
    });

    test('exclui cliente arquivado e sem dependentes', () async {
      final id = await criarCliente('Hospital Vazio');
      await repository.archiveCustomer(id);
      await repository.purgeCustomer(id);

      final arquivados = await repository.fetchArchived();
      expect(arquivados.customers, isEmpty);
      final catalogo = await repository.fetchEquipmentCatalog();
      expect(catalogo.customers.where((item) => item.id == id), isEmpty);
    });

    test('dependente arquivado ainda impede a exclusão do cliente', () async {
      // `createCustomerSite` devolve o id do local, não o do cliente.
      await repository.createCustomerSite(
        const CustomerSiteDraft(
          customerName: 'Hospital com Equipamento',
          siteName: 'Sala 1',
        ),
      );
      final catalogo = await repository.fetchEquipmentCatalog();
      final site = catalogo.sites.single;
      final clienteId = site.customerId;
      final modeloId = await repository.createEquipmentModel(
        const EquipmentModelDraft(
          manufacturer: 'Philips',
          model: 'Azurion 7',
          modality: 'Angiografia',
        ),
      );
      await repository.createEquipment(
        EquipmentDraft(
          modelId: modeloId,
          serialNumber: 'AZ-001',
          status: 'operational',
          siteId: site.id,
        ),
      );

      final equipamento = (await repository.fetchEquipments()).single;
      await repository.archiveEquipment(equipamento.id);
      await repository.archiveCustomer(clienteId);

      // O arquivamento passou porque só conta dependentes ativos. A
      // exclusão não pode passar: o equipamento arquivado sairia junto.
      await expectLater(
        repository.purgeCustomer(clienteId),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'mensagem',
            allOf(contains('1 equipamento'), contains('inclusive arquivados')),
          ),
        ),
      );
    });

    test('enfileira a operação de exclusão como purge', () async {
      final id = await criarCliente('Hospital Enfileirado');
      await repository.archiveCustomer(id);
      await repository.purgeCustomer(id);

      final operacoes = await store.pendingOperations('purge');
      expect(operacoes.last.operation, 'purge');
      expect(operacoes.last.entityId, id);
    });
  });

  group('repositório offline', () {
    test('conta dependente arquivado que só existe no servidor', () async {
      final store = MemorySnapshotStore();
      final local = DemoServiceLogRepository.offlineMirror(
        storage: store,
        namespace: 'offline-purge',
      );
      final remote = _RemoteComArquivados();
      final repository = OfflineFirstServiceLogRepository(
        local: local,
        remote: remote,
        store: store,
        namespace: 'offline-purge',
      );

      // O cliente e o local existem no espelho; o equipamento está
      // arquivado e, por isso, só aparece na lista do servidor.
      await repository.createCustomerSite(
        const CustomerSiteDraft(customerName: 'Hospital Remoto', siteName: 'A'),
      );
      final site = (await repository.fetchEquipmentCatalog()).sites.single;
      final clienteId = site.customerId;
      remote.arquivados = ArchivedRecords(
        equipment: [
          Equipment(
            id: 'eq-remoto',
            modelId: 'm',
            manufacturer: 'Philips',
            family: '',
            model: 'Azurion',
            modality: '',
            serialNumber: 'AZ-9',
            customer: 'Hospital Remoto',
            site: 'A',
            siteId: site.id,
            status: 'operational',
            archivedAt: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      await repository.archiveCustomer(clienteId);
      await expectLater(
        repository.purgeCustomer(clienteId),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'mensagem',
            contains('1 equipamento'),
          ),
        ),
      );
    });

    test('exclusão aceita pelo servidor esvazia a fila', () async {
      final store = MemorySnapshotStore();
      final local = DemoServiceLogRepository.offlineMirror(
        storage: store,
        namespace: 'offline-purge-ok',
      );
      final remote = _RemoteComArquivados();
      final repository = OfflineFirstServiceLogRepository(
        local: local,
        remote: remote,
        store: store,
        namespace: 'offline-purge-ok',
      );

      final id = await repository.createCustomer(
        const CustomerDraft(name: 'Hospital Descartável'),
      );
      await repository.archiveCustomer(id);
      await repository.purgeCustomer(id);
      await repository.syncPendingChanges();

      expect((await repository.fetchSyncStatus()).pendingCount, 0);
      expect(remote.operacoes.map((item) => item.operation), contains('purge'));
    });

    test('servidor sem revisão não trava a fila na exclusão', () async {
      final store = MemorySnapshotStore();
      final local = DemoServiceLogRepository.offlineMirror(
        storage: store,
        namespace: 'offline-purge-sem-revisao',
      );
      // Registro já inexistente no servidor: a resposta vem sem revisão.
      final remote = _RemoteComArquivados(revisaoNaResposta: false);
      final repository = OfflineFirstServiceLogRepository(
        local: local,
        remote: remote,
        store: store,
        namespace: 'offline-purge-sem-revisao',
      );

      final id = await repository.createCustomer(
        const CustomerDraft(name: 'Hospital Fantasma'),
      );
      await repository.archiveCustomer(id);
      await repository.purgeCustomer(id);
      await repository.syncPendingChanges();

      expect(
        (await repository.fetchSyncStatus()).pendingCount,
        0,
        reason:
            'sem revisão a exclusão ainda conclui, pois nada há a versionar',
      );
    });
  });
}

class _RemoteComArquivados implements OfflineSyncRemote {
  _RemoteComArquivados({this.revisaoNaResposta = true});

  final bool revisaoNaResposta;
  ArchivedRecords arquivados = ArchivedRecords.empty;
  final List<SyncOperation> operacoes = [];

  @override
  Future<SyncApplyResult> applyOperation(SyncOperation operation) async {
    operacoes.add(operation);
    if (operation.operation == 'purge' && !revisaoNaResposta) {
      return const SyncApplyResult(status: 'applied');
    }
    return const SyncApplyResult(status: 'applied', revision: 4);
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
  Future<ArchivedRecords> fetchArchived() async => arquivados;

  @override
  Future<void> signOut() async {}
}
