class Equipment {
  const Equipment({
    required this.id,
    required this.modelId,
    required this.manufacturer,
    required this.family,
    required this.model,
    required this.modality,
    required this.serialNumber,
    required this.customer,
    required this.site,
    required this.status,
    this.siteId,
    this.softwareVersion,
    this.hardwareVersion,
    this.notes,
    this.archivedAt,
  });

  final String id;
  final String modelId;
  final String manufacturer;
  final String family;
  final String model;
  final String modality;
  final String serialNumber;
  final String customer;
  final String site;
  final String status;
  final String? siteId;
  final String? softwareVersion;
  final String? hardwareVersion;
  final String? notes;

  /// Momento em que o equipamento foi arquivado. Nulo enquanto ativo.
  /// Corresponde a `deleted_at` no banco: o registro continua existindo
  /// e preserva o histórico de atendimentos vinculado a ele.
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  /// Vazio quando a série não pôde ser identificada. No banco a coluna
  /// é nula nesse caso: nulos não colidem entre si no índice único,
  /// enquanto a cadeia vazia colidiria na segunda ocorrência.
  bool get hasSerial => serialNumber.trim().isNotEmpty;

  /// Rótulo para exibição, sempre preenchido.
  String get serialLabel => hasSerial ? serialNumber : 'Série não informada';

  String get displayName => '$manufacturer $model';
  String get locationLabel =>
      [customer, site].where((value) => value.isNotEmpty).join(' · ');

  factory Equipment.fromSupabase(Map<String, dynamic> json) {
    final model = _firstMap(json['equipment_models']);
    final manufacturer = _firstMap(model['manufacturers']);
    final site = _firstMap(json['sites']);
    final customer = _firstMap(site['customers']);

    return Equipment(
      id: json['id'] as String,
      modelId: (json['equipment_model_id'] ?? model['id'] ?? '') as String,
      manufacturer:
          manufacturer['name'] as String? ?? 'Fabricante não informado',
      family: model['family'] as String? ?? '',
      model: model['model'] as String? ?? 'Modelo não informado',
      modality: model['modality'] as String? ?? 'Não informada',
      serialNumber: json['serial_number'] as String? ?? '',
      customer: customer['name'] as String? ?? '',
      site: site['name'] as String? ?? '',
      siteId: json['site_id'] as String?,
      softwareVersion: json['software_version'] as String?,
      hardwareVersion: json['hardware_version'] as String?,
      status: json['status'] as String? ?? 'operational',
      notes: json['notes'] as String?,
    );
  }

  static Map<String, dynamic> _firstMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List &&
        value.isNotEmpty &&
        value.first is Map<String, dynamic>) {
      return value.first as Map<String, dynamic>;
    }
    return <String, dynamic>{};
  }
}

class EquipmentDraft {
  const EquipmentDraft({
    required this.modelId,
    required this.serialNumber,
    required this.status,
    this.siteId,
    this.softwareVersion,
    this.hardwareVersion,
    this.notes,
  });

  final String modelId;
  final String serialNumber;
  final String status;
  final String? siteId;
  final String? softwareVersion;
  final String? hardwareVersion;
  final String? notes;
}

class EquipmentModelOption {
  const EquipmentModelOption({
    required this.id,
    required this.manufacturer,
    required this.family,
    required this.model,
    required this.modality,
  });

  final String id;
  final String manufacturer;
  final String family;
  final String model;
  final String modality;

  String get label {
    final details = [
      if (family.trim().isNotEmpty) family.trim(),
      if (modality.trim().isNotEmpty && modality != 'Não informada')
        modality.trim(),
    ];
    return details.isEmpty
        ? '$manufacturer $model'
        : "$manufacturer $model — ${details.join(' · ')}";
  }
}

class EquipmentModelDraft {
  const EquipmentModelDraft({
    required this.manufacturer,
    required this.model,
    required this.modality,
    this.family,
    this.description,
  });

  final String manufacturer;
  final String model;
  final String modality;
  final String? family;
  final String? description;
}

class CustomerOption {
  const CustomerOption({
    required this.id,
    required this.name,
    this.taxId,
    this.contactName,
    this.email,
    this.phone,
    this.addressLine,
    this.city,
    this.state,
    this.notes,
    this.archivedAt,
  });

  final String id;
  final String name;
  final String? taxId;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? addressLine;
  final String? city;
  final String? state;
  final String? notes;

  /// Ver [Equipment.archivedAt].
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  String get locationLabel => [
    city,
    state,
  ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' / ');
}

class SiteOption {
  const SiteOption({
    required this.id,
    required this.customerId,
    required this.customer,
    required this.site,
    this.city,
    this.state,
    this.notes,
  });

  final String id;
  final String customerId;
  final String customer;
  final String site;
  final String? city;
  final String? state;
  final String? notes;

  String get label => '$customer — $site';
  String get locationLabel => [
    city,
    state,
  ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' / ');
}

class EquipmentCatalog {
  const EquipmentCatalog({
    required this.models,
    required this.customers,
    required this.sites,
  });

  final List<EquipmentModelOption> models;
  final List<CustomerOption> customers;
  final List<SiteOption> sites;

  static const empty = EquipmentCatalog(models: [], customers: [], sites: []);
}

class CustomerDraft {
  const CustomerDraft({
    required this.name,
    this.taxId,
    this.contactName,
    this.email,
    this.phone,
    this.addressLine,
    this.city,
    this.state,
    this.notes,
  });

  final String name;
  final String? taxId;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? addressLine;
  final String? city;
  final String? state;
  final String? notes;
}

class SiteDraft {
  const SiteDraft({
    required this.customerId,
    required this.siteName,
    this.city,
    this.state,
    this.notes,
  });

  final String customerId;
  final String siteName;
  final String? city;
  final String? state;
  final String? notes;
}

class CustomerSiteDraft {
  const CustomerSiteDraft({
    required this.customerName,
    required this.siteName,
    this.taxId,
    this.contactName,
    this.email,
    this.phone,
    this.addressLine,
    this.customerCity,
    this.customerState,
    this.siteCity,
    this.siteState,
    this.city,
    this.state,
    this.customerNotes,
    this.siteNotes,
  });

  final String customerName;
  final String siteName;
  final String? taxId;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? addressLine;
  final String? customerCity;
  final String? customerState;
  final String? siteCity;
  final String? siteState;
  final String? city;
  final String? state;
  final String? customerNotes;
  final String? siteNotes;
}

/// Conjunto de registros arquivados, exibido na tela de restauração.
class ArchivedRecords {
  const ArchivedRecords({
    this.customers = const [],
    this.equipment = const [],
    this.cases = const [],
  });

  final List<CustomerOption> customers;
  final List<Equipment> equipment;
  final List<ServiceCaseSummary> cases;

  static const empty = ArchivedRecords();

  bool get isEmpty => customers.isEmpty && equipment.isEmpty && cases.isEmpty;

  int get total => customers.length + equipment.length + cases.length;
}

/// Resumo de atendimento arquivado. A tela de restauração não precisa do
/// atendimento inteiro, e trazê-lo completo obrigaria o repositório
/// Supabase a repetir todos os relacionamentos da consulta principal.
class ServiceCaseSummary {
  const ServiceCaseSummary({
    required this.id,
    required this.caseNumber,
    required this.equipmentLabel,
    required this.reportedFailure,
    required this.openedAt,
    this.archivedAt,
  });

  final String id;
  final int caseNumber;
  final String equipmentLabel;
  final String reportedFailure;
  final DateTime openedAt;
  final DateTime? archivedAt;
}
