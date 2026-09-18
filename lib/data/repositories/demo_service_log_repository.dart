import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/storage/local_snapshot_store.dart';
import '../../core/storage/async_mutex.dart';
import '../../core/storage/memory_snapshot_store.dart';

import '../models/equipment.dart';
import '../models/service_case.dart';
import '../models/service_time_metrics.dart';
import '../sync/sync_conflict.dart';
import '../sync/sync_operation.dart';
import '../sync/sync_queue_service.dart';
import 'service_log_repository.dart';

class DemoServiceLogRepository
    implements ServiceLogRepository, SyncAwareRepository {
  DemoServiceLogRepository._({
    required List<Equipment> equipment,
    required List<ServiceCase> cases,
    required List<EquipmentModelOption> models,
    required List<CustomerOption> customers,
    required List<SiteOption> sites,
    required LocalSnapshotStore storage,
    required String namespace,
    required bool isDemo,
    required bool useUuidIds,
    SyncQueueService? syncQueue,
    Uuid? uuid,
  }) : _storage = storage,
       _syncQueue = syncQueue,
       _namespace = namespace,
       _isDemo = isDemo,
       _useUuidIds = useUuidIds,
       _uuid = uuid ?? const Uuid(),
       _equipment = equipment,
       _cases = cases,
       _models = models,
       _customers = customers,
       _sites = sites;

  factory DemoServiceLogRepository.seeded({
    LocalSnapshotStore? storage,
    String namespace = 'demo-local',
    bool journalChanges = false,
  }) {
    final resolvedStorage = storage ?? MemorySnapshotStore();
    final models = <EquipmentModelOption>[
      const EquipmentModelOption(
        id: 'model-allura-fd10',
        manufacturer: 'Philips',
        family: 'Allura Xper',
        model: 'Allura Xper FD10',
        modality: 'Angiografia',
      ),
      const EquipmentModelOption(
        id: 'model-azurion-7',
        manufacturer: 'Philips',
        family: 'Azurion',
        model: 'Azurion 7 M20',
        modality: 'Angiografia',
      ),
      const EquipmentModelOption(
        id: 'model-versa-hd',
        manufacturer: 'Elekta',
        family: 'Versa HD',
        model: 'Versa HD',
        modality: 'Radioterapia',
      ),
    ];

    final customers = <CustomerOption>[
      const CustomerOption(
        id: 'customer-hospital-central',
        name: 'Hospital Central',
      ),
      const CustomerOption(
        id: 'customer-oncologia',
        name: 'Instituto de Oncologia',
      ),
    ];

    final sites = <SiteOption>[
      const SiteOption(
        id: 'site-hospital-central',
        customerId: 'customer-hospital-central',
        customer: 'Hospital Central',
        site: 'Hemodinâmica 1',
        city: 'Curitiba',
        state: 'PR',
      ),
      const SiteOption(
        id: 'site-hospital-central-2',
        customerId: 'customer-hospital-central',
        customer: 'Hospital Central',
        site: 'Hemodinâmica 2',
        city: 'Curitiba',
        state: 'PR',
      ),
      const SiteOption(
        id: 'site-oncologia',
        customerId: 'customer-oncologia',
        customer: 'Instituto de Oncologia',
        site: 'Bunker 2',
        city: 'Curitiba',
        state: 'PR',
      ),
    ];

    final equipment = <Equipment>[
      const Equipment(
        id: 'eq-allura-001',
        modelId: 'model-allura-fd10',
        manufacturer: 'Philips',
        family: 'Allura Xper',
        model: 'Allura Xper FD10',
        modality: 'Angiografia',
        serialNumber: 'FD10-OR-001',
        customer: 'Hospital Central',
        site: 'Hemodinâmica 1',
        siteId: 'site-hospital-central',
        softwareVersion: 'R8.2',
        hardwareVersion: 'Rev. C',
        status: 'operational',
      ),
      const Equipment(
        id: 'eq-azurion-002',
        modelId: 'model-azurion-7',
        manufacturer: 'Philips',
        family: 'Azurion',
        model: 'Azurion 7 M20',
        modality: 'Angiografia',
        serialNumber: 'AZ7-OR-002',
        customer: 'Hospital Central',
        site: 'Hemodinâmica 2',
        siteId: 'site-hospital-central-2',
        softwareVersion: '2.1.1',
        status: 'degraded',
      ),
      const Equipment(
        id: 'eq-versa-003',
        modelId: 'model-versa-hd',
        manufacturer: 'Elekta',
        family: 'Versa HD',
        model: 'Versa HD',
        modality: 'Radioterapia',
        serialNumber: 'EVHD-OR-003',
        customer: 'Instituto de Oncologia',
        site: 'Bunker 2',
        siteId: 'site-oncologia',
        softwareVersion: 'MOSAIQ 2.83',
        status: 'operational',
      ),
    ];

    final now = DateTime.now();
    final cases = <ServiceCase>[
      ServiceCase(
        id: 'case-101',
        caseNumber: 101,
        equipmentId: 'eq-allura-001',
        equipmentLabel: 'Philips Allura Xper FD10 · FD10-OR-001',
        status: 'resolved',
        openedAt: now.subtract(const Duration(days: 50)),
        closedAt: now.subtract(const Duration(days: 49, hours: 20)),
        reportedFailure: 'Aquisição interrompida após aquecimento do sistema.',
        observedSymptoms:
            'Falha intermitente após cerca de 20 minutos; baixa dose permanecia funcional.',
        errorCode: 'XPER-ACQ-42',
        subsystem: 'Cadeia de aquisição',
        operationalImpact: 'partial_stop',
        measurements:
            'Tensões estáveis. Temperatura elevada no módulo de aquisição.',
        rootCause:
            'Ventilação insuficiente no módulo de aquisição por obstrução do filtro.',
        solutionDetails:
            'Limpeza do conjunto de ventilação, substituição do filtro e restauração da configuração.',
        validationResult:
            'Executadas 50 aquisições em diferentes protocolos sem recorrência.',
        finalEquipmentStatus: 'operational',
        solutionConfidence: 'confirmed',
        downtimeMinutes: 245,
        serviceMinutes: 210,
      ),
      ServiceCase(
        id: 'case-102',
        caseNumber: 102,
        equipmentId: 'eq-allura-001',
        equipmentLabel: 'Philips Allura Xper FD10 · FD10-OR-001',
        status: 'resolved',
        openedAt: now.subtract(const Duration(days: 24)),
        closedAt: now.subtract(const Duration(days: 23, hours: 21)),
        reportedFailure: 'Movimento do arco interrompe durante rotação.',
        observedSymptoms:
            'Parada reproduzida entre 20° e 35° com ruído no acionamento.',
        errorCode: 'GEO-MOT-17',
        subsystem: 'Geometria / C-arm',
        operationalImpact: 'total_stop',
        measurements: 'Feedback do encoder apresentou perda intermitente.',
        rootCause: 'Conector do encoder com contato intermitente.',
        solutionDetails:
            'Reassentamento, limpeza técnica do conector e fixação do chicote.',
        validationResult:
            'Vinte ciclos completos e calibração geométrica aprovados.',
        finalEquipmentStatus: 'operational',
        solutionConfidence: 'recurring',
        downtimeMinutes: 180,
        serviceMinutes: 150,
      ),
      ServiceCase(
        id: 'case-103',
        caseNumber: 103,
        equipmentId: 'eq-versa-003',
        equipmentLabel: 'Elekta Versa HD · EVHD-OR-003',
        status: 'resolved',
        openedAt: now.subtract(const Duration(days: 12)),
        closedAt: now.subtract(const Duration(days: 11, hours: 20)),
        reportedFailure: 'Interlock de MLC impede início do feixe.',
        observedSymptoms:
            'Banco B não conclui posicionamento; falha em campos modulados.',
        errorCode: 'MLC-BANK-B-POS',
        subsystem: 'MLC',
        operationalImpact: 'total_stop',
        measurements:
            'Desvio de posição superior à tolerância em duas lâminas.',
        rootCause:
            'Desalinhamento mecânico e necessidade de recalibração das lâminas.',
        solutionDetails:
            'Inspeção mecânica, correção do alinhamento e execução da calibração do MLC.',
        validationResult:
            'QA de posicionamento aprovado e tratamentos de teste executados.',
        finalEquipmentStatus: 'operational',
        solutionConfidence: 'reviewed',
        downtimeMinutes: 320,
        serviceMinutes: 280,
      ),
      ServiceCase(
        id: 'case-104',
        caseNumber: 104,
        equipmentId: 'eq-azurion-002',
        equipmentLabel: 'Philips Azurion 7 M20 · AZ7-OR-002',
        status: 'diagnosing',
        openedAt: now.subtract(const Duration(hours: 9)),
        reportedFailure:
            'Imagem apresenta artefato intermitente em fluoroscopia.',
        observedSymptoms:
            'Linhas horizontais aparecem após movimentação da mesa.',
        errorCode: 'IMG-DET-09',
        subsystem: 'Detector / imagem',
        operationalImpact: 'degraded',
        measurements: 'Logs coletados; inspeção de cabos em andamento.',
        solutionConfidence: 'unconfirmed',
        downtimeMinutes: 40,
        serviceMinutes: 75,
        requiresFollowUp: true,
        followUpNotes:
            'Repetir teste com o sistema aquecido e verificar o chicote móvel.',
      ),
    ];

    return DemoServiceLogRepository._(
      equipment: equipment,
      cases: cases,
      models: models,
      customers: customers,
      sites: sites,
      storage: resolvedStorage,
      namespace: namespace,
      syncQueue: journalChanges
          ? SyncQueueService(store: resolvedStorage, namespace: namespace)
          : null,
      isDemo: true,
      useUuidIds: false,
    );
  }

  factory DemoServiceLogRepository.offlineMirror({
    required LocalSnapshotStore storage,
    required String namespace,
  }) {
    return DemoServiceLogRepository._(
      equipment: <Equipment>[],
      cases: <ServiceCase>[],
      models: <EquipmentModelOption>[],
      customers: <CustomerOption>[],
      sites: <SiteOption>[],
      storage: storage,
      namespace: namespace,
      syncQueue: SyncQueueService(store: storage, namespace: namespace),
      isDemo: false,
      useUuidIds: true,
    );
  }

  final _mutex = AsyncMutex();
  final List<SyncOperation> _stagedOperations = [];
  final LocalSnapshotStore _storage;
  final SyncQueueService? _syncQueue;
  final String _namespace;
  final bool _isDemo;
  final bool _useUuidIds;
  final Uuid _uuid;
  final Map<String, int> _remoteRevisions = <String, int>{};
  final List<Equipment> _equipment;
  final List<ServiceCase> _cases;
  final List<EquipmentModelOption> _models;
  final List<CustomerOption> _customers;
  final List<SiteOption> _sites;
  Future<void>? _hydrationFuture;
  int _equipmentSequence = 10;
  int _caseSequence = 105;
  int _catalogSequence = 100;

  @override
  bool get isDemo => _isDemo;

  @override
  Future<List<Equipment>> fetchEquipments() => _mutex.run(_fetchEquipments);

  Future<List<Equipment>> _fetchEquipments() async {
    await _ensureHydrated();
    await _latency();
    // Arquivados continuam no armazenamento, mas fora das listagens.
    return List.unmodifiable(_equipment.where((item) => !item.isArchived));
  }

  @override
  Future<List<ServiceCase>> fetchCases() => _mutex.run(_fetchCases);

  Future<List<ServiceCase>> _fetchCases() async {
    await _ensureHydrated();
    await _latency();
    final result = _cases.where((item) => !item.isArchived).toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return List.unmodifiable(result);
  }

  @override
  Future<EquipmentCatalog> fetchEquipmentCatalog() =>
      _mutex.run(_fetchEquipmentCatalog);

  Future<EquipmentCatalog> _fetchEquipmentCatalog() async {
    await _ensureHydrated();
    await _latency();
    final ativos = _customers.where((item) => !item.isArchived).toList();
    final idsAtivos = ativos.map((item) => item.id).toSet();
    return EquipmentCatalog(
      models: List.unmodifiable(_models),
      customers: List.unmodifiable(ativos),
      // Um local de cliente arquivado não deve aparecer para seleção,
      // senão seria possível cadastrar equipamento sob um cliente que
      // não está mais em uso.
      sites: List.unmodifiable(
        _sites.where((item) => idsAtivos.contains(item.customerId)),
      ),
    );
  }

  @override
  Future<String> createEquipmentModel(EquipmentModelDraft draft) =>
      _mutate(() => _createEquipmentModel(draft));

  Future<String> _createEquipmentModel(EquipmentModelDraft draft) async {
    await _ensureHydrated();
    await _latency();
    final manufacturer = draft.manufacturer.trim();
    final modelName = draft.model.trim();
    final existing = _models.where(
      (item) =>
          item.manufacturer.toLowerCase() == manufacturer.toLowerCase() &&
          item.model.toLowerCase() == modelName.toLowerCase(),
    );
    if (existing.isNotEmpty) return existing.first.id;

    final id = _nextId('model');
    _models.add(
      EquipmentModelOption(
        id: id,
        manufacturer: manufacturer,
        family: draft.family?.trim() ?? '',
        model: modelName,
        modality: _fallback(draft.modality, 'Não informada'),
      ),
    );
    await _journal(
      entityType: 'equipment_model',
      entityId: id,
      payload: {
        'id': id,
        'manufacturer': manufacturer,
        'family': draft.family?.trim(),
        'model': modelName,
        'modality': _fallback(draft.modality, 'Não informada'),
        'description': _blankToNull(draft.description),
      },
    );
    return id;
  }

  @override
  Future<String> createCustomer(CustomerDraft draft) =>
      _mutate(() => _createCustomer(draft));

  Future<String> _createCustomer(CustomerDraft draft) async {
    await _ensureHydrated();
    await _latency();
    final name = draft.name.trim();
    final existing = _customers.where(
      (item) => item.name.toLowerCase() == name.toLowerCase(),
    );
    if (existing.isNotEmpty) return existing.first.id;

    final id = _nextId('customer');
    _customers.add(
      CustomerOption(
        id: id,
        name: name,
        taxId: _blankToNull(draft.taxId),
        contactName: _blankToNull(draft.contactName),
        email: _blankToNull(draft.email),
        phone: _blankToNull(draft.phone),
        addressLine: _blankToNull(draft.addressLine),
        city: _blankToNull(draft.city),
        state: _blankToNull(draft.state),
        notes: _blankToNull(draft.notes),
      ),
    );
    await _journal(
      entityType: 'customer',
      entityId: id,
      payload: _customerDraftPayload(id, draft),
    );
    return id;
  }

  @override
  Future<void> updateCustomer(String id, CustomerDraft draft) =>
      _mutate(() => _updateCustomer(id, draft));

  Future<void> _updateCustomer(String id, CustomerDraft draft) async {
    await _ensureHydrated();
    await _latency();
    final index = _customers.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Cliente não encontrado.');

    final name = draft.name.trim();
    final duplicate = _customers.any(
      (item) => item.id != id && item.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) throw StateError('Já existe um cliente com esse nome.');

    _customers[index] = CustomerOption(
      id: id,
      name: name,
      taxId: _blankToNull(draft.taxId),
      contactName: _blankToNull(draft.contactName),
      email: _blankToNull(draft.email),
      phone: _blankToNull(draft.phone),
      addressLine: _blankToNull(draft.addressLine),
      city: _blankToNull(draft.city),
      state: _blankToNull(draft.state),
      notes: _blankToNull(draft.notes),
    );

    final affectedSiteIds = <String>{};
    for (var i = 0; i < _sites.length; i++) {
      final site = _sites[i];
      if (site.customerId != id) continue;
      affectedSiteIds.add(site.id);
      _sites[i] = SiteOption(
        id: site.id,
        customerId: site.customerId,
        customer: name,
        site: site.site,
        city: site.city,
        state: site.state,
        notes: site.notes,
      );
    }

    for (var i = 0; i < _equipment.length; i++) {
      final item = _equipment[i];
      if (!affectedSiteIds.contains(item.siteId)) continue;
      _equipment[i] = Equipment(
        id: item.id,
        modelId: item.modelId,
        manufacturer: item.manufacturer,
        family: item.family,
        model: item.model,
        modality: item.modality,
        serialNumber: item.serialNumber,
        customer: name,
        site: item.site,
        status: item.status,
        siteId: item.siteId,
        softwareVersion: item.softwareVersion,
        hardwareVersion: item.hardwareVersion,
        notes: item.notes,
      );
    }

    await _journal(
      entityType: 'customer',
      entityId: id,
      payload: _customerDraftPayload(id, draft),
    );
  }

  @override
  Future<String> createSite(SiteDraft draft) =>
      _mutate(() => _createSite(draft));

  Future<String> _createSite(SiteDraft draft) async {
    await _ensureHydrated();
    await _latency();
    final customer = _customers.firstWhere(
      (item) => item.id == draft.customerId,
    );
    final siteName = draft.siteName.trim();
    final existing = _sites.where(
      (item) =>
          item.customerId == customer.id &&
          item.site.toLowerCase() == siteName.toLowerCase(),
    );
    if (existing.isNotEmpty) return existing.first.id;

    final id = _nextId('site');
    _sites.add(
      SiteOption(
        id: id,
        customerId: customer.id,
        customer: customer.name,
        site: siteName,
        city: _blankToNull(draft.city),
        state: _blankToNull(draft.state),
        notes: _blankToNull(draft.notes),
      ),
    );
    await _journal(
      entityType: 'site',
      entityId: id,
      payload: _siteDraftPayload(id, draft),
    );
    return id;
  }

  @override
  Future<void> updateSite(String id, SiteDraft draft) =>
      _mutate(() => _updateSite(id, draft));

  Future<void> _updateSite(String id, SiteDraft draft) async {
    await _ensureHydrated();
    await _latency();
    final index = _sites.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Local não encontrado.');
    final customer = _customers.firstWhere(
      (item) => item.id == draft.customerId,
    );
    final siteName = draft.siteName.trim();
    final duplicate = _sites.any(
      (item) =>
          item.id != id &&
          item.customerId == customer.id &&
          item.site.toLowerCase() == siteName.toLowerCase(),
    );
    if (duplicate) {
      throw StateError('Já existe um local com esse nome para o cliente.');
    }

    _sites[index] = SiteOption(
      id: id,
      customerId: customer.id,
      customer: customer.name,
      site: siteName,
      city: _blankToNull(draft.city),
      state: _blankToNull(draft.state),
      notes: _blankToNull(draft.notes),
    );

    for (var i = 0; i < _equipment.length; i++) {
      final item = _equipment[i];
      if (item.siteId != id) continue;
      _equipment[i] = Equipment(
        id: item.id,
        modelId: item.modelId,
        manufacturer: item.manufacturer,
        family: item.family,
        model: item.model,
        modality: item.modality,
        serialNumber: item.serialNumber,
        customer: customer.name,
        site: siteName,
        status: item.status,
        siteId: item.siteId,
        softwareVersion: item.softwareVersion,
        hardwareVersion: item.hardwareVersion,
        notes: item.notes,
      );
    }

    await _journal(
      entityType: 'site',
      entityId: id,
      payload: _siteDraftPayload(id, draft),
    );
  }

  @override
  Future<String> createCustomerSite(CustomerSiteDraft draft) =>
      _mutate(() => _createCustomerSite(draft));

  Future<String> _createCustomerSite(CustomerSiteDraft draft) async {
    final customerId = await _createCustomer(
      CustomerDraft(
        name: draft.customerName,
        taxId: draft.taxId,
        contactName: draft.contactName,
        email: draft.email,
        phone: draft.phone,
        addressLine: draft.addressLine,
        city: draft.customerCity,
        state: draft.customerState,
        notes: draft.customerNotes,
      ),
    );
    return _createSite(
      SiteDraft(
        customerId: customerId,
        siteName: draft.siteName,
        city: draft.siteCity ?? draft.city,
        state: draft.siteState ?? draft.state,
        notes: draft.siteNotes,
      ),
    );
  }

  @override
  Future<void> createEquipment(EquipmentDraft draft) =>
      _mutate(() => _createEquipment(draft));

  Future<void> _createEquipment(EquipmentDraft draft) async {
    await _ensureHydrated();
    await _latency();
    final serial = draft.serialNumber.trim();

    // O banco tem unique (organization_id, serial_number). Sem checar
    // aqui, o cadastro era aceito localmente, recusado na sincronização,
    // e depois sumia da tela quando o pull substituía o estado local
    // pelo remoto — dando a impressão de que um equipamento havia
    // substituído o outro. Arquivados contam: a restrição do banco não
    // os ignora.
    // Sem série não há o que colidir: o banco guarda nulo, e nulos são
    // distintos entre si no índice único.
    final duplicate =
        serial.isNotEmpty &&
        _equipment.any(
          (item) => item.serialNumber.toLowerCase() == serial.toLowerCase(),
        );
    if (duplicate) {
      throw StateError(
        'Já existe um equipamento com o número de série "$serial". '
        'Cada unidade precisa de uma série distinta, mesmo sendo do '
        'mesmo modelo.',
      );
    }

    final model = _models.firstWhere((item) => item.id == draft.modelId);
    final matchingSites = _sites.where((item) => item.id == draft.siteId);
    final site = matchingSites.isEmpty ? null : matchingSites.first;
    final id = _nextId('eq');
    _equipment.add(
      Equipment(
        id: id,
        modelId: model.id,
        manufacturer: model.manufacturer,
        family: model.family,
        model: model.model,
        modality: model.modality,
        serialNumber: serial,
        customer: site?.customer ?? '',
        site: site?.site ?? '',
        siteId: site?.id,
        softwareVersion: _blankToNull(draft.softwareVersion),
        hardwareVersion: _blankToNull(draft.hardwareVersion),
        status: draft.status,
        notes: _blankToNull(draft.notes),
      ),
    );
    _equipmentSequence++;
    await _journal(
      entityType: 'equipment',
      entityId: id,
      payload: {
        'id': id,
        'equipment_model_id': draft.modelId,
        'site_id': draft.siteId,
        'serial_number': serial.isEmpty ? null : serial,
        'software_version': _blankToNull(draft.softwareVersion),
        'hardware_version': _blankToNull(draft.hardwareVersion),
        'status': draft.status,
        'notes': _blankToNull(draft.notes),
      },
    );
  }

  @override
  Future<void> updateEquipment(String id, EquipmentDraft draft) =>
      _mutate(() => _updateEquipment(id, draft));

  Future<void> _updateEquipment(String id, EquipmentDraft draft) async {
    await _ensureHydrated();
    await _latency();
    final index = _equipment.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Equipamento não encontrado.');

    final serial = draft.serialNumber.trim();
    final duplicate =
        serial.isNotEmpty &&
        _equipment.any(
          (item) =>
              item.id != id &&
              item.serialNumber.toLowerCase() == serial.toLowerCase(),
        );
    if (duplicate) {
      throw StateError(
        'Já existe um equipamento com o número de série "$serial".',
      );
    }

    final model = _models.firstWhere((item) => item.id == draft.modelId);
    final matchingSites = _sites.where((item) => item.id == draft.siteId);
    final site = matchingSites.isEmpty ? null : matchingSites.first;

    _equipment[index] = Equipment(
      id: id,
      modelId: model.id,
      manufacturer: model.manufacturer,
      family: model.family,
      model: model.model,
      modality: model.modality,
      serialNumber: serial,
      customer: site?.customer ?? '',
      site: site?.site ?? '',
      siteId: site?.id,
      softwareVersion: _blankToNull(draft.softwareVersion),
      hardwareVersion: _blankToNull(draft.hardwareVersion),
      status: draft.status,
      notes: _blankToNull(draft.notes),
    );

    // Os atendimentos guardam uma etiqueta desnormalizada do equipamento
    // para exibição. Sem atualizá-la, o histórico continuaria mostrando o
    // modelo ou o número de série antigos depois da edição.
    for (var i = 0; i < _cases.length; i++) {
      final item = _cases[i];
      if (item.equipmentId != id) continue;
      _cases[i] = item.copyWith(
        // Sem série, a etiqueta não carrega o separador solto.
        equipmentLabel: [
          '${model.manufacturer} ${model.model}',
          if (serial.isNotEmpty) serial,
        ].join(' · '),
      );
    }

    await _journal(
      entityType: 'equipment',
      entityId: id,
      payload: {
        'id': id,
        'equipment_model_id': draft.modelId,
        'site_id': draft.siteId,
        'serial_number': serial.isEmpty ? null : serial,
        'software_version': _blankToNull(draft.softwareVersion),
        'hardware_version': _blankToNull(draft.hardwareVersion),
        'status': draft.status,
        'notes': _blankToNull(draft.notes),
      },
    );
  }

  // ---------------------------------------------------------------------
  // Arquivamento
  // ---------------------------------------------------------------------
  // O registro recebe `archivedAt` e some das listagens, mas continua no
  // armazenamento. Arquivar é recusado enquanto houver histórico
  // dependente: num registro de serviço técnico, o histórico é o ativo
  // principal e não pode ser escondido por um clique em outro cadastro.

  /// Equipamentos de um cliente, através dos locais dele.
  ///
  /// [incluirArquivados] distingue os dois usos: arquivar só se importa
  /// com o que ainda está ativo, enquanto excluir em definitivo precisa
  /// contar também o arquivado — ele sairia em cascata e deixaria
  /// histórico órfão.
  List<Equipment> _equipmentOfCustomer(
    String customerId, {
    bool incluirArquivados = false,
  }) {
    final siteIds = _sites
        .where((item) => item.customerId == customerId)
        .map((item) => item.id)
        .toSet();
    return _equipment
        .where(
          (item) =>
              (incluirArquivados || !item.isArchived) &&
              siteIds.contains(item.siteId),
        )
        .toList(growable: false);
  }

  List<ServiceCase> _casesOfEquipment(
    String equipmentId, {
    bool incluirArquivados = false,
  }) => _cases
      .where(
        (item) =>
            (incluirArquivados || !item.isArchived) &&
            item.equipmentId == equipmentId,
      )
      .toList(growable: false);

  static String _plural(int count, String singular, String plural) =>
      count == 1 ? '1 $singular' : '$count $plural';

  @override
  Future<void> archiveCustomer(String id) =>
      _mutate(() => _archiveCustomer(id));

  Future<void> _archiveCustomer(String id) async {
    await _ensureHydrated();
    await _latency();
    final index = _customers.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Cliente não encontrado.');
    if (_customers[index].isArchived) return;

    final equipamentos = _equipmentOfCustomer(id);
    final atendimentos = equipamentos
        .expand((item) => _casesOfEquipment(item.id))
        .length;
    if (equipamentos.isNotEmpty || atendimentos > 0) {
      final partes = <String>[
        if (equipamentos.isNotEmpty)
          _plural(equipamentos.length, 'equipamento', 'equipamentos'),
        if (atendimentos > 0)
          _plural(atendimentos, 'atendimento', 'atendimentos'),
      ];
      // O verbo acompanha o total, não cada parte: "1 equipamento depende",
      // mas "1 equipamento e 2 atendimentos dependem".
      final unico =
          partes.length == 1 && equipamentos.length + atendimentos == 1;
      throw StateError(
        'Não é possível arquivar: ${partes.join(' e ')} ainda '
        '${unico ? 'depende' : 'dependem'} deste cliente. Arquive-os primeiro.',
      );
    }

    final atual = _customers[index];
    _customers[index] = CustomerOption(
      id: atual.id,
      name: atual.name,
      taxId: atual.taxId,
      contactName: atual.contactName,
      email: atual.email,
      phone: atual.phone,
      addressLine: atual.addressLine,
      city: atual.city,
      state: atual.state,
      notes: atual.notes,
      archivedAt: DateTime.now(),
    );
    await _journal(
      entityType: 'customer',
      entityId: id,
      operation: 'archive',
      payload: {'id': id},
    );
  }

  @override
  Future<void> archiveEquipment(String id) =>
      _mutate(() => _archiveEquipment(id));

  Future<void> _archiveEquipment(String id) async {
    await _ensureHydrated();
    await _latency();
    final index = _equipment.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Equipamento não encontrado.');
    if (_equipment[index].isArchived) return;

    final atendimentos = _casesOfEquipment(id);
    if (atendimentos.isNotEmpty) {
      throw StateError(
        'Não é possível arquivar: '
        '${_plural(atendimentos.length, 'atendimento depende', 'atendimentos dependem')} '
        'deste equipamento. Arquive-os primeiro.',
      );
    }

    _equipment[index] = _withArchivedAt(_equipment[index], DateTime.now());
    await _journal(
      entityType: 'equipment',
      entityId: id,
      operation: 'archive',
      payload: {'id': id},
    );
  }

  @override
  Future<void> archiveCase(String id) => _mutate(() => _archiveCase(id));

  Future<void> _archiveCase(String id) async {
    await _ensureHydrated();
    await _latency();
    final index = _cases.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Atendimento não encontrado.');
    if (_cases[index].isArchived) return;

    // Atendimento é folha: nada depende dele, então nunca é bloqueado.
    _cases[index] = _cases[index].copyWith(archivedAt: DateTime.now());
    await _journal(
      entityType: 'service_case',
      entityId: id,
      operation: 'archive',
      payload: {'id': id},
    );
  }

  // ---------------------------------------------------------------------
  // Exclusão definitiva
  // ---------------------------------------------------------------------
  // A linha sai do banco. Duas exigências antes disso: o registro precisa
  // estar arquivado, e não pode ter nenhum dependente — nem arquivado.
  //
  // A contagem aqui enxerga apenas o espelho local, que guarda o que veio
  // do download (ativos) mais o que foi arquivado neste dispositivo e
  // ainda não sincronizou. Registros arquivados noutro dispositivo ficam
  // fora dessa conta; quem fecha essa lacuna é o repositório offline,
  // que soma a lista de arquivados do servidor antes de delegar, e o
  // próprio servidor, que recusa em último caso.

  @override
  Future<void> purgeCustomer(String id) => _mutate(() => _purgeCustomer(id));

  Future<void> _purgeCustomer(String id) async {
    await _ensureHydrated();
    await _latency();
    final index = _customers.indexWhere((item) => item.id == id);
    if (index >= 0) {
      if (!_customers[index].isArchived) {
        throw StateError(
          'Só registros arquivados podem ser excluídos em definitivo. '
          'Arquive o cliente primeiro.',
        );
      }
      final equipamentos = _equipmentOfCustomer(id, incluirArquivados: true);
      final atendimentos = equipamentos
          .expand((item) => _casesOfEquipment(item.id, incluirArquivados: true))
          .length;
      assertNoPurgeBlockers(
        'cliente',
        equipamentos: equipamentos.length,
        atendimentos: atendimentos,
      );
      _customers.removeAt(index);
      _sites.removeWhere((item) => item.customerId == id);
    }
    // Ausente do espelho não é erro: um registro arquivado noutro
    // dispositivo só existe na lista vinda do servidor, e é de lá que a
    // tela de Arquivados o oferece para exclusão.
    await _journal(
      entityType: 'customer',
      entityId: id,
      operation: 'purge',
      payload: {'id': id},
    );
  }

  @override
  Future<void> purgeEquipment(String id) => _mutate(() => _purgeEquipment(id));

  Future<void> _purgeEquipment(String id) async {
    await _ensureHydrated();
    await _latency();
    final index = _equipment.indexWhere((item) => item.id == id);
    if (index >= 0) {
      if (!_equipment[index].isArchived) {
        throw StateError(
          'Só registros arquivados podem ser excluídos em definitivo. '
          'Arquive o equipamento primeiro.',
        );
      }
      assertNoPurgeBlockers(
        'equipamento',
        equipamentos: 0,
        atendimentos: _casesOfEquipment(id, incluirArquivados: true).length,
      );
      _equipment.removeAt(index);
    }
    await _journal(
      entityType: 'equipment',
      entityId: id,
      operation: 'purge',
      payload: {'id': id},
    );
  }

  @override
  Future<void> purgeCase(String id) => _mutate(() => _purgeCase(id));

  Future<void> _purgeCase(String id) async {
    await _ensureHydrated();
    await _latency();
    final index = _cases.indexWhere((item) => item.id == id);
    if (index >= 0) {
      if (!_cases[index].isArchived) {
        throw StateError(
          'Só registros arquivados podem ser excluídos em definitivo. '
          'Arquive o atendimento primeiro.',
        );
      }
      // Atendimento é folha: nada depende dele.
      _cases.removeAt(index);
    }
    await _journal(
      entityType: 'service_case',
      entityId: id,
      operation: 'purge',
      payload: {'id': id},
    );
  }

  /// Recusa a exclusão quando há dependentes, com a contagem por extenso.
  /// Exposta porque o repositório offline refaz a conta sobre a visão
  /// completa — local mais arquivados do servidor — e precisa recusar com
  /// a mesma frase.
  static void assertNoPurgeBlockers(
    String tipo, {
    required int equipamentos,
    required int atendimentos,
  }) {
    if (equipamentos == 0 && atendimentos == 0) return;
    final partes = <String>[
      if (equipamentos > 0)
        _plural(equipamentos, 'equipamento', 'equipamentos'),
      if (atendimentos > 0)
        _plural(atendimentos, 'atendimento', 'atendimentos'),
    ];
    final unico = partes.length == 1 && equipamentos + atendimentos == 1;
    throw StateError(
      'Não é possível excluir: ${partes.join(' e ')} ainda '
      '${unico ? 'depende' : 'dependem'} deste $tipo, inclusive arquivados. '
      'Exclua-os primeiro.',
    );
  }

  @override
  Future<void> restoreCustomer(String id) =>
      _mutate(() => _restoreCustomer(id));

  Future<void> _restoreCustomer(String id) async {
    await _ensureHydrated();
    await _latency();
    final index = _customers.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Cliente não encontrado.');
    final atual = _customers[index];
    _customers[index] = CustomerOption(
      id: atual.id,
      name: atual.name,
      taxId: atual.taxId,
      contactName: atual.contactName,
      email: atual.email,
      phone: atual.phone,
      addressLine: atual.addressLine,
      city: atual.city,
      state: atual.state,
      notes: atual.notes,
    );
    await _journal(
      entityType: 'customer',
      entityId: id,
      operation: 'restore',
      payload: {'id': id},
    );
  }

  @override
  Future<void> restoreEquipment(String id) =>
      _mutate(() => _restoreEquipment(id));

  Future<void> _restoreEquipment(String id) async {
    await _ensureHydrated();
    await _latency();
    final index = _equipment.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Equipamento não encontrado.');
    _equipment[index] = _withArchivedAt(_equipment[index], null);
    await _journal(
      entityType: 'equipment',
      entityId: id,
      operation: 'restore',
      payload: {'id': id},
    );
  }

  @override
  Future<void> restoreCase(String id) => _mutate(() => _restoreCase(id));

  Future<void> _restoreCase(String id) async {
    await _ensureHydrated();
    await _latency();
    final index = _cases.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Atendimento não encontrado.');
    _cases[index] = _cases[index].copyWith(unarchive: true);
    await _journal(
      entityType: 'service_case',
      entityId: id,
      operation: 'restore',
      payload: {'id': id},
    );
  }

  @override
  Future<ArchivedRecords> fetchArchived() => _mutex.run(_fetchArchived);

  Future<ArchivedRecords> _fetchArchived() async {
    await _ensureHydrated();
    return ArchivedRecords(
      customers: _customers.where((item) => item.isArchived).toList(),
      equipment: _equipment.where((item) => item.isArchived).toList(),
      cases: _cases
          .where((item) => item.isArchived)
          .map(
            (item) => ServiceCaseSummary(
              id: item.id,
              caseNumber: item.caseNumber,
              equipmentId: item.equipmentId,
              equipmentLabel: item.equipmentLabel,
              reportedFailure: item.reportedFailure,
              openedAt: item.openedAt,
              archivedAt: item.archivedAt,
            ),
          )
          .toList(),
    );
  }

  static DateTime? _parseIso(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static Equipment _withArchivedAt(Equipment item, DateTime? value) =>
      Equipment(
        id: item.id,
        modelId: item.modelId,
        manufacturer: item.manufacturer,
        family: item.family,
        model: item.model,
        modality: item.modality,
        serialNumber: item.serialNumber,
        customer: item.customer,
        site: item.site,
        status: item.status,
        siteId: item.siteId,
        softwareVersion: item.softwareVersion,
        hardwareVersion: item.hardwareVersion,
        notes: item.notes,
        archivedAt: value,
      );

  @override
  Future<void> saveCase(ServiceCaseDraft draft) =>
      _mutate(() => _saveCase(draft));

  Future<void> _saveCase(ServiceCaseDraft draft) async {
    await _ensureHydrated();
    await _latency();
    final equipment = _equipment.firstWhere(
      (item) => item.id == draft.equipmentId,
    );
    final existingIndex = draft.id == null
        ? -1
        : _cases.indexWhere((item) => item.id == draft.id);
    final existing = existingIndex >= 0 ? _cases[existingIndex] : null;
    final resolved = draft.status == 'resolved';

    if (resolved && draft.progressEntries.any((entry) => entry.isOpen)) {
      throw StateError(
        'Encerre a sessão de trabalho em aberto no diário antes de concluir o atendimento.',
      );
    }

    // A data informada no rascunho prevalece: ao carregar histórico
    // antigo, a data do registro não é a data do atendimento. Sem ela,
    // preserva-se a que já estava gravada.
    final openedAt = draft.openedAt ?? existing?.openedAt ?? DateTime.now();

    // Só recorre ao relógio quando o atendimento está sendo concluído
    // agora e não havia conclusão anterior. Antes, qualquer gravação de
    // um atendimento resolvido reescrevia a conclusão para o instante
    // atual, movendo a data de chamados antigos a cada edição.
    final closedAt = !resolved
        ? null
        : (draft.closedAt ?? existing?.closedAt ?? DateTime.now());

    if (closedAt != null && closedAt.isBefore(openedAt)) {
      throw StateError(
        'A conclusão não pode ser anterior à abertura do chamado.',
      );
    }

    // Tempo técnico é somado das sessões do diário — aritmética pura, sem
    // constante de calibração, então pode ser calculado offline.
    final serviceMinutes = ServiceTimeMetrics.serviceMinutes(
      draft.progressEntries,
    );
    // A indisponibilidade depende dos pesos por impacto operacional, cuja
    // regra vive apenas no servidor (migration 0010). Preserva-se o último
    // valor recalculado por ele; num atendimento ainda não sincronizado
    // fica nulo, e a interface indica que será calculado na sincronização.
    final downtimeMinutes = existing?.downtimeMinutes;

    final item = ServiceCase(
      id: draft.id ?? _nextId('case'),
      caseNumber: existing?.caseNumber ?? _caseSequence++,
      equipmentId: equipment.id,
      // Sem série, a etiqueta não carrega o separador solto.
      equipmentLabel: [
        equipment.displayName,
        if (equipment.hasSerial) equipment.serialNumber,
      ].join(' · '),
      status: draft.status,
      activityType: draft.activityType,
      openedAt: openedAt,
      closedAt: closedAt,
      reportedFailure: draft.reportedFailure.trim(),
      observedSymptoms: _blankToNull(draft.observedSymptoms),
      errorCode: _blankToNull(draft.errorCode),
      errorMessage: _blankToNull(draft.errorMessage),
      subsystem: _blankToNull(draft.subsystem),
      operationalImpact: draft.operationalImpact,
      measurements: _blankToNull(draft.measurements),
      rootCause: _blankToNull(draft.rootCause),
      solutionDetails: _blankToNull(draft.solutionDetails),
      validationResult: _blankToNull(draft.validationResult),
      finalEquipmentStatus: resolved ? draft.finalEquipmentStatus : null,
      solutionConfidence: draft.solutionConfidence,
      progressEntries: List.unmodifiable(draft.progressEntries),
      downtimeMinutes: downtimeMinutes,
      serviceMinutes: serviceMinutes,
      requiresFollowUp: draft.requiresFollowUp,
      followUpNotes: _blankToNull(draft.followUpNotes),
      safetyNotes: _blankToNull(draft.safetyNotes),
    );

    if (existingIndex >= 0) {
      _cases[existingIndex] = item;
    } else {
      _cases.add(item);
    }
    await _journal(
      entityType: 'service_case',
      entityId: item.id,
      payload: _caseSyncPayload(item),
    );
  }

  @override
  Future<List<SimilarCaseResult>> searchSimilarCases(SimilarCaseQuery query) =>
      _mutex.run(() => _searchSimilarCases(query));

  Future<List<SimilarCaseResult>> _searchSimilarCases(
    SimilarCaseQuery query,
  ) async {
    await _ensureHydrated();
    await _latency();
    final queryTokens = _tokens(
      '${query.text} ${query.errorCode ?? ''} ${query.subsystem ?? ''}',
    );

    final results = <SimilarCaseResult>[];
    for (final serviceCase in _cases.where((item) => item.isResolved)) {
      final caseTokens = _tokens(
        [
          serviceCase.reportedFailure,
          serviceCase.observedSymptoms,
          serviceCase.errorCode,
          serviceCase.errorMessage,
          serviceCase.subsystem,
          serviceCase.measurements,
          serviceCase.rootCause,
          serviceCase.solutionDetails,
          serviceCase.validationResult,
          serviceCase.progressEntries
              .map((entry) => entry.description)
              .join(' '),
        ].whereType<String>().join(' '),
      );

      final intersection = queryTokens.intersection(caseTokens).length;
      final union = queryTokens.union(caseTokens).length;
      var score = union == 0 ? 0.0 : intersection / union * 2.4;
      final reasons = <String>[];

      if (query.errorCode?.trim().isNotEmpty == true &&
          serviceCase.errorCode?.toLowerCase() ==
              query.errorCode!.trim().toLowerCase()) {
        score += 0.30;
        reasons.add('Código de erro idêntico');
      }
      if (query.equipmentId?.isNotEmpty == true &&
          serviceCase.equipmentId == query.equipmentId) {
        score += 0.12;
        reasons.add('Mesmo equipamento');
      }
      if (query.subsystem?.trim().isNotEmpty == true &&
          serviceCase.subsystem?.toLowerCase() ==
              query.subsystem!.trim().toLowerCase()) {
        score += 0.10;
        reasons.add('Mesmo subsistema');
      }
      if ({
        'confirmed',
        'recurring',
        'reviewed',
      }.contains(serviceCase.solutionConfidence)) {
        score += 0.05;
        reasons.add('Solução validada');
      }
      if (intersection > 0) {
        reasons.add('$intersection termos técnicos em comum');
      }

      score = score.clamp(0.0, 0.99).toDouble();
      if (score >= 0.12) {
        results.add(
          SimilarCaseResult(
            serviceCase: serviceCase,
            score: score,
            reasons: reasons,
          ),
        );
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return List.unmodifiable(results.take(8));
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<SyncStatusSnapshot> fetchSyncStatus() async {
    final pendingOperations = _syncQueue == null
        ? const <SyncOperation>[]
        : await _syncQueue.pending();
    final lastSync = await _storage.readMetadata(
      _namespace,
      'last_successful_sync',
    );
    final lastError = await _storage.readMetadata(
      _namespace,
      'last_sync_error',
    );
    return SyncStatusSnapshot(
      pendingCount: pendingOperations.length,
      conflictCount: pendingOperations
          .where(
            (item) => item.lastError?.startsWith(conflictErrorPrefix) == true,
          )
          .length,
      storageLabel: _storage.storageLabel,
      lastSuccessfulSync: lastSync == null ? null : DateTime.tryParse(lastSync),
      lastError: lastError,
    );
  }

  @override
  Future<void> syncPendingChanges() async {
    // O replay remoto será ativado no próximo marco da versão 0.4.
  }

  @override
  Future<List<SyncConflict>> fetchConflicts() => _mutex.run(() async {
    final queue = _syncQueue;
    if (queue == null) return const <SyncConflict>[];
    await _ensureHydrated();
    final conflicts = <SyncConflict>[];
    for (final operation in await queue.pending()) {
      final conflict = SyncConflict.fromOperation(
        operation,
        recordLabel: describeEntity(operation.entityType, operation.entityId),
      );
      if (conflict != null) conflicts.add(conflict);
    }
    return List.unmodifiable(conflicts);
  });

  @override
  Future<void> resolveConflict(
    String operationId,
    ConflictResolution resolution,
  ) => _mutex.run(() async {
    switch (resolution) {
      case ConflictResolution.discardLocal:
        // A alteração local some da fila. O espelho ainda mostra o valor
        // recusado até o próximo download — que só é aplicado quando a
        // fila esvazia, e por isso é ele que devolve a versão do servidor.
        await _storage.removeOperation(operationId);
      case ConflictResolution.keepLocal:
        // Base zero desliga a verificação de revisão no servidor, que
        // passa a aceitar a gravação por cima. É o mesmo caminho de um
        // registro novo, cuja revisão de origem também é desconhecida.
        await _storage.rebaseOperation(operationId, baseRevision: 0);
    }
  });

  Future<void> _journal({
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    String operation = 'upsert',
  }) async {
    final queue = _syncQueue;
    if (queue == null) return;
    // Estrutura transacional da entrega do outbox, preservando o
    // parâmetro `operation`: arquivamento e restauração não são upsert,
    // e fixá-los aqui faria a fila enviar a operação errada.
    _stagedOperations.add(
      SyncOperation(
        id: _uuid.v4(),
        namespace: _namespace,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        createdAt: DateTime.now(),
        payload: {
          ...payload,
          '_base_revision': remoteRevision(entityType, entityId),
          '_client_updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    );
  }

  static Map<String, dynamic> _customerDraftPayload(
    String id,
    CustomerDraft draft,
  ) => {
    'id': id,
    'name': draft.name.trim(),
    'tax_id': _blankToNull(draft.taxId),
    'contact_name': _blankToNull(draft.contactName),
    'email': _blankToNull(draft.email),
    'phone': _blankToNull(draft.phone),
    'address_line': _blankToNull(draft.addressLine),
    'city': _blankToNull(draft.city),
    'state': _blankToNull(draft.state),
    'notes': _blankToNull(draft.notes),
  };

  static Map<String, dynamic> _siteDraftPayload(String id, SiteDraft draft) => {
    'id': id,
    'customer_id': draft.customerId,
    'name': draft.siteName.trim(),
    'city': _blankToNull(draft.city),
    'state': _blankToNull(draft.state),
    'notes': _blankToNull(draft.notes),
  };

  /// Ids dos locais de um cliente, inclusive quando o cliente está
  /// arquivado.
  ///
  /// `fetchEquipmentCatalog` esconde os locais de clientes arquivados, o
  /// que é certo para as listagens e errado para a exclusão definitiva:
  /// ali o cliente é sempre arquivado, e é por esses locais que se chega
  /// aos equipamentos que impediriam a exclusão.
  Future<Set<String>> siteIdsOfCustomer(String customerId) =>
      _mutex.run(() async {
        await _ensureHydrated();
        return _sites
            .where((item) => item.customerId == customerId)
            .map((item) => item.id)
            .toSet();
      });

  /// Descrição legível de um registro do espelho local, para a tela de
  /// conflitos. O payload da operação não serve: arquivar e restaurar
  /// enfileiram apenas o id, e um conflito precisa dizer sobre o que é.
  ///
  /// Registros já removidos do espelho caem no rótulo genérico — não é um
  /// erro, apenas o que sobra quando o download já apagou a linha local.
  String describeEntity(String entityType, String entityId) {
    switch (entityType) {
      case 'customer':
        for (final item in _customers) {
          if (item.id == entityId) return item.name;
        }
      case 'site':
        for (final item in _sites) {
          if (item.id == entityId) return '${item.customer} · ${item.site}';
        }
      case 'equipment_model':
        for (final item in _models) {
          if (item.id == entityId) return item.label;
        }
      case 'equipment':
        for (final item in _equipment) {
          if (item.id == entityId) {
            return '${item.displayName} · ${item.serialLabel}';
          }
        }
      case 'service_case':
        for (final item in _cases) {
          if (item.id == entityId) {
            return 'Chamado ${item.caseNumber} · ${item.reportedFailure}';
          }
        }
    }
    return 'Registro $entityId';
  }

  int remoteRevision(String entityType, String entityId) =>
      _remoteRevisions['$entityType:$entityId'] ?? 0;

  Future<void> acknowledge(SyncOperation operation, int revision) => _mutate(
    () async {
      _remoteRevisions['${operation.entityType}:${operation.entityId}'] =
          revision;
    },
    completed: operation,
    revision: revision,
  );

  /// Confirmação de uma exclusão definitiva.
  ///
  /// Não há revisão a guardar: a linha deixou de existir, e manter a
  /// entrada de revisão faria uma futura gravação com o mesmo id partir de
  /// uma base que o servidor não reconhece mais.
  Future<void> acknowledgePurge(SyncOperation operation) => _mutate(
    () async {
      _remoteRevisions.remove('${operation.entityType}:${operation.entityId}');
    },
    completed: operation,
    revision: 0,
  );

  Future<void> replaceFromRemote({
    required List<Equipment> equipment,
    required List<ServiceCase> cases,
    required EquipmentCatalog catalog,
    required Map<String, int> revisions,
  }) => _mutate(() async {
    // A downloaded snapshot is stale with respect to edits made during I/O.
    // Keep the complete local view until the pending writes have been replayed.
    if (await _storage.pendingCount(_namespace) > 0) return;
    _models
      ..clear()
      ..addAll(catalog.models);
    _customers
      ..clear()
      ..addAll(catalog.customers);
    _sites
      ..clear()
      ..addAll(catalog.sites);
    _equipment
      ..clear()
      ..addAll(equipment);
    _cases
      ..clear()
      ..addAll(cases);
    _remoteRevisions
      ..clear()
      ..addAll(revisions);
    final greatestCaseNumber = _cases.fold<int>(
      0,
      (current, item) => item.caseNumber > current ? item.caseNumber : current,
    );
    _caseSequence = greatestCaseNumber + 1;
  });

  static Map<String, dynamic> _caseSyncPayload(ServiceCase item) => {
    'id': item.id,
    'equipment_id': item.equipmentId,
    'status': item.status,
    'activity_type': item.activityType,
    'opened_at': item.openedAt.toUtc().toIso8601String(),
    'closed_at': item.closedAt?.toUtc().toIso8601String(),
    'reported_failure': item.reportedFailure,
    'observed_symptoms': item.observedSymptoms,
    'error_code': item.errorCode,
    'error_message': item.errorMessage,
    'subsystem': item.subsystem,
    'operational_impact': item.operationalImpact,
    'measurements': item.measurements,
    'root_cause': item.rootCause,
    'solution_details': item.solutionDetails,
    'validation_result': item.validationResult,
    'final_equipment_status': item.finalEquipmentStatus,
    'solution_confidence': item.solutionConfidence,
    'downtime_minutes': item.downtimeMinutes,
    'service_minutes': item.serviceMinutes,
    'requires_follow_up': item.requiresFollowUp,
    'follow_up_notes': item.followUpNotes,
    'safety_notes': item.safetyNotes,
    'progress_entries': item.progressEntries
        .map(
          (entry) => {
            'id': entry.id,
            'occurred_at': entry.occurredAt.toUtc().toIso8601String(),
            'ended_at': entry.endedAt?.toUtc().toIso8601String(),
            'description': entry.description,
          },
        )
        .toList(growable: false),
  };

  Future<void> _ensureHydrated() {
    return _hydrationFuture ??= _hydrate();
  }

  Future<void> _hydrate() async {
    final stored = await _storage.readSnapshot(_namespace);
    if (stored == null || stored.isEmpty) {
      await _persist();
      return;
    }

    _restoreSnapshot(stored);
  }

  void _restoreSnapshot(String stored) {
    final root = jsonDecode(stored) as Map<String, dynamic>;
    _models
      ..clear()
      ..addAll(
        _list(root['models']).map(
          (item) => EquipmentModelOption(
            id: item['id'] as String,
            manufacturer: item['manufacturer'] as String? ?? '',
            family: item['family'] as String? ?? '',
            model: item['model'] as String? ?? '',
            modality: item['modality'] as String? ?? '',
          ),
        ),
      );
    _customers
      ..clear()
      ..addAll(
        _list(root['customers']).map(
          (item) => CustomerOption(
            id: item['id'] as String,
            name: item['name'] as String? ?? '',
            taxId: item['taxId'] as String?,
            contactName: item['contactName'] as String?,
            email: item['email'] as String?,
            phone: item['phone'] as String?,
            addressLine: item['addressLine'] as String?,
            city: item['city'] as String?,
            state: item['state'] as String?,
            notes: item['notes'] as String?,
            archivedAt: _parseIso(item['archivedAt']),
          ),
        ),
      );
    _sites
      ..clear()
      ..addAll(
        _list(root['sites']).map(
          (item) => SiteOption(
            id: item['id'] as String,
            customerId: item['customerId'] as String? ?? '',
            customer: item['customer'] as String? ?? '',
            site: item['site'] as String? ?? '',
            city: item['city'] as String?,
            state: item['state'] as String?,
            notes: item['notes'] as String?,
          ),
        ),
      );
    _equipment
      ..clear()
      ..addAll(
        _list(root['equipment']).map(
          (item) => Equipment(
            id: item['id'] as String,
            modelId: item['modelId'] as String? ?? '',
            manufacturer: item['manufacturer'] as String? ?? '',
            family: item['family'] as String? ?? '',
            model: item['model'] as String? ?? '',
            modality: item['modality'] as String? ?? '',
            serialNumber: item['serialNumber'] as String? ?? '',
            customer: item['customer'] as String? ?? '',
            site: item['site'] as String? ?? '',
            status: item['status'] as String? ?? 'operational',
            siteId: item['siteId'] as String?,
            softwareVersion: item['softwareVersion'] as String?,
            hardwareVersion: item['hardwareVersion'] as String?,
            notes: item['notes'] as String?,
            archivedAt: _parseIso(item['archivedAt']),
          ),
        ),
      );
    _cases
      ..clear()
      ..addAll(_list(root['cases']).map(_caseFromJson));
    _equipmentSequence = (root['equipmentSequence'] as num?)?.toInt() ?? 10;
    _caseSequence = (root['caseSequence'] as num?)?.toInt() ?? 105;
    _catalogSequence = (root['catalogSequence'] as num?)?.toInt() ?? 100;
    _remoteRevisions
      ..clear()
      ..addAll(
        Map<String, dynamic>.from(
          root['remoteRevisions'] as Map? ?? const <String, dynamic>{},
        ).map((key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0)),
      );
  }

  Future<T> _mutate<T>(
    Future<T> Function() action, {
    SyncOperation? completed,
    int? revision,
  }) => _mutex.run(() async {
    await _ensureHydrated();
    final before = _encodeSnapshot();
    _stagedOperations.clear();
    try {
      final result = await action();
      await _storage.commitMutation(
        namespace: _namespace,
        snapshot: _encodeSnapshot(),
        operations: _stagedOperations,
        completed: completed,
        revision: revision,
      );
      return result;
    } catch (_) {
      _restoreSnapshot(before);
      rethrow;
    } finally {
      _stagedOperations.clear();
    }
  });

  Future<void> _persist() =>
      _storage.writeSnapshot(_namespace, _encodeSnapshot());

  String _encodeSnapshot() => jsonEncode({
    'models': _models
        .map(
          (item) => {
            'id': item.id,
            'manufacturer': item.manufacturer,
            'family': item.family,
            'model': item.model,
            'modality': item.modality,
          },
        )
        .toList(),
    'customers': _customers
        .map(
          (item) => {
            'id': item.id,
            'name': item.name,
            'taxId': item.taxId,
            'contactName': item.contactName,
            'email': item.email,
            'phone': item.phone,
            'addressLine': item.addressLine,
            'city': item.city,
            'state': item.state,
            'notes': item.notes,
            'archivedAt': item.archivedAt?.toIso8601String(),
          },
        )
        .toList(),
    'sites': _sites
        .map(
          (item) => {
            'id': item.id,
            'customerId': item.customerId,
            'customer': item.customer,
            'site': item.site,
            'city': item.city,
            'state': item.state,
            'notes': item.notes,
          },
        )
        .toList(),
    'equipment': _equipment
        .map(
          (item) => {
            'id': item.id,
            'modelId': item.modelId,
            'manufacturer': item.manufacturer,
            'family': item.family,
            'model': item.model,
            'modality': item.modality,
            'serialNumber': item.serialNumber,
            'customer': item.customer,
            'site': item.site,
            'siteId': item.siteId,
            'softwareVersion': item.softwareVersion,
            'hardwareVersion': item.hardwareVersion,
            'status': item.status,
            'notes': item.notes,
            'archivedAt': item.archivedAt?.toIso8601String(),
          },
        )
        .toList(),
    'cases': _cases.map(_caseToJson).toList(),
    'equipmentSequence': _equipmentSequence,
    'caseSequence': _caseSequence,
    'catalogSequence': _catalogSequence,
    'remoteRevisions': _remoteRevisions,
  });

  String _nextId(String prefix) {
    if (_useUuidIds) return _uuid.v4();
    final value = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-demo-$value-${_catalogSequence++}';
  }

  static Map<String, dynamic> _caseToJson(ServiceCase item) => {
    'id': item.id,
    'caseNumber': item.caseNumber,
    'equipmentId': item.equipmentId,
    'equipmentLabel': item.equipmentLabel,
    'status': item.status,
    'activityType': item.activityType,
    'progressEntries': item.progressEntries
        .map(
          (entry) => {
            'id': entry.id,
            'occurredAt': entry.occurredAt.toIso8601String(),
            'endedAt': entry.endedAt?.toIso8601String(),
            'description': entry.description,
          },
        )
        .toList(),
    'openedAt': item.openedAt.toIso8601String(),
    'closedAt': item.closedAt?.toIso8601String(),
    'reportedFailure': item.reportedFailure,
    'operationalImpact': item.operationalImpact,
    'solutionConfidence': item.solutionConfidence,
    'observedSymptoms': item.observedSymptoms,
    'errorCode': item.errorCode,
    'errorMessage': item.errorMessage,
    'subsystem': item.subsystem,
    'measurements': item.measurements,
    'rootCause': item.rootCause,
    'solutionDetails': item.solutionDetails,
    'validationResult': item.validationResult,
    'finalEquipmentStatus': item.finalEquipmentStatus,
    'downtimeMinutes': item.downtimeMinutes,
    'serviceMinutes': item.serviceMinutes,
    'requiresFollowUp': item.requiresFollowUp,
    'followUpNotes': item.followUpNotes,
    'safetyNotes': item.safetyNotes,
    'archivedAt': item.archivedAt?.toIso8601String(),
  };

  static ServiceCase _caseFromJson(Map<String, dynamic> item) => ServiceCase(
    id: item['id'] as String,
    caseNumber: (item['caseNumber'] as num?)?.toInt() ?? 0,
    equipmentId: item['equipmentId'] as String? ?? '',
    equipmentLabel: item['equipmentLabel'] as String? ?? '',
    status: item['status'] as String? ?? 'open',
    activityType:
        item['activityType'] as String? ?? ServiceActivityType.maintenance,
    progressEntries: _list(item['progressEntries'])
        .map(
          (entry) => ServiceProgressEntry(
            id: entry['id'] as String? ?? '',
            occurredAt:
                DateTime.tryParse(entry['occurredAt'] as String? ?? '') ??
                DateTime.now(),
            endedAt: entry['endedAt'] == null
                ? null
                : DateTime.tryParse(entry['endedAt'] as String),
            description: entry['description'] as String? ?? '',
          ),
        )
        .toList(),
    openedAt:
        DateTime.tryParse(item['openedAt'] as String? ?? '') ?? DateTime.now(),
    closedAt: DateTime.tryParse(item['closedAt'] as String? ?? ''),
    reportedFailure: item['reportedFailure'] as String? ?? '',
    operationalImpact: item['operationalImpact'] as String? ?? 'degraded',
    solutionConfidence: item['solutionConfidence'] as String? ?? 'unconfirmed',
    observedSymptoms: item['observedSymptoms'] as String?,
    errorCode: item['errorCode'] as String?,
    errorMessage: item['errorMessage'] as String?,
    subsystem: item['subsystem'] as String?,
    measurements: item['measurements'] as String?,
    rootCause: item['rootCause'] as String?,
    solutionDetails: item['solutionDetails'] as String?,
    validationResult: item['validationResult'] as String?,
    finalEquipmentStatus: item['finalEquipmentStatus'] as String?,
    downtimeMinutes: (item['downtimeMinutes'] as num?)?.toInt(),
    serviceMinutes: (item['serviceMinutes'] as num?)?.toInt(),
    requiresFollowUp: item['requiresFollowUp'] as bool? ?? false,
    followUpNotes: item['followUpNotes'] as String?,
    safetyNotes: item['safetyNotes'] as String?,
    archivedAt: _parseIso(item['archivedAt']),
  );

  static List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _latency() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  static String _fallback(String? value, String fallback) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? fallback : cleaned;
  }

  static String? _blankToNull(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  static Set<String> _tokens(String value) {
    const ignored = {
      'a',
      'ao',
      'as',
      'com',
      'da',
      'das',
      'de',
      'do',
      'dos',
      'e',
      'em',
      'na',
      'nas',
      'no',
      'nos',
      'o',
      'os',
      'para',
      'por',
      'um',
      'uma',
    };
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áàâãéêíóôõúç_-]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length > 2 && !ignored.contains(token))
        .toSet();
  }
}
