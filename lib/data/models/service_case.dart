class ServiceActivityType {
  const ServiceActivityType._();

  static const maintenance = 'maintenance';
  static const installation = 'installation';
  static const deinstallation = 'deinstallation';

  static const values = [maintenance, installation, deinstallation];

  static String label(String value) {
    switch (value) {
      case installation:
        return 'Instalação';
      case deinstallation:
        return 'Desinstalação';
      default:
        return 'Manutenção';
    }
  }
}

class ServiceProgressEntry {
  const ServiceProgressEntry({
    required this.id,
    required this.occurredAt,
    required this.description,
  });

  final String id;
  final DateTime occurredAt;
  final String description;

  factory ServiceProgressEntry.fromSupabase(Map<String, dynamic> json) {
    return ServiceProgressEntry(
      id: json['id'] as String? ?? '',
      occurredAt:
          DateTime.tryParse(json['occurred_at'] as String? ?? '') ??
          DateTime.now(),
      description: json['description'] as String? ?? '',
    );
  }
}

class ServiceCase {
  const ServiceCase({
    required this.id,
    required this.caseNumber,
    required this.equipmentId,
    required this.equipmentLabel,
    required this.status,
    required this.openedAt,
    required this.reportedFailure,
    required this.operationalImpact,
    required this.solutionConfidence,
    this.activityType = ServiceActivityType.maintenance,
    this.progressEntries = const [],
    this.closedAt,
    this.observedSymptoms,
    this.errorCode,
    this.errorMessage,
    this.subsystem,
    this.measurements,
    this.rootCause,
    this.solutionDetails,
    this.validationResult,
    this.finalEquipmentStatus,
    this.downtimeMinutes,
    this.serviceMinutes,
    this.requiresFollowUp = false,
    this.followUpNotes,
    this.safetyNotes,
  });

  final String id;
  final int caseNumber;
  final String equipmentId;
  final String equipmentLabel;
  final String status;
  final String activityType;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String reportedFailure;
  final String operationalImpact;
  final String solutionConfidence;
  final List<ServiceProgressEntry> progressEntries;
  final String? observedSymptoms;
  final String? errorCode;
  final String? errorMessage;
  final String? subsystem;
  final String? measurements;
  final String? rootCause;
  final String? solutionDetails;
  final String? validationResult;
  final String? finalEquipmentStatus;
  final int? downtimeMinutes;
  final int? serviceMinutes;
  final bool requiresFollowUp;
  final String? followUpNotes;
  final String? safetyNotes;

  bool get isResolved => status == 'resolved';
  String get activityLabel => ServiceActivityType.label(activityType);

  factory ServiceCase.fromSupabase(Map<String, dynamic> json) {
    final equipment = _firstMap(json['equipments']);
    final model = _firstMap(equipment['equipment_models']);
    final manufacturer = _firstMap(model['manufacturers']);
    final manufacturerName = manufacturer['name'] as String? ?? '';
    final modelName = model['model'] as String? ?? '';
    final serial = equipment['serial_number'] as String? ?? '';
    final progress =
        _listOfMaps(
            json['service_progress_entries'],
          ).map(ServiceProgressEntry.fromSupabase).toList()
          ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return ServiceCase(
      id: json['id'] as String,
      caseNumber: (json['case_number'] as num?)?.toInt() ?? 0,
      equipmentId: json['equipment_id'] as String,
      equipmentLabel: '$manufacturerName $modelName · $serial'.trim(),
      status: json['status'] as String? ?? 'open',
      activityType:
          json['activity_type'] as String? ?? ServiceActivityType.maintenance,
      openedAt:
          DateTime.tryParse(json['opened_at'] as String? ?? '') ??
          DateTime.now(),
      closedAt: DateTime.tryParse(json['closed_at'] as String? ?? ''),
      reportedFailure: json['reported_failure'] as String? ?? '',
      observedSymptoms: json['observed_symptoms'] as String?,
      errorCode: json['error_code'] as String?,
      errorMessage: json['error_message'] as String?,
      subsystem: json['subsystem'] as String?,
      operationalImpact: json['operational_impact'] as String? ?? 'degraded',
      measurements: json['measurements'] as String?,
      rootCause: json['root_cause'] as String?,
      solutionDetails: json['solution_details'] as String?,
      validationResult: json['validation_result'] as String?,
      finalEquipmentStatus: json['final_equipment_status'] as String?,
      solutionConfidence:
          json['solution_confidence'] as String? ?? 'unconfirmed',
      progressEntries: progress,
      downtimeMinutes: (json['downtime_minutes'] as num?)?.toInt(),
      serviceMinutes: (json['service_minutes'] as num?)?.toInt(),
      requiresFollowUp: json['requires_follow_up'] as bool? ?? false,
      followUpNotes: json['follow_up_notes'] as String?,
      safetyNotes: json['safety_notes'] as String?,
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

  static List<Map<String, dynamic>> _listOfMaps(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}

class ServiceCaseDraft {
  const ServiceCaseDraft({
    required this.equipmentId,
    required this.reportedFailure,
    required this.status,
    required this.operationalImpact,
    required this.solutionConfidence,
    this.activityType = ServiceActivityType.maintenance,
    this.progressEntries = const [],
    this.id,
    this.observedSymptoms,
    this.errorCode,
    this.errorMessage,
    this.subsystem,
    this.measurements,
    this.rootCause,
    this.solutionDetails,
    this.validationResult,
    this.finalEquipmentStatus,
    this.downtimeMinutes,
    this.serviceMinutes,
    this.requiresFollowUp = false,
    this.followUpNotes,
    this.safetyNotes,
  });

  final String? id;
  final String equipmentId;
  final String reportedFailure;
  final String status;
  final String activityType;
  final String operationalImpact;
  final String solutionConfidence;
  final List<ServiceProgressEntry> progressEntries;
  final String? observedSymptoms;
  final String? errorCode;
  final String? errorMessage;
  final String? subsystem;
  final String? measurements;
  final String? rootCause;
  final String? solutionDetails;
  final String? validationResult;
  final String? finalEquipmentStatus;
  final int? downtimeMinutes;
  final int? serviceMinutes;
  final bool requiresFollowUp;
  final String? followUpNotes;
  final String? safetyNotes;
}

class SimilarCaseQuery {
  const SimilarCaseQuery({
    required this.text,
    this.equipmentId,
    this.errorCode,
    this.subsystem,
  });

  final String text;
  final String? equipmentId;
  final String? errorCode;
  final String? subsystem;
}

class SimilarCaseResult {
  const SimilarCaseResult({
    required this.serviceCase,
    required this.score,
    required this.reasons,
  });

  final ServiceCase serviceCase;
  final double score;
  final List<String> reasons;
}
