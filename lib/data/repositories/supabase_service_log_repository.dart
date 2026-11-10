import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/keyset_pagination.dart';

import '../models/equipment.dart';
import '../models/service_case.dart';

/// Leituras do Supabase: o download da sincronização, os arquivados e a
/// busca por casos semelhantes.
///
/// Não grava. Toda gravação do aplicativo passa pela fila offline e chega
/// ao servidor pela RPC `apply_offline_operation`, que é onde vivem as
/// regras de revisão, de arquivamento e de exclusão. Esta classe já teve
/// um caminho de escrita direta nas tabelas, de antes da fila; ele não
/// era mais chamado e contornava essas regras, então saiu.
class SupabaseServiceLogRepository {
  SupabaseServiceLogRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Revisão de cada registro lido, por `tipo:id`, preenchida pelas
  /// próprias consultas de download.
  ///
  /// Antes vinha de cinco consultas à parte, sem paginação: acima de mil
  /// registros numa tabela, o PostgREST cortava a resposta em silêncio e
  /// os registros de fora ficavam com revisão zero — o que desliga a
  /// detecção de conflito no servidor justamente nas bases maiores.
  final Map<String, int> _revisions = <String, int>{};

  /// Cópia das revisões coletadas até aqui. Chamar depois das leituras.
  Map<String, int> takeRevisions() {
    final copy = Map<String, int>.of(_revisions);
    _revisions.clear();
    return copy;
  }

  Future<List<Equipment>> fetchEquipments() async {
    final rows = await _fetchAll('equipments', revisionsAs: 'equipment', '''
      id,
      sync_revision,
      created_at,
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
    ''');

    // A ordem de exibição é aplicada sobre o conjunto completo: o
    // percurso paginado é por `id`, que não tem significado visual.
    final equipment = rows
        .map((row) => Equipment.fromSupabase(row))
        .toList(growable: false);
    final byId = {for (final row in rows) row['id'] as String: row};
    final ordered = [...equipment]
      ..sort((a, b) {
        final da = byId[a.id]?['created_at'] as String? ?? '';
        final db = byId[b.id]?['created_at'] as String? ?? '';
        return db.compareTo(da);
      });
    return List.unmodifiable(ordered);
  }

  Future<List<ServiceCase>> fetchCases() async {
    final rows = await _fetchAll(
      'service_cases',
      revisionsAs: 'service_case',
      '''
      id,
      sync_revision,
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
    ''',
    );

    // O limite de 300 saiu daqui: truncava o histórico sem aviso, e
    // o PostgREST ainda somava o próprio corte por cima. A ordenação
    // por abertura é aplicada ao conjunto completo.
    final cases = rows.map((row) => ServiceCase.fromSupabase(row)).toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return List.unmodifiable(cases);
  }

