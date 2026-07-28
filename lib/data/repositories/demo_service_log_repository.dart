import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/equipment.dart';
import '../models/service_case.dart';
import 'service_log_repository.dart';

class DemoServiceLogRepository implements ServiceLogRepository {
  DemoServiceLogRepository._({
    required List<Equipment> equipment,
    required List<ServiceCase> cases,
    required List<EquipmentModelOption> models,
    required List<CustomerOption> customers,
    required List<SiteOption> sites,
  })  : _equipment = equipment,
        _cases = cases,
        _models = models,
        _customers = customers,
        _sites = sites;

  factory DemoServiceLogRepository.seeded() {
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
    );
  }

  static const _storageKey = 'orion_servicelog_demo_v3';

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
  bool get isDemo => true;

  @override
  Future<List<Equipment>> fetchEquipments() async {
    await _ensureHydrated();
    await _latency();
    return List.unmodifiable(_equipment);
  }

  @override
  Future<List<ServiceCase>> fetchCases() async {
    await _ensureHydrated();
    await _latency();
    final result = [..._cases]
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return List.unmodifiable(result);
  }

  @override
  Future<EquipmentCatalog> fetchEquipmentCatalog() async {
    await _ensureHydrated();
    await _latency();
    return EquipmentCatalog(
      models: List.unmodifiable(_models),
      customers: List.unmodifiable(_customers),
      sites: List.unmodifiable(_sites),
    );
  }

  @override
  Future<String> createEquipmentModel(EquipmentModelDraft draft) async {
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
    await _persist();
    return id;
  }

  @override
  Future<String> createCustomer(CustomerDraft draft) async {
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
    await _persist();
    return id;
  }

  @override
  Future<void> updateCustomer(String id, CustomerDraft draft) async {
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

    await _persist();
  }

  @override
  Future<String> createSite(SiteDraft draft) async {
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
    await _persist();
    return id;
  }

  @override
  Future<void> updateSite(String id, SiteDraft draft) async {
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

    await _persist();
  }

  @override
  Future<String> createCustomerSite(CustomerSiteDraft draft) async {
    final customerId = await createCustomer(
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
    return createSite(
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
  Future<void> createEquipment(EquipmentDraft draft) async {
    await _ensureHydrated();
    await _latency();
    final model = _models.firstWhere((item) => item.id == draft.modelId);
    final matchingSites = _sites.where((item) => item.id == draft.siteId);
    final site = matchingSites.isEmpty ? null : matchingSites.first;
    _equipment.add(
      Equipment(
        id: _nextId('eq'),
        modelId: model.id,
        manufacturer: model.manufacturer,
        family: model.family,
        model: model.model,
        modality: model.modality,
        serialNumber: draft.serialNumber.trim(),
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
    await _persist();
  }

  @override
  Future<void> saveCase(ServiceCaseDraft draft) async {
    await _ensureHydrated();
    await _latency();
    final equipment =
        _equipment.firstWhere((item) => item.id == draft.equipmentId);
    final existingIndex = draft.id == null
        ? -1
        : _cases.indexWhere((item) => item.id == draft.id);
    final existing = existingIndex >= 0 ? _cases[existingIndex] : null;
    final resolved = draft.status == 'resolved';

    final item = ServiceCase(
      id: draft.id ?? _nextId('case'),
      caseNumber: existing?.caseNumber ?? _caseSequence++,
      equipmentId: equipment.id,
      equipmentLabel: '${equipment.displayName} · ${equipment.serialNumber}',
      status: draft.status,
      activityType: draft.activityType,
      openedAt: existing?.openedAt ?? DateTime.now(),
      closedAt: resolved ? DateTime.now() : null,
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
      downtimeMinutes: draft.downtimeMinutes,
      serviceMinutes: draft.serviceMinutes,
      requiresFollowUp: draft.requiresFollowUp,
      followUpNotes: _blankToNull(draft.followUpNotes),
      safetyNotes: _blankToNull(draft.safetyNotes),
    );

    if (existingIndex >= 0) {
      _cases[existingIndex] = item;
    } else {
      _cases.add(item);
    }
    await _persist();
  }

  @override
  Future<List<SimilarCaseResult>> searchSimilarCases(
    SimilarCaseQuery query,
  ) async {
    await _ensureHydrated();
    await _latency();
    final queryTokens = _tokens(
      '${query.text} ${query.errorCode ?? ''} ${query.subsystem ?? ''}',
    );

    final results = <SimilarCaseResult>[];
    for (final serviceCase in _cases.where((item) => item.isResolved)) {
      final caseTokens = _tokens([
        serviceCase.reportedFailure,
        serviceCase.observedSymptoms,
        serviceCase.errorCode,
        serviceCase.errorMessage,
        serviceCase.subsystem,
        serviceCase.measurements,
        serviceCase.rootCause,
        serviceCase.solutionDetails,
        serviceCase.validationResult,
        serviceCase.progressEntries.map((entry) => entry.description).join(' '),
      ].whereType<String>().join(' '));

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
      if ({'confirmed', 'recurring', 'reviewed'}
          .contains(serviceCase.solutionConfidence)) {
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

  Future<void> _ensureHydrated() {
    return _hydrationFuture ??= _hydrate();
  }

  Future<void> _hydrate() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_storageKey);
    if (stored == null || stored.isEmpty) {
      await _persist();
      return;
    }

    try {
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
            ),
          ),
        );
      _cases
        ..clear()
        ..addAll(
          _list(root['cases']).map(_caseFromJson),
        );
      _equipmentSequence = (root['equipmentSequence'] as num?)?.toInt() ?? 10;
      _caseSequence = (root['caseSequence'] as num?)?.toInt() ?? 105;
      _catalogSequence = (root['catalogSequence'] as num?)?.toInt() ?? 100;
    } catch (_) {
      await preferences.remove(_storageKey);
      await _persist();
    }
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode({
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
              },
            )
            .toList(),
        'cases': _cases.map(_caseToJson).toList(),
        'equipmentSequence': _equipmentSequence,
        'caseSequence': _caseSequence,
        'catalogSequence': _catalogSequence,
      }),
    );
  }

  String _nextId(String prefix) {
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
                occurredAt: DateTime.tryParse(
                      entry['occurredAt'] as String? ?? '',
                    ) ??
                    DateTime.now(),
                description: entry['description'] as String? ?? '',
              ),
            )
            .toList(),
        openedAt: DateTime.tryParse(item['openedAt'] as String? ?? '') ??
            DateTime.now(),
        closedAt: DateTime.tryParse(item['closedAt'] as String? ?? ''),
        reportedFailure: item['reportedFailure'] as String? ?? '',
        operationalImpact: item['operationalImpact'] as String? ?? 'degraded',
        solutionConfidence:
            item['solutionConfidence'] as String? ?? 'unconfirmed',
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
