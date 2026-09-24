import '../../data/models/equipment.dart';
import '../../data/models/service_case.dart';
import '../cases/activity_copy.dart';
import 'service_order_details.dart';
import 'service_order_issuer.dart';

/// Uma linha "nome: valor" da ordem de serviço.
class ServiceOrderField {
  const ServiceOrderField(this.label, this.value);

  final String label;
  final String value;
}

/// Conteúdo de uma ordem de serviço, no desenho do modelo em uso pela
/// ORION, pronto para ser desenhado.
///
/// Fica separado do PDF de propósito: aqui se decide O QUE vai em cada
/// casa do modelo, e isso é testável sem abrir o arquivo gerado.
class ServiceOrder {
  const ServiceOrder({
    required this.caseNumber,
    required this.issuedAt,
    required this.issuer,
    required this.customer,
    required this.address,
    required this.sector,
    required this.requester,
    required this.equipment,
    required this.serialAndTag,
    required this.manufacturerModel,
    required this.openedAt,
    required this.narrative,
    required this.materials,
    required this.checks,
    required this.testNotes,
    required this.recommendations,
    this.startedAt,
    this.finishedAt,
    this.downtimeMinutes,
    this.situation,
  });

  final int caseNumber;
  final DateTime issuedAt;
  final ServiceOrderIssuer issuer;

  // Dados do atendimento.
  final String customer;
  final String address;
  final String sector;
  final String requester;
  final String equipment;
  final String serialAndTag;
  final String manufacturerModel;

  final DateTime openedAt;

  /// Início da primeira sessão de trabalho.
  final DateTime? startedAt;

  /// Conclusão do atendimento ou, sem ela, fim da última sessão.
  final DateTime? finishedAt;

  /// Calculada pelo servidor; nula num atendimento que ainda não passou
  /// por ele.
  final int? downtimeMinutes;

  /// Relato, causa e procedimento — sempre os três, mesmo vazios, como no
  /// modelo.
  final List<ServiceOrderField> narrative;

  final List<ServiceOrderMaterial> materials;
  final Set<ServiceOrderCheck> checks;

  /// Medições e validação registradas no atendimento, que o modelo não
  /// tem onde pôr e saem abaixo da lista de verificações.
  final List<ServiceOrderField> testNotes;

  final ServiceOrderSituation? situation;
  final String recommendations;

  /// Monta a OS a partir do atendimento, do cadastro, do emitente e dos
  /// complementos digitados na janela da OS.
  ///
  /// [equipment], [site] e [customer] podem faltar — um equipamento sem
  /// local, ou um catálogo que ainda não carregou. A OS sai assim mesmo:
  /// a etiqueta desnormalizada do atendimento garante ao menos a
  /// identificação do equipamento.
  factory ServiceOrder.assemble({
    required ServiceCase item,
    required ServiceOrderIssuer issuer,
    required ServiceOrderDetails details,
    required DateTime issuedAt,
    Equipment? equipment,
    SiteOption? site,
    CustomerOption? customer,
  }) {
    final copy = ActivityCopy.forType(item.activityType);
    final maintenance = item.activityType == ServiceActivityType.maintenance;

    final sessions = [...item.progressEntries]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    DateTime? lastEnd;
    for (final entry in sessions) {
      final end = entry.endedAt;
      if (end != null && (lastEnd == null || end.isAfter(lastEnd))) {
        lastEnd = end;
      }
    }

    final serial = equipment?.serialNumber.trim() ?? '';
    final tag = details.assetTag.trim();

    // O modelo foi desenhado para manutenção. Nas outras atividades, os
    // nomes das casas vêm do formulário daquela atividade, para que um
    // "Escopo da instalação" não saia rotulado como "Relato do cliente".
    final narrative = [
      ServiceOrderField(
        maintenance ? 'Relato do cliente' : clean(copy.primaryFieldLabel),
        _joinLines([
          item.reportedFailure,
          _joinText([
            if (item.errorCode?.trim().isNotEmpty ?? false)
              '${clean(copy.referenceLabel)}: ${item.errorCode!.trim()}',
            item.errorMessage,
          ], ' — '),
        ]),
      ),
      ServiceOrderField(
        maintenance ? 'Causa identificada' : clean(copy.deviationLabel),
        item.rootCause?.trim() ?? '',
      ),
      ServiceOrderField(
        maintenance ? 'Procedimento executado' : clean(copy.solutionLabel),
        item.solutionDetails?.trim() ?? '',
      ),
    ];

    return ServiceOrder(
      caseNumber: item.caseNumber,
      issuedAt: issuedAt,
      issuer: issuer,
      customer: _first([customer?.name, equipment?.customer]),
      address: _joinText([
        customer?.addressLine,
        _first([customer?.locationLabel, site?.locationLabel]),
      ], ' — '),
      sector: details.sector.trim(),
      requester: details.requester.trim(),
      equipment: _first([equipment?.modality, equipment?.family]),
      serialAndTag: _joinText([serial, tag], ' / '),
      manufacturerModel: equipment == null
          ? item.equipmentLabel
          : _joinText([equipment.manufacturer, equipment.model], ' / '),
      openedAt: item.openedAt,
      startedAt: sessions.isEmpty ? null : sessions.first.occurredAt,
      finishedAt: item.closedAt ?? lastEnd,
      downtimeMinutes: item.downtimeMinutes,
      narrative: narrative,
      materials: [
        for (final material in details.materials)
          if (!material.isEmpty) material,
      ],
      checks: details.checks,
      testNotes: [
        for (final (label, value) in [
          (clean(copy.measurementsLabel), item.measurements),
          (clean(copy.validationLabel), item.validationResult),
        ])
          if (value?.trim().isNotEmpty ?? false)
            ServiceOrderField(label, value!.trim()),
      ],
      situation: details.situation,
      recommendations: details.recommendations.trim(),
    );
  }

  /// "3h 05min". Minutos em dois dígitos para as horas lerem bem.
  static String formatMinutes(int minutes) {
    if (minutes <= 0) return '0 min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '$minutes min';
    return '${hours}h ${remainder.toString().padLeft(2, '0')}min';
  }

  static const _months = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  /// "Curitiba/PR, 24 de setembro de 2026." — o local e a data acima das
  /// assinaturas. Escrito à mão para não depender dos dados de idioma do
  /// intl, que precisariam ser carregados antes.
  String get placeAndDate {
    final d = issuedAt;
    final date = '${d.day} de ${_months[d.month - 1]} de ${d.year}';
    final city = issuer.city.trim();
    return city.isEmpty ? '$date.' : '$city, $date.';
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
  static String clean(String label) =>
      label.replaceAll(RegExp(r'\s*\(opcional\)\s*$'), '');

  static String _first(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  static String _joinText(List<String?> parts, String separator) => parts
      .map((part) => part?.trim() ?? '')
      .where((part) => part.isNotEmpty)
      .join(separator);

  static String _joinLines(List<String?> parts) => _joinText(parts, '\n');
}
