import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/equipment.dart';
import '../models/service_case.dart';
import 'service_log_repository.dart';

class SupabaseServiceLogRepository implements ServiceLogRepository {
  SupabaseServiceLogRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  bool get isDemo => false;

  @override
  Future<List<Equipment>> fetchEquipments() async {
    final response = await _client
        .from('equipments')
        .select('''
      id,
      equipment_model_id,
      site_id,
      serial_number,
      software_version,
      hardware_version,
      status,
      notes,
      equipment_models(
        id,
        family,
        model,
        modality,
        manufacturers(name)
      ),
      sites(
        id,
        name,
        customers(name)
      )
    ''')
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => Equipment.fromSupabase(_map(row)))
        .toList(growable: false);
  }

  @override
  Future<List<ServiceCase>> fetchCases() async {
    final response = await _client
        .from('service_cases')
        .select('''
      id,
      case_number,
      equipment_id,
      status,
      activity_type,
      opened_at,
      closed_at,
      reported_failure,
      observed_symptoms,
      error_code,
      error_message,
      subsystem,
      operational_impact,
      measurements,
      root_cause,
      solution_details,
      validation_result,
      final_equipment_status,
      solution_confidence,
      downtime_minutes,
      service_minutes,
      requires_follow_up,
      follow_up_notes,
      safety_notes,
      service_progress_entries(
        id,
        occurred_at,
        ended_at,
        description
      ),
      equipments(
        serial_number,
        equipment_models(
          model,
          manufacturers(name)
        )
      )
    ''')
        .isFilter('deleted_at', null)
        .order('opened_at', ascending: false)
        .limit(300);

    return (response as List)
        .map((row) => ServiceCase.fromSupabase(_map(row)))
        .toList(growable: false);
  }

  @override
  Future<EquipmentCatalog> fetchEquipmentCatalog() async {
    final responses = await Future.wait<dynamic>([
      _client
          .from('equipment_models')
          .select('''
        id,
        family,
        model,
        modality,
        manufacturers(name)
      ''')
          .isFilter('deleted_at', null)
          .order('model'),
      _client
          .from('customers')
          .select('''
        id,
        name,
        tax_id,
        contact_name,
        email,
        phone,
        address_line,
        city,
        state,
        notes
      ''')
          .isFilter('deleted_at', null)
          .order('name'),
      _client
          .from('sites')
          .select('''
        id,
        customer_id,
        name,
        city,
        state,
        notes,
        customers(name)
      ''')
          .isFilter('deleted_at', null)
          .order('name'),
    ]);

    final models = (responses[0] as List)
        .map((row) {
          final json = _map(row);
          final manufacturer = _firstMap(json['manufacturers']);
          return EquipmentModelOption(
            id: json['id'] as String,
            manufacturer: manufacturer['name'] as String? ?? '',
            family: json['family'] as String? ?? '',
            model: json['model'] as String? ?? '',
            modality: json['modality'] as String? ?? '',
          );
        })
        .toList(growable: false);

    final customers = (responses[1] as List)
        .map((row) {
          final json = _map(row);
          return CustomerOption(
            id: json['id'] as String,
            name: json['name'] as String? ?? '',
            taxId: json['tax_id'] as String?,
            contactName: json['contact_name'] as String?,
            email: json['email'] as String?,
            phone: json['phone'] as String?,
            addressLine: json['address_line'] as String?,
            city: json['city'] as String?,
            state: json['state'] as String?,
            notes: json['notes'] as String?,
          );
        })
        .toList(growable: false);

    final sites = (responses[2] as List)
        .map((row) {
          final json = _map(row);
          final customer = _firstMap(json['customers']);
          return SiteOption(
            id: json['id'] as String,
            customerId: json['customer_id'] as String? ?? '',
            customer: customer['name'] as String? ?? '',
            site: json['name'] as String? ?? '',
            city: json['city'] as String?,
            state: json['state'] as String?,
            notes: json['notes'] as String?,
          );
        })
        .toList(growable: false);

    return EquipmentCatalog(models: models, customers: customers, sites: sites);
  }

  @override
  Future<String> createEquipmentModel(EquipmentModelDraft draft) async {
    final organizationId = await _organizationId();
    final manufacturerName = draft.manufacturer.trim();
    final modelName = draft.model.trim();

    final manufacturerRows = await _client
        .from('manufacturers')
        .select('id, name');
    final manufacturers = (manufacturerRows as List).map(_map).toList();
    final manufacturerMatch = manufacturers.where(
      (item) =>
          (item['name'] as String? ?? '').toLowerCase() ==
          manufacturerName.toLowerCase(),
    );

    late final String manufacturerId;
    if (manufacturerMatch.isNotEmpty) {
      manufacturerId = manufacturerMatch.first['id'] as String;
    } else {
      final created = await _client
          .from('manufacturers')
          .insert({'organization_id': organizationId, 'name': manufacturerName})
          .select('id')
          .single();
      manufacturerId = created['id'] as String;
    }

    final modelRows = await _client
        .from('equipment_models')
        .select('id, model')
        .eq('manufacturer_id', manufacturerId);
    final modelMatch = (modelRows as List)
        .map(_map)
        .where(
          (item) =>
              (item['model'] as String? ?? '').toLowerCase() ==
              modelName.toLowerCase(),
        );
    if (modelMatch.isNotEmpty) return modelMatch.first['id'] as String;

    final created = await _client
        .from('equipment_models')
        .insert({
          'organization_id': organizationId,
          'manufacturer_id': manufacturerId,
          'family': _blankToNull(draft.family),
          'model': modelName,
          'modality': _fallback(draft.modality, 'Não informada'),
          'description': _blankToNull(draft.description),
        })
        .select('id')
        .single();
    return created['id'] as String;
  }

  @override
  Future<String> createCustomer(CustomerDraft draft) async {
    final organizationId = await _organizationId();
    final name = draft.name.trim();
    final rows = await _client.from('customers').select('id, name');
    final match = (rows as List)
        .map(_map)
        .where(
          (item) =>
              (item['name'] as String? ?? '').toLowerCase() ==
              name.toLowerCase(),
        );
    if (match.isNotEmpty) return match.first['id'] as String;

    final created = await _client
        .from('customers')
        .insert({
          'organization_id': organizationId,
          'name': name,
          'tax_id': _blankToNull(draft.taxId),
          'contact_name': _blankToNull(draft.contactName),
          'email': _blankToNull(draft.email),
          'phone': _blankToNull(draft.phone),
          'address_line': _blankToNull(draft.addressLine),
          'city': _blankToNull(draft.city),
          'state': _blankToNull(draft.state),
          'notes': _blankToNull(draft.notes),
        })
        .select('id')
        .single();
    return created['id'] as String;
  }

  @override
  Future<void> updateCustomer(String id, CustomerDraft draft) async {
    await _client
        .from('customers')
        .update({
          'name': draft.name.trim(),
          'tax_id': _blankToNull(draft.taxId),
          'contact_name': _blankToNull(draft.contactName),
          'email': _blankToNull(draft.email),
          'phone': _blankToNull(draft.phone),
          'address_line': _blankToNull(draft.addressLine),
          'city': _blankToNull(draft.city),
          'state': _blankToNull(draft.state),
          'notes': _blankToNull(draft.notes),
        })
        .eq('id', id);
  }

  @override
  Future<String> createSite(SiteDraft draft) async {
    final organizationId = await _organizationId();
    final siteName = draft.siteName.trim();
    final rows = await _client
        .from('sites')
        .select('id, name')
        .eq('customer_id', draft.customerId);
    final match = (rows as List)
        .map(_map)
        .where(
          (item) =>
              (item['name'] as String? ?? '').toLowerCase() ==
              siteName.toLowerCase(),
        );
    if (match.isNotEmpty) return match.first['id'] as String;

    final created = await _client
        .from('sites')
        .insert({
          'organization_id': organizationId,
          'customer_id': draft.customerId,
          'name': siteName,
          'city': _blankToNull(draft.city),
          'state': _blankToNull(draft.state),
          'notes': _blankToNull(draft.notes),
        })
        .select('id')
        .single();
    return created['id'] as String;
  }

  @override
  Future<void> updateSite(String id, SiteDraft draft) async {
    await _client
        .from('sites')
        .update({
          'customer_id': draft.customerId,
          'name': draft.siteName.trim(),
          'city': _blankToNull(draft.city),
          'state': _blankToNull(draft.state),
          'notes': _blankToNull(draft.notes),
        })
        .eq('id', id);
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
    final organizationId = await _organizationId();
    await _client.from('equipments').insert({
      'organization_id': organizationId,
      'equipment_model_id': draft.modelId,
      'site_id': _blankToNull(draft.siteId),
      'serial_number': draft.serialNumber.trim(),
      'software_version': _blankToNull(draft.softwareVersion),
      'hardware_version': _blankToNull(draft.hardwareVersion),
      'status': draft.status,
      'notes': _blankToNull(draft.notes),
      'created_by': _client.auth.currentUser?.id,
    });
  }

  @override
  Future<void> updateEquipment(String id, EquipmentDraft draft) async {
    await _client
        .from('equipments')
        .update({
          'equipment_model_id': draft.modelId,
          'site_id': draft.siteId,
          'serial_number': draft.serialNumber.trim(),
          'software_version': _blankToNull(draft.softwareVersion),
          'hardware_version': _blankToNull(draft.hardwareVersion),
          'status': draft.status,
          'notes': _blankToNull(draft.notes),
        })
        .eq('id', id);
  }

  @override
  Future<void> saveCase(ServiceCaseDraft draft) async {
    final organizationId = await _organizationId();
    final resolved = draft.status == 'resolved';
    final payload = <String, dynamic>{
      'organization_id': organizationId,
      'equipment_id': draft.equipmentId,
      'status': draft.status,
      'activity_type': draft.activityType,
      'reported_failure': draft.reportedFailure.trim(),
      'observed_symptoms': _blankToNull(draft.observedSymptoms),
      'error_code': _blankToNull(draft.errorCode),
      'error_message': _blankToNull(draft.errorMessage),
      'subsystem': _blankToNull(draft.subsystem),
      'operational_impact': draft.operationalImpact,
      'measurements': _blankToNull(draft.measurements),
      'root_cause': _blankToNull(draft.rootCause),
      'solution_details': _blankToNull(draft.solutionDetails),
      'validation_result': _blankToNull(draft.validationResult),
      'final_equipment_status': resolved ? draft.finalEquipmentStatus : null,
      'solution_confidence': draft.solutionConfidence,
      // downtime_minutes e service_minutes não são enviados: são derivados
      // no servidor a partir das sessões do diário e do impacto operacional.
      'requires_follow_up': draft.requiresFollowUp,
      'follow_up_notes': _blankToNull(draft.followUpNotes),
      'safety_notes': _blankToNull(draft.safetyNotes),
      'closed_at': resolved ? DateTime.now().toIso8601String() : null,
    };

    late final String serviceCaseId;
    if (draft.id == null) {
      final created = await _client
          .from('service_cases')
          .insert(payload)
          .select('id')
          .single();
      serviceCaseId = created['id'] as String;
    } else {
      serviceCaseId = draft.id!;
      await _client
          .from('service_cases')
          .update(payload)
          .eq('id', serviceCaseId);
    }

    await _client
        .from('service_progress_entries')
        .delete()
        .eq('service_case_id', serviceCaseId);

    final progressPayload = draft.progressEntries
        .map(
          (entry) => {
            'organization_id': organizationId,
            'service_case_id': serviceCaseId,
            'occurred_at': entry.occurredAt.toIso8601String(),
            'ended_at': entry.endedAt?.toIso8601String(),
            'description': entry.description.trim(),
          },
        )
        .where((entry) => entry['description']?.isNotEmpty == true)
        .toList();

    if (progressPayload.isNotEmpty) {
      await _client.from('service_progress_entries').insert(progressPayload);
    }

    if (resolved) {
      try {
        await indexResolvedCase(serviceCaseId);
      } catch (_) {
        // O atendimento permanece salvo mesmo se a indexação estiver indisponível.
      }
    }
  }

  /// Chama a Edge Function `generate-case-embedding` para o atendimento
  /// informado. A própria função só indexa quando `status = 'resolved'`
  /// (ela consulta o registro com a sessão do usuário e valida isso do
  /// lado do servidor), então é seguro chamar assim que soubermos que o
  /// atendimento foi salvo com esse status.
  Future<void> indexResolvedCase(String serviceCaseId) async {
    final response = await _client.functions.invoke(
      'generate-case-embedding',
      body: {'serviceCaseId': serviceCaseId},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('A indexação por IA do atendimento falhou.');
    }
  }

  @override
  Future<List<SimilarCaseResult>> searchSimilarCases(
    SimilarCaseQuery query,
  ) async {
    final response = await _client.functions.invoke(
      'search-similar-cases',
      body: {
        'queryText': query.text.trim(),
        'equipmentId': _blankToNull(query.equipmentId),
        'errorCode': _blankToNull(query.errorCode),
        'subsystem': _blankToNull(query.subsystem),
        'limit': 10,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      throw StateError('A busca inteligente não pôde ser concluída.');
    }

    final body = response.data;
    if (body is! Map) return const [];
    final rawCases = body['cases'];
    if (rawCases is! List) return const [];

    return rawCases
        .map((raw) => mapSimilarCaseJson(_map(raw)))
        .toList(growable: false);
  }

  /// Converte um item do array `cases` retornado pela Edge Function
  /// `search-similar-cases` em um [SimilarCaseResult]. Extraído como
  /// método estático (em vez de closure inline) para poder ser testado
  /// diretamente, sem precisar de um `SupabaseClient` real.
  static SimilarCaseResult mapSimilarCaseJson(Map<String, dynamic> json) {
    final score = (json['final_score'] as num?)?.toDouble() ?? 0.0;
    final reasons = <String>[];
    if (json['exact_code_match'] == true) {
      reasons.add('Código de erro idêntico');
    }
    final lexical = (json['lexical_score'] as num?)?.toDouble() ?? 0.0;
    if (lexical > 0.05) reasons.add('Descrição textual semelhante');
    final vector = (json['vector_similarity'] as num?)?.toDouble() ?? 0.0;
    if (vector > 0.72) reasons.add('Alta similaridade semântica');
    if ({
      'confirmed',
      'recurring',
      'reviewed',
    }.contains(json['solution_confidence'])) {
      reasons.add('Solução validada');
    }

    final serviceCase = ServiceCase(
      id: json['service_case_id'] as String,
      caseNumber: (json['case_number'] as num?)?.toInt() ?? 0,
      equipmentId: json['equipment_id'] as String? ?? '',
      equipmentLabel:
          '${json['manufacturer'] ?? ''} ${json['equipment_model'] ?? ''} · ${json['serial_number'] ?? ''}'
              .trim(),
      status: 'resolved',
      activityType:
          json['activity_type'] as String? ?? ServiceActivityType.maintenance,
      openedAt:
          DateTime.tryParse(json['opened_at'] as String? ?? '') ??
          DateTime.now(),
      reportedFailure: json['reported_failure'] as String? ?? '',
      observedSymptoms: json['observed_symptoms'] as String?,
      errorCode: json['error_code'] as String?,
      subsystem: json['subsystem'] as String?,
      operationalImpact: 'degraded',
      rootCause: json['root_cause'] as String?,
      solutionDetails: json['solution_details'] as String?,
      validationResult: json['validation_result'] as String?,
      finalEquipmentStatus: 'operational',
      solutionConfidence:
          json['solution_confidence'] as String? ?? 'unconfirmed',
    );

    final explanation = json['ai_explanation'] as String?;

    return SimilarCaseResult(
      serviceCase: serviceCase,
      score: score,
      reasons: reasons,
      explanation: explanation?.trim().isEmpty == true ? null : explanation,
    );
  }

  // -----------------------------------------------------------------------
  // Arquivamento
  // -----------------------------------------------------------------------
  // A validação de dependências é responsabilidade do servidor: a RPC
  // `apply_offline_operation` recusa o arquivamento e devolve conflito.
  // Estes caminhos diretos são usados apenas quando o aplicativo fala com
  // o Supabase sem passar pela fila offline.

  Future<void> _setDeletedAt(String table, String id, DateTime? value) async {
    await _client
        .from(table)
        .update({'deleted_at': value?.toUtc().toIso8601String()})
        .eq('id', id);
  }

  @override
  Future<void> archiveCustomer(String id) =>
      _setDeletedAt('customers', id, DateTime.now());

  @override
  Future<void> archiveEquipment(String id) =>
      _setDeletedAt('equipments', id, DateTime.now());

  @override
  Future<void> archiveCase(String id) =>
      _setDeletedAt('service_cases', id, DateTime.now());

  @override
  Future<void> restoreCustomer(String id) =>
      _setDeletedAt('customers', id, null);

  @override
  Future<void> restoreEquipment(String id) =>
      _setDeletedAt('equipments', id, null);

  @override
  Future<void> restoreCase(String id) =>
      _setDeletedAt('service_cases', id, null);

  @override
  Future<ArchivedRecords> fetchArchived() async {
    final results = await Future.wait<dynamic>([
      _client
          .from('customers')
          .select()
          .not('deleted_at', 'is', null)
          .order('deleted_at', ascending: false),
      _client
          .from('equipments')
          .select('''
      id,
      equipment_model_id,
      site_id,
      serial_number,
      software_version,
      hardware_version,
      status,
      notes,
      deleted_at,
      equipment_models(
        id,
        family,
        model,
        modality,
        manufacturers(name)
      ),
      sites(
        id,
        name,
        customers(name)
      )
    ''')
          .not('deleted_at', 'is', null)
          .order('deleted_at', ascending: false),
      _client
          .from('service_cases')
          .select('id, case_number, reported_failure, opened_at, deleted_at')
          .not('deleted_at', 'is', null)
          .order('deleted_at', ascending: false),
    ]);

    return ArchivedRecords(
      customers: (results[0] as List).map((row) {
        final json = _map(row);
        return CustomerOption(
          id: json['id'] as String,
          name: json['name'] as String? ?? '',
          taxId: json['tax_id'] as String?,
          contactName: json['contact_name'] as String?,
          email: json['email'] as String?,
          phone: json['phone'] as String?,
          addressLine: json['address_line'] as String?,
          city: json['city'] as String?,
          state: json['state'] as String?,
          notes: json['notes'] as String?,
          archivedAt: DateTime.tryParse(json['deleted_at'] as String? ?? ''),
        );
      }).toList(),
      equipment: (results[1] as List).map((row) {
        final json = _map(row);
        return Equipment.fromSupabase(json);
      }).toList(),
      cases: (results[2] as List).map((row) {
        final item = _map(row);
        return ServiceCaseSummary(
          id: item['id'] as String,
          caseNumber: (item['case_number'] as num?)?.toInt() ?? 0,
          equipmentLabel: '',
          reportedFailure: item['reported_failure'] as String? ?? '',
          openedAt:
              DateTime.tryParse(item['opened_at'] as String? ?? '') ??
              DateTime.now(),
          archivedAt: DateTime.tryParse(item['deleted_at'] as String? ?? ''),
        );
      }).toList(),
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  Future<String> _organizationId() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sessão não autenticada.');
    final profile = await _client
        .from('profiles')
        .select('organization_id')
        .eq('user_id', user.id)
        .single();
    return profile['organization_id'] as String;
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static Map<String, dynamic> _firstMap(dynamic value) {
    if (value is List && value.isNotEmpty) return _map(value.first);
    return _map(value);
  }

  static String _fallback(String? value, String fallback) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? fallback : cleaned;
  }

  static String? _blankToNull(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
