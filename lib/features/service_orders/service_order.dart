import '../../data/models/equipment.dart';
import '../../data/models/service_case.dart';
import '../../data/models/service_time_metrics.dart';
import '../cases/activity_copy.dart';

/// Uma linha "nome: valor" da ordem de serviço.
class ServiceOrderField {
  const ServiceOrderField(this.label, this.value);

  final String label;
  final String value;
}

/// Bloco de texto livre, como a solução aplicada. Ocupa a largura toda,
/// ao contrário dos [ServiceOrderField] do cabeçalho, que vão lado a lado.
class ServiceOrderSection {
  const ServiceOrderSection(this.title, this.fields);

  final String title;
  final List<ServiceOrderField> fields;
}

class ServiceOrderSession {
  const ServiceOrderSession({
    required this.start,
    required this.description,
    this.end,
  });

  final DateTime start;
  final DateTime? end;
  final String description;

  int? get minutes => end?.difference(start).inMinutes;
}

/// Conteúdo de uma ordem de serviço, pronto para ser desenhado.
///
/// Fica separado do PDF de propósito: aqui se decide O QUE sai na OS
/// (quais campos, com que nome, o que fica de fora por estar vazio), e
/// isso é testável sem abrir o arquivo gerado.
class ServiceOrder {
  const ServiceOrder({
    required this.caseNumber,
    required this.organizationName,
    required this.issuerName,
    required this.issuedAt,
    required this.activityLabel,
    required this.statusLabel,
    required this.openedAt,
    required this.customerFields,
    required this.equipmentFields,
    required this.sections,
    required this.sessions,
    required this.serviceMinutes,
    this.closedAt,
    this.downtimeMinutes,
  });

  final int caseNumber;
  final String organizationName;
  final String issuerName;
  final DateTime issuedAt;
  final String activityLabel;
  final String statusLabel;
  final DateTime openedAt;
  final DateTime? closedAt;
  final List<ServiceOrderField> customerFields;
  final List<ServiceOrderField> equipmentFields;
  final List<ServiceOrderSection> sections;
  final List<ServiceOrderSession> sessions;

  /// Soma das sessões encerradas — a mesma conta do formulário.
  final int serviceMinutes;

  /// Calculada pelo servidor. Nula num atendimento que ainda não passou
  /// por ele; a OS então simplesmente não mostra a linha.
  final int? downtimeMinutes;

  /// Monta a OS a partir do atendimento e do que se sabe sobre o
  /// equipamento, o local e o cliente.
  ///
  /// [equipment], [site] e [customer] podem faltar — um equipamento sem
  /// local, ou um catálogo que ainda não carregou. A OS sai assim mesmo,
  /// com o que houver: a etiqueta desnormalizada do atendimento garante
  /// ao menos a identificação do equipamento.
  factory ServiceOrder.assemble({
    required ServiceCase item,
    required String organizationName,
    required String issuerName,
    required DateTime issuedAt,
    Equipment? equipment,
    SiteOption? site,
    CustomerOption? customer,
  }) {
    final copy = ActivityCopy.forType(item.activityType);

    final customerName = _text(customer?.name) ?? _text(equipment?.customer);
    // O local leva a própria cidade: um cliente com várias unidades
    // costuma ter cadastrado o endereço da sede, não o de cada unidade.
    final siteName = _joined([
      _text(site?.site) ?? _text(equipment?.site),
      site?.locationLabel,
    ], ' — ');
    final customerFields = _present([
      ('Cliente', customerName),
      ('CNPJ / CPF', customer?.taxId),
      ('Local', siteName),
      (
        'Endereço',
        _joined([customer?.addressLine, customer?.locationLabel], ' — '),
      ),
      ('Contato', customer?.contactName),
      ('Telefone', customer?.phone),
      ('E-mail', customer?.email),
    ]);

    final equipmentFields = equipment == null
        ? _present([('Equipamento', item.equipmentLabel)])
        : _present([
            ('Equipamento', equipment.displayName),
            ('Modalidade', equipment.modality),
            ('Número de série', equipment.serialNumber),
            ('Versão de software', equipment.softwareVersion),
            ('Versão de hardware', equipment.hardwareVersion),
          ]);

    final sections = <ServiceOrderSection>[
      ServiceOrderSection(
        'Chamado',
        _present([
          (copy.primaryFieldLabel, item.reportedFailure),
          (copy.referenceLabel, item.errorCode),
          (copy.subsystemLabel, item.subsystem),
          (copy.initialNotesLabel, item.errorMessage),
          (copy.impactLabel, labelForImpact(item.operationalImpact)),
        ]),
      ),
      ServiceOrderSection(
        copy.executionStepTitle,
        _present([
          (copy.executionSummaryLabel, item.observedSymptoms),
          (copy.measurementsLabel, item.measurements),
          (copy.deviationLabel, item.rootCause),
          ('Notas de segurança', item.safetyNotes),
        ]),
      ),
      ServiceOrderSection(
        copy.conclusionStepTitle,
        _present([
          (copy.solutionLabel, item.solutionDetails),
          (copy.validationLabel, item.validationResult),
          (
            'Condição final do equipamento',
            labelForFinalCondition(item.finalEquipmentStatus),
          ),
          if (item.requiresFollowUp)
            (
              'Retorno ou acompanhamento',
              _text(item.followUpNotes) ?? 'Necessário, a combinar.',
            ),
        ]),
      ),
    ].where((section) => section.fields.isNotEmpty).toList();

    final sessions = [...item.progressEntries]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return ServiceOrder(
      caseNumber: item.caseNumber,
      organizationName: organizationName,
      issuerName: issuerName,
      issuedAt: issuedAt,
      activityLabel: ServiceActivityType.label(item.activityType),
      statusLabel: labelForStatus(item.status),
      openedAt: item.openedAt,
      closedAt: item.closedAt,
      customerFields: customerFields,
      equipmentFields: equipmentFields,
      sections: sections,
      sessions: [
        for (final entry in sessions)
          ServiceOrderSession(
            start: entry.occurredAt,
            end: entry.endedAt,
            description: entry.description.trim(),
          ),
      ],
      serviceMinutes: ServiceTimeMetrics.serviceMinutes(item.progressEntries),
      downtimeMinutes: item.downtimeMinutes,
    );
  }