  Future<EquipmentCatalog> fetchEquipmentCatalog() async {
    // As três consultas também eram cortadas pelo PostgREST, em silêncio.
    // Nenhuma tinha limite explícito, o que tornava o truncamento ainda
    // menos visível que o dos atendimentos.
    final responses = await Future.wait<List<Map<String, dynamic>>>([
      _fetchAll('equipment_models', revisionsAs: 'equipment_model', '''
        id,
        sync_revision,
        family,
        model,
        modality,
        manufacturers(name)
      '''),
      _fetchAll('customers', revisionsAs: 'customer', '''
        id,
        sync_revision,
        name,
        tax_id,
        contact_name,
        email,
        phone,
        address_line,
        city,
        state,
        notes
      '''),
      _fetchAll('sites', revisionsAs: 'site', '''
        id,
        sync_revision,
        customer_id,
        name,
        city,
        state,
        notes,
        customers(name)
      '''),
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

    // Ordem de exibição restaurada sobre o conjunto completo — o percurso
    // paginado usa `id`, que não serve para apresentação.
    int porTexto(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());

    return EquipmentCatalog(
      models: [...models]..sort((a, b) => porTexto(a.model, b.model)),
      customers: [...customers]..sort((a, b) => porTexto(a.name, b.name)),
      sites: [...sites]..sort((a, b) => porTexto(a.site, b.site)),
    );
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
      equipmentLabel: [
        '${json['manufacturer'] ?? ''} ${json['equipment_model'] ?? ''}'.trim(),
        if ((json['serial_number'] as String?)?.trim().isNotEmpty == true)
          (json['serial_number'] as String).trim(),
      ].where((part) => part.isNotEmpty).join(' · '),
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

  Future<ArchivedRecords> fetchArchived() async {
    // Arquivados também eram cortados pelo PostgREST. Mesma paginação.
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _fetchAll('customers', '''
        id, name, tax_id, contact_name, email, phone,
        address_line, city, state, notes, deleted_at
      ''', archived: true),
      _fetchAll('equipments', '''
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
      ''', archived: true),
      _fetchAll(
        'service_cases',
        'id, case_number, equipment_id, reported_failure, opened_at, deleted_at',
        archived: true,
      ),
    ]);

    // O percurso paginado é por `id`; a ordem de apresentação —
    // arquivados mais recentes primeiro — é aplicada aqui.
    return ArchivedRecords(
      customers:
          (results[0] as List).map((row) {
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
              archivedAt: DateTime.tryParse(
                json['deleted_at'] as String? ?? '',
              ),
            );
          }).toList()..sort(
            (a, b) => (b.archivedAt ?? DateTime(0)).compareTo(
              a.archivedAt ?? DateTime(0),
            ),
          ),
      equipment:
          (results[1] as List).map((row) {
            final json = _map(row);
            return Equipment.fromSupabase(json);
          }).toList()..sort(
            (a, b) => (b.archivedAt ?? DateTime(0)).compareTo(
              a.archivedAt ?? DateTime(0),
            ),
          ),
      cases:
          (results[2] as List).map((row) {
            final item = _map(row);
            return ServiceCaseSummary(
              id: item['id'] as String,
              caseNumber: (item['case_number'] as num?)?.toInt() ?? 0,
              equipmentId: item['equipment_id'] as String? ?? '',
              equipmentLabel: '',
              reportedFailure: item['reported_failure'] as String? ?? '',
              openedAt:
                  DateTime.tryParse(item['opened_at'] as String? ?? '') ??
                  DateTime.now(),
              archivedAt: DateTime.tryParse(
                item['deleted_at'] as String? ?? '',
              ),
            );
          }).toList()..sort(
            (a, b) => (b.archivedAt ?? DateTime(0)).compareTo(
              a.archivedAt ?? DateTime(0),
            ),
          ),
    );
  }

  /// Lê a tabela inteira, em páginas, em vez de aceitar o corte do
  /// PostgREST. Percorre por `id` porque a ordem de exibição não pode
  /// servir de cursor: `name` e `created_at` repetem, e chave repetida
  /// faz a página seguinte pular ou repetir registros.
  ///
  /// Quem chama ordena o resultado completo.
  /// [archived] escolhe o lado do `deleted_at`: nulo traz os ativos,
  /// verdadeiro traz os arquivados, e `null` não filtra.
  Future<List<Map<String, dynamic>>> _fetchAll(
    String table,
    String columns, {
    bool? archived = false,
    String? revisionsAs,
  }) async {
    final rows = await fetchAllPages<Map<String, dynamic>>(
      keyOf: (row) => row['id'] as String,
      readPage: (after, limit) async {
        var query = _client.from(table).select(columns);
        if (archived == false) query = query.isFilter('deleted_at', null);
        if (archived == true) query = query.not('deleted_at', 'is', null);
        if (after != null) query = query.gt('id', after);
        final page = await query.order('id', ascending: true).limit(limit);
        return (page as List).map(_map).toList(growable: false);
      },
    );
    if (revisionsAs != null) {
      for (final row in rows) {
        _revisions['$revisionsAs:${row['id']}'] =
            (row['sync_revision'] as num?)?.toInt() ?? 1;
      }
    }
    return rows;
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

  static String? _blankToNull(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
