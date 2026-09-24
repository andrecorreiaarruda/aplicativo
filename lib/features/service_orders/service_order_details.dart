import '../../data/models/equipment.dart';
import '../../data/models/service_case.dart';

/// Itens de "Testes e verificações finais", na ordem do modelo de OS:
/// três colunas de três, lidas de cima para baixo.
enum ServiceOrderCheck {
  functionalTest('Teste funcional completo'),
  electricalSafety('Segurança elétrica'),
  calibration('Calibração / aferição'),
  cleaning('Limpeza e conservação'),
  alarms('Alarmes e mensagens'),
  operatorTraining('Treinamento ao operador'),
  documentation('Documentação atualizada'),
  partReturned('Peça devolvida ao cliente'),
  followUpNeeded('Necessário retorno técnico');

  const ServiceOrderCheck(this.label);

  final String label;
}

/// "Situação final e pendências" do modelo. Uma só pode estar marcada.
enum ServiceOrderSituation {
  released('Equipamento liberado para uso clínico'),
  restricted('Liberado com restrição'),
  inoperative('Inoperante'),
  awaiting('Aguardando peça / aprovação');

  const ServiceOrderSituation(this.label);

  final String label;
}

class ServiceOrderMaterial {
  const ServiceOrderMaterial({
    this.description = '',
    this.partNumber = '',
    this.quantity = '',
    this.warranty = '',
  });

  final String description;
  final String partNumber;

  /// Texto, e não número: "2", "1,5 m" e "1 kit" são todos válidos.
  final String quantity;
  final String warranty;

  bool get isEmpty =>
      description.trim().isEmpty &&
      partNumber.trim().isEmpty &&
      quantity.trim().isEmpty &&
      warranty.trim().isEmpty;

  Map<String, String> toJson() => {
    'description': description,
    'partNumber': partNumber,
    'quantity': quantity,
    'warranty': warranty,
  };

  factory ServiceOrderMaterial.fromJson(Map<dynamic, dynamic> json) =>
      ServiceOrderMaterial(
        description: json['description'] as String? ?? '',
        partNumber: json['partNumber'] as String? ?? '',
        quantity: json['quantity'] as String? ?? '',
        warranty: json['warranty'] as String? ?? '',
      );
}

/// O que a OS pede e o atendimento não guarda.
///
/// Preenchido na janela da OS e gravado junto dela neste computador:
/// emitir de novo, depois de uma correção, reaproveita o que já foi
/// digitado. Não sobe para o servidor.
class ServiceOrderDetails {
  const ServiceOrderDetails({
    this.requester = '',
    this.sector = '',
    this.assetTag = '',
    this.materials = const [],
    this.checks = const {},
    this.situation,
    this.recommendations = '',
  });

  final String requester;
  final String sector;

  /// Número de patrimônio do cliente.
  final String assetTag;
  final List<ServiceOrderMaterial> materials;
  final Set<ServiceOrderCheck> checks;
  final ServiceOrderSituation? situation;
  final String recommendations;

  /// Primeira abertura da janela para um atendimento: sugere o que dá
  /// para deduzir dele. Tudo continua editável.
  factory ServiceOrderDetails.suggest({
    required ServiceCase item,
    SiteOption? site,
    CustomerOption? customer,
    Equipment? equipment,
  }) {
    return ServiceOrderDetails(
      requester: customer?.contactName?.trim() ?? '',
      sector: site?.site.trim() ?? equipment?.site.trim() ?? '',
      checks: {
        if (item.validationResult?.trim().isNotEmpty ?? false)
          ServiceOrderCheck.functionalTest,
        if (item.requiresFollowUp) ServiceOrderCheck.followUpNeeded,
      },
      situation: suggestSituation(item),
      recommendations: item.requiresFollowUp
          ? item.followUpNotes?.trim() ?? ''
          : '',
    );
  }

  /// Situação final a partir da condição registrada no atendimento.
  static ServiceOrderSituation? suggestSituation(ServiceCase item) {
    if (item.status == 'waiting_parts' || item.status == 'waiting_customer') {
      return ServiceOrderSituation.awaiting;
    }
    return switch (item.finalEquipmentStatus) {
      'operational' => ServiceOrderSituation.released,
      'degraded' => ServiceOrderSituation.restricted,
      'stopped' || 'decommissioned' => ServiceOrderSituation.inoperative,
      _ => null,
    };
  }

  ServiceOrderDetails copyWith({
    String? requester,
    String? sector,
    String? assetTag,
    List<ServiceOrderMaterial>? materials,
    Set<ServiceOrderCheck>? checks,
    ServiceOrderSituation? situation,
    bool clearSituation = false,
    String? recommendations,
  }) => ServiceOrderDetails(
    requester: requester ?? this.requester,
    sector: sector ?? this.sector,
    assetTag: assetTag ?? this.assetTag,
    materials: materials ?? this.materials,
    checks: checks ?? this.checks,
    situation: clearSituation ? null : situation ?? this.situation,
    recommendations: recommendations ?? this.recommendations,
  );

  Map<String, Object?> toJson() => {
    'requester': requester,
    'sector': sector,
    'assetTag': assetTag,
    'materials': [
      for (final material in materials)
        if (!material.isEmpty) material.toJson(),
    ],
    'checks': [for (final check in checks) check.name],
    'situation': situation?.name,
    'recommendations': recommendations,
  };

  factory ServiceOrderDetails.fromJson(Map<dynamic, dynamic> json) {
    T? byName<T extends Enum>(List<T> values, Object? name) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return null;
    }

    return ServiceOrderDetails(
      requester: json['requester'] as String? ?? '',
      sector: json['sector'] as String? ?? '',
      assetTag: json['assetTag'] as String? ?? '',
      materials: [
        for (final item in json['materials'] as List? ?? const [])
          if (item is Map) ServiceOrderMaterial.fromJson(item),
      ],
      checks: {
        for (final name in json['checks'] as List? ?? const [])
          ?byName(ServiceOrderCheck.values, name),
      },
      situation: byName(ServiceOrderSituation.values, json['situation']),
      recommendations: json['recommendations'] as String? ?? '',
    );
  }
}