  static String labelForStatus(String value) => switch (value) {
    'open' => 'Aberto',
    'diagnosing' => 'Em andamento',
    'waiting_parts' => 'Aguardando peça / material',
    'waiting_customer' => 'Aguardando cliente / local',
    'resolved' => 'Concluído',
    'cancelled' => 'Cancelado',
    _ => value,
  };

  static String? labelForImpact(String value) => switch (value) {
    'none' => 'Sem impacto',
    'degraded' => 'Operação degradada',
    'partial_stop' => 'Parada parcial',
    'total_stop' => 'Parada total',
    _ => null,
  };

  static String? labelForFinalCondition(String? value) => switch (value) {
    'operational' => 'Operacional',
    'degraded' => 'Degradado',
    'stopped' => 'Parado',
    'decommissioned' => 'Desativado / removido',
    _ => null,
  };

  /// "3h 05min", como no formulário, mas com os minutos em dois dígitos
  /// para as colunas da tabela de sessões alinharem.
  static String formatMinutes(int minutes) {
    if (minutes <= 0) return '0 min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '$minutes min';
    return '${hours}h ${remainder.toString().padLeft(2, '0')}min';
  }

  /// Nome do arquivo, sem pasta. A data e a hora da emissão entram no
  /// nome porque a mesma OS pode ser emitida de novo depois de uma
  /// correção, e a versão anterior — talvez já enviada ao cliente — não
  /// deve ser sobrescrita.
  String get fileName {
    String two(int value) => value.toString().padLeft(2, '0');
    final d = issuedAt;
    return 'OS-$caseNumber'
        '_${d.year}-${two(d.month)}-${two(d.day)}'
        '_${two(d.hour)}${two(d.minute)}.pdf';
  }

  /// Os rótulos do formulário avisam que o campo é opcional; na OS,
  /// preenchida, o aviso não faz sentido.
  static String cleanLabel(String label) =>
      label.replaceAll(RegExp(r'\s*\(opcional\)\s*$'), '');

  static String? _text(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static List<ServiceOrderField> _present(List<(String, String?)> pairs) => [
    for (final (label, value) in pairs)
      if (_text(value) case final text?)
        ServiceOrderField(cleanLabel(label), text),
  ];

  static String? _joined(List<String?> parts, String separator) {
    final present = parts.map(_text).whereType<String>().toList();
    return present.isEmpty ? null : present.join(separator);
  }
}
