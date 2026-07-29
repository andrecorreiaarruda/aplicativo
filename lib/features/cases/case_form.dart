import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/equipment.dart';
import '../../data/models/service_case.dart';
import '../shell/service_log_controller.dart';

class CaseForm extends StatefulWidget {
  const CaseForm({super.key, required this.controller, this.initialCase});

  final ServiceLogController controller;
  final ServiceCase? initialCase;

  @override
  State<CaseForm> createState() => _CaseFormState();
}

class _CaseFormState extends State<CaseForm> {
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _failure;
  late final TextEditingController _symptoms;
  late final TextEditingController _errorCode;
  late final TextEditingController _errorMessage;
  late final TextEditingController _subsystem;
  late final TextEditingController _measurements;
  late final TextEditingController _rootCause;
  late final TextEditingController _solution;
  late final TextEditingController _validation;
  late final TextEditingController _downtime;
  late final TextEditingController _serviceTime;
  late final TextEditingController _followUpNotes;
  late final TextEditingController _safetyNotes;
  late final TextEditingController _progressNote;
  late List<ServiceProgressEntry> _progressEntries;

  String? _equipmentId;
  String _activityType = ServiceActivityType.maintenance;
  String _status = 'open';
  String _impact = 'degraded';
  String _confidence = 'unconfirmed';
  String _finalStatus = 'operational';
  bool _requiresFollowUp = false;
  int _step = 0;

  bool get _resolving => _status == 'resolved';
  _ActivityCopy get _copy => _ActivityCopy.forType(_activityType);

  @override
  void initState() {
    super.initState();
    final item = widget.initialCase;
    _equipmentId = item?.equipmentId;
    _activityType = item?.activityType ?? ServiceActivityType.maintenance;
    _status = item?.status ?? 'open';
    _impact = item?.operationalImpact ?? 'degraded';
    _confidence = item?.solutionConfidence ?? 'unconfirmed';
    _finalStatus =
        item?.finalEquipmentStatus ??
        (_activityType == ServiceActivityType.deinstallation
            ? 'decommissioned'
            : 'operational');
    _requiresFollowUp = item?.requiresFollowUp ?? false;
    _progressEntries = List<ServiceProgressEntry>.from(
      item?.progressEntries ?? const [],
    );
    _failure = TextEditingController(text: item?.reportedFailure ?? '');
    _symptoms = TextEditingController(text: item?.observedSymptoms ?? '');
    _errorCode = TextEditingController(text: item?.errorCode ?? '');
    _errorMessage = TextEditingController(text: item?.errorMessage ?? '');
    _subsystem = TextEditingController(text: item?.subsystem ?? '');
    _measurements = TextEditingController(text: item?.measurements ?? '');
    _rootCause = TextEditingController(text: item?.rootCause ?? '');
    _solution = TextEditingController(text: item?.solutionDetails ?? '');
    _validation = TextEditingController(text: item?.validationResult ?? '');
    _downtime = TextEditingController(
      text: item?.downtimeMinutes?.toString() ?? '',
    );
    _serviceTime = TextEditingController(
      text: item?.serviceMinutes?.toString() ?? '',
    );
    _followUpNotes = TextEditingController(text: item?.followUpNotes ?? '');
    _safetyNotes = TextEditingController(text: item?.safetyNotes ?? '');
    _progressNote = TextEditingController();
  }

  @override
  void dispose() {
    for (final controller in [
      _failure,
      _symptoms,
      _errorCode,
      _errorMessage,
      _subsystem,
      _measurements,
      _rootCause,
      _solution,
      _validation,
      _downtime,
      _serviceTime,
      _followUpNotes,
      _safetyNotes,
      _progressNote,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changeActivity(String value) {
    setState(() {
      _activityType = value;
      if (widget.initialCase == null) {
        _impact = value == ServiceActivityType.maintenance
            ? 'degraded'
            : 'none';
        _finalStatus = value == ServiceActivityType.deinstallation
            ? 'decommissioned'
            : 'operational';
      }
    });
  }

  void _addProgressEntry() {
    final description = _progressNote.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Descreva o andamento antes de adicionar.'),
        ),
      );
      return;
    }
    setState(() {
      _progressEntries.add(
        ServiceProgressEntry(
          id: _uuid.v4(),
          occurredAt: DateTime.now(),
          description: description,
        ),
      );
      _progressNote.clear();
    });
  }

  void _appendPendingProgress() {
    final description = _progressNote.text.trim();
    if (description.isEmpty) return;
    _progressEntries.add(
      ServiceProgressEntry(
        id: _uuid.v4(),
        occurredAt: DateTime.now(),
        description: description,
      ),
    );
    _progressNote.clear();
  }

  Future<void> _save() async {
    if (_equipmentId == null || _failure.text.trim().isEmpty) {
      setState(() => _step = 0);
      _formKey.currentState!.validate();
      return;
    }
    if (_resolving &&
        (_solution.text.trim().isEmpty || _validation.text.trim().isEmpty)) {
      setState(() => _step = 2);
      _formKey.currentState!.validate();
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    _appendPendingProgress();
    final ok = await widget.controller.saveCase(
      ServiceCaseDraft(
        id: widget.initialCase?.id,
        equipmentId: _equipmentId!,
        activityType: _activityType,
        reportedFailure: _failure.text,
        status: _status,
        operationalImpact: _impact,
        solutionConfidence: _confidence,
        progressEntries: List.unmodifiable(_progressEntries),
        observedSymptoms: _symptoms.text,
        errorCode: _errorCode.text,
        errorMessage: _errorMessage.text,
        subsystem: _subsystem.text,
        measurements: _measurements.text,
        rootCause: _rootCause.text,
        solutionDetails: _solution.text,
        validationResult: _validation.text,
        finalEquipmentStatus: _finalStatus,
        downtimeMinutes: int.tryParse(_downtime.text.trim()),
        serviceMinutes: int.tryParse(_serviceTime.text.trim()),
        requiresFollowUp: _requiresFollowUp,
        followUpNotes: _followUpNotes.text,
        safetyNotes: _safetyNotes.text,
      ),
    );
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.initialCase == null
                          ? 'Novo atendimento técnico'
                          : 'Atendimento #${widget.initialCase!.caseNumber}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${ServiceActivityType.label(_activityType)} com histórico contínuo no mesmo atendimento.',
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Form(
            key: _formKey,
            child: Stepper(
              currentStep: _step,
              onStepTapped: (value) => setState(() => _step = value),
              onStepContinue: () {
                if (_step < 2) setState(() => _step++);
              },
              onStepCancel: () {
                if (_step > 0) setState(() => _step--);
              },
              controlsBuilder: (context, details) {
                return Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Row(
                    children: [
                      if (_step < 2)
                        FilledButton(
                          onPressed: details.onStepContinue,
                          child: const Text('Continuar'),
                        ),
                      if (_step > 0) ...[
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: details.onStepCancel,
                          child: const Text('Voltar'),
                        ),
                      ],
                    ],
                  ),
                );
              },
              steps: [
                Step(
                  title: const Text('Abertura'),
                  subtitle: Text(_copy.openingSubtitle),
                  isActive: _step >= 0,
                  content: _OpeningStep(
                    equipment: widget.controller.equipment,
                    equipmentId: _equipmentId,
                    activityType: _activityType,
                    copy: _copy,
                    failure: _failure,
                    errorCode: _errorCode,
                    errorMessage: _errorMessage,
                    subsystem: _subsystem,
                    status: _status,
                    impact: _impact,
                    onEquipmentChanged: (value) =>
                        setState(() => _equipmentId = value),
                    onActivityChanged: _changeActivity,
                    onStatusChanged: (value) => setState(() => _status = value),
                    onImpactChanged: (value) => setState(() => _impact = value),
                  ),
                ),
                Step(
                  title: Text(_copy.executionStepTitle),
                  subtitle: const Text(
                    'Registros cumulativos por dia de trabalho',
                  ),
                  isActive: _step >= 1,
                  content: _ExecutionStep(
                    copy: _copy,
                    symptoms: _symptoms,
                    measurements: _measurements,
                    rootCause: _rootCause,
                    safetyNotes: _safetyNotes,
                    progressNote: _progressNote,
                    entries: _progressEntries,
                    onAddEntry: _addProgressEntry,
                    onRemoveEntry: (entry) {
                      setState(() => _progressEntries.remove(entry));
                    },
                  ),
                ),
                Step(
                  title: Text(_copy.conclusionStepTitle),
                  subtitle: Text(_copy.conclusionSubtitle),
                  isActive: _step >= 2,
                  content: _ConclusionStep(
                    copy: _copy,
                    resolving: _resolving,
                    solution: _solution,
                    validation: _validation,
                    downtime: _downtime,
                    serviceTime: _serviceTime,
                    followUpNotes: _followUpNotes,
                    confidence: _confidence,
                    finalStatus: _finalStatus,
                    requiresFollowUp: _requiresFollowUp,
                    onConfidenceChanged: (value) =>
                        setState(() => _confidence = value),
                    onFinalStatusChanged: (value) =>
                        setState(() => _finalStatus = value),
                    onFollowUpChanged: (value) =>
                        setState(() => _requiresFollowUp = value),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.controller.saving
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: widget.controller.saving ? null : _save,
                icon: widget.controller.saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _resolving ? 'Concluir atendimento' : 'Salvar andamento',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OpeningStep extends StatelessWidget {
  const _OpeningStep({
    required this.equipment,
    required this.equipmentId,
    required this.activityType,
    required this.copy,
    required this.failure,
    required this.errorCode,
    required this.errorMessage,
    required this.subsystem,
    required this.status,
    required this.impact,
    required this.onEquipmentChanged,
    required this.onActivityChanged,
    required this.onStatusChanged,
    required this.onImpactChanged,
  });

  final List<Equipment> equipment;
  final String? equipmentId;
  final String activityType;
  final _ActivityCopy copy;
  final TextEditingController failure;
  final TextEditingController errorCode;
  final TextEditingController errorMessage;
  final TextEditingController subsystem;
  final String status;
  final String impact;
  final ValueChanged<String?> onEquipmentChanged;
  final ValueChanged<String> onActivityChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onImpactChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: activityType,
          decoration: const InputDecoration(
            labelText: 'Classificação do atendimento',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: ServiceActivityType.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(ServiceActivityType.label(value)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onActivityChanged(value);
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: equipmentId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Equipamento'),
          items: equipment
              .map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(
                    '${item.displayName} · ${item.serialNumber}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onEquipmentChanged,
          validator: (value) =>
              value == null ? 'Selecione o equipamento.' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: failure,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: copy.primaryFieldLabel,
            hintText: copy.primaryFieldHint,
          ),
          validator: (value) => value?.trim().isEmpty ?? true
              ? copy.primaryFieldValidation
              : null,
        ),
        const SizedBox(height: 14),
        _AdaptiveFields(
          children: [
            TextFormField(
              controller: errorCode,
              decoration: InputDecoration(labelText: copy.referenceLabel),
            ),
            TextFormField(
              controller: subsystem,
              decoration: InputDecoration(labelText: copy.subsystemLabel),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: errorMessage,
          maxLines: 2,
          decoration: InputDecoration(labelText: copy.initialNotesLabel),
        ),
        const SizedBox(height: 14),
        _AdaptiveFields(
          children: [
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Situação'),
              items: const [
                DropdownMenuItem(value: 'open', child: Text('Aberto')),
                DropdownMenuItem(
                  value: 'diagnosing',
                  child: Text('Em andamento'),
                ),
                DropdownMenuItem(
                  value: 'waiting_parts',
                  child: Text('Aguardando peça / material'),
                ),
                DropdownMenuItem(
                  value: 'waiting_customer',
                  child: Text('Aguardando cliente / local'),
                ),
                DropdownMenuItem(value: 'resolved', child: Text('Concluído')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelado')),
              ],
              onChanged: (value) => onStatusChanged(value!),
            ),
            DropdownButtonFormField<String>(
              initialValue: impact,
              decoration: InputDecoration(labelText: copy.impactLabel),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Sem impacto')),
                DropdownMenuItem(
                  value: 'degraded',
                  child: Text('Operação degradada'),
                ),
                DropdownMenuItem(
                  value: 'partial_stop',
                  child: Text('Parada parcial'),
                ),
                DropdownMenuItem(
                  value: 'total_stop',
                  child: Text('Parada total'),
                ),
              ],
              onChanged: (value) => onImpactChanged(value!),
            ),
          ],
        ),
      ],
    );
  }
}

class _ExecutionStep extends StatelessWidget {
  const _ExecutionStep({
    required this.copy,
    required this.symptoms,
    required this.measurements,
    required this.rootCause,
    required this.safetyNotes,
    required this.progressNote,
    required this.entries,
    required this.onAddEntry,
    required this.onRemoveEntry,
  });

  final _ActivityCopy copy;
  final TextEditingController symptoms;
  final TextEditingController measurements;
  final TextEditingController rootCause;
  final TextEditingController safetyNotes;
  final TextEditingController progressNote;
  final List<ServiceProgressEntry> entries;
  final VoidCallback onAddEntry;
  final ValueChanged<ServiceProgressEntry> onRemoveEntry;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final orderedEntries = [...entries]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: symptoms,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: copy.executionSummaryLabel,
            hintText: copy.executionSummaryHint,
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: measurements,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: copy.measurementsLabel,
            hintText: copy.measurementsHint,
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: rootCause,
          maxLines: 3,
          decoration: InputDecoration(labelText: copy.deviationLabel),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: safetyNotes,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Notas de segurança',
            hintText: 'Bloqueios, riscos elétricos, mecânicos ou radiológicos.',
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Diário de andamento',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Adicione quantos registros forem necessários. Eles permanecerão vinculados ao mesmo atendimento até sua conclusão.',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: progressNote,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: copy.progressEntryLabel,
            hintText: copy.progressEntryHint,
            suffixIcon: IconButton(
              tooltip: 'Adicionar ao diário',
              onPressed: onAddEntry,
              icon: const Icon(Icons.add_task_rounded),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: onAddEntry,
            icon: const Icon(Icons.playlist_add_rounded),
            label: const Text('Adicionar registro ao diário'),
          ),
        ),
        if (orderedEntries.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...orderedEntries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.event_note_outlined),
                  title: Text(
                    dateFormat.format(entry.occurredAt),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(entry.description),
                  ),
                  trailing: IconButton(
                    tooltip: 'Remover registro',
                    onPressed: () => onRemoveEntry(entry),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConclusionStep extends StatelessWidget {
  const _ConclusionStep({
    required this.copy,
    required this.resolving,
    required this.solution,
    required this.validation,
    required this.downtime,
    required this.serviceTime,
    required this.followUpNotes,
    required this.confidence,
    required this.finalStatus,
    required this.requiresFollowUp,
    required this.onConfidenceChanged,
    required this.onFinalStatusChanged,
    required this.onFollowUpChanged,
  });

  final _ActivityCopy copy;
  final bool resolving;
  final TextEditingController solution;
  final TextEditingController validation;
  final TextEditingController downtime;
  final TextEditingController serviceTime;
  final TextEditingController followUpNotes;
  final String confidence;
  final String finalStatus;
  final bool requiresFollowUp;
  final ValueChanged<String> onConfidenceChanged;
  final ValueChanged<String> onFinalStatusChanged;
  final ValueChanged<bool> onFollowUpChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: solution,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: copy.solutionLabel,
            hintText: copy.solutionHint,
          ),
          validator: (value) => resolving && (value?.trim().isEmpty ?? true)
              ? copy.solutionValidation
              : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: validation,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: copy.validationLabel,
            hintText: copy.validationHint,
          ),
          validator: (value) => resolving && (value?.trim().isEmpty ?? true)
              ? copy.validationValidation
              : null,
        ),
        const SizedBox(height: 14),
        _AdaptiveFields(
          children: [
            DropdownButtonFormField<String>(
              initialValue: confidence,
              decoration: InputDecoration(labelText: copy.confidenceLabel),
              items: const [
                DropdownMenuItem(
                  value: 'unconfirmed',
                  child: Text('Não confirmada'),
                ),
                DropdownMenuItem(value: 'probable', child: Text('Provável')),
                DropdownMenuItem(value: 'confirmed', child: Text('Confirmada')),
                DropdownMenuItem(value: 'recurring', child: Text('Recorrente')),
                DropdownMenuItem(value: 'reviewed', child: Text('Revisada')),
                DropdownMenuItem(value: 'obsolete', child: Text('Obsoleta')),
              ],
              onChanged: (value) => onConfidenceChanged(value!),
            ),
            DropdownButtonFormField<String>(
              initialValue: finalStatus,
              decoration: const InputDecoration(labelText: 'Condição final'),
              items: const [
                DropdownMenuItem(
                  value: 'operational',
                  child: Text('Operacional'),
                ),
                DropdownMenuItem(value: 'degraded', child: Text('Degradado')),
                DropdownMenuItem(value: 'stopped', child: Text('Parado')),
                DropdownMenuItem(
                  value: 'decommissioned',
                  child: Text('Desativado / removido'),
                ),
              ],
              onChanged: (value) => onFinalStatusChanged(value!),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _AdaptiveFields(
          children: [
            TextFormField(
              controller: downtime,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Máquina indisponível (min)',
              ),
              validator: _nonNegativeInteger,
            ),
            TextFormField(
              controller: serviceTime,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Tempo técnico (min)',
              ),
              validator: _nonNegativeInteger,
            ),
          ],
        ),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: requiresFollowUp,
          onChanged: onFollowUpChanged,
          title: Text(copy.followUpLabel),
        ),
        if (requiresFollowUp)
          TextFormField(
            controller: followUpNotes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Plano de acompanhamento / próxima etapa',
            ),
          ),
      ],
    );
  }

  static String? _nonNegativeInteger(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) {
      return 'Informe um número inteiro positivo.';
    }
    return null;
  }
}

class _AdaptiveFields extends StatelessWidget {
  const _AdaptiveFields({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index < children.length - 1) const SizedBox(height: 14),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index < children.length - 1) const SizedBox(width: 14),
            ],
          ],
        );
      },
    );
  }
}

class _ActivityCopy {
  const _ActivityCopy({
    required this.openingSubtitle,
    required this.primaryFieldLabel,
    required this.primaryFieldHint,
    required this.primaryFieldValidation,
    required this.referenceLabel,
    required this.subsystemLabel,
    required this.initialNotesLabel,
    required this.impactLabel,
    required this.executionStepTitle,
    required this.executionSummaryLabel,
    required this.executionSummaryHint,
    required this.measurementsLabel,
    required this.measurementsHint,
    required this.deviationLabel,
    required this.progressEntryLabel,
    required this.progressEntryHint,
    required this.conclusionStepTitle,
    required this.conclusionSubtitle,
    required this.solutionLabel,
    required this.solutionHint,
    required this.solutionValidation,
    required this.validationLabel,
    required this.validationHint,
    required this.validationValidation,
    required this.confidenceLabel,
    required this.followUpLabel,
  });

  final String openingSubtitle;
  final String primaryFieldLabel;
  final String primaryFieldHint;
  final String primaryFieldValidation;
  final String referenceLabel;
  final String subsystemLabel;
  final String initialNotesLabel;
  final String impactLabel;
  final String executionStepTitle;
  final String executionSummaryLabel;
  final String executionSummaryHint;
  final String measurementsLabel;
  final String measurementsHint;
  final String deviationLabel;
  final String progressEntryLabel;
  final String progressEntryHint;
  final String conclusionStepTitle;
  final String conclusionSubtitle;
  final String solutionLabel;
  final String solutionHint;
  final String solutionValidation;
  final String validationLabel;
  final String validationHint;
  final String validationValidation;
  final String confidenceLabel;
  final String followUpLabel;

  static _ActivityCopy forType(String type) {
    switch (type) {
      case ServiceActivityType.installation:
        return const _ActivityCopy(
          openingSubtitle: 'Equipamento, escopo e condição inicial',
          primaryFieldLabel: 'Escopo da instalação',
          primaryFieldHint:
              'Descreva o equipamento, acessórios, responsabilidades e objetivo da instalação.',
          primaryFieldValidation: 'Informe o escopo da instalação.',
          referenceLabel: 'Projeto / OS / referência (opcional)',
          subsystemLabel: 'Conjunto / área principal (opcional)',
          initialNotesLabel: 'Condição inicial e pré-requisitos',
          impactLabel: 'Impacto durante a instalação',
          executionStepTitle: 'Execução',
          executionSummaryLabel: 'Etapas executadas',
          executionSummaryHint:
              'Montagem, posicionamento, conexões, energização e configurações realizadas.',
          measurementsLabel: 'Testes, medições e comissionamento',
          measurementsHint:
              'Registre valores, calibrações, testes funcionais e critérios de aceite.',
          deviationLabel: 'Pendências, desvios ou interferências',
          progressEntryLabel: 'Andamento do dia',
          progressEntryHint:
              'Ex.: Posicionada a gantry, instalados cabos e iniciada energização.',
          conclusionStepTitle: 'Conclusão',
          conclusionSubtitle: 'Comissionamento, aceite e liberação',
          solutionLabel: 'Configuração e serviços concluídos',
          solutionHint:
              'Resuma a montagem final, configurações, calibrações e condições de entrega.',
          solutionValidation: 'Informe o resultado final da instalação.',
          validationLabel: 'Testes de aceitação e liberação',
          validationHint:
              'Descreva testes aprovados, pendências e responsável pelo aceite.',
          validationValidation: 'Informe os testes finais da instalação.',
          confidenceLabel: 'Confiabilidade do registro',
          followUpLabel: 'Necessita retorno, treinamento ou etapa complementar',
        );
      case ServiceActivityType.deinstallation:
        return const _ActivityCopy(
          openingSubtitle: 'Equipamento, escopo e condição antes da retirada',
          primaryFieldLabel: 'Escopo da desinstalação',
          primaryFieldHint:
              'Descreva o que será removido, embalado, transportado ou entregue.',
          primaryFieldValidation: 'Informe o escopo da desinstalação.',
          referenceLabel: 'Projeto / OS / destino (opcional)',
          subsystemLabel: 'Conjunto / área principal (opcional)',
          initialNotesLabel: 'Condição inicial e inventário preliminar',
          impactLabel: 'Impacto durante a retirada',
          executionStepTitle: 'Execução',
          executionSummaryLabel: 'Etapas de desligamento e desmontagem',
          executionSummaryHint:
              'Bloqueios, desconexões, desmontagem, identificação e embalagem realizadas.',
          measurementsLabel: 'Conferências, inventário e condição dos itens',
          measurementsHint:
              'Registre quantidades, integridade, volumes, acessórios e evidências.',
          deviationLabel: 'Avarias, faltas ou ocorrências',
          progressEntryLabel: 'Andamento do dia',
          progressEntryHint:
              'Ex.: Sistema desenergizado, detector removido e embalado no volume 03.',
          conclusionStepTitle: 'Conclusão',
          conclusionSubtitle: 'Embalagem, entrega e condição final',
          solutionLabel: 'Desmontagem, embalagem e destino final',
          solutionHint:
              'Resuma o que foi removido, identificado, embalado e entregue.',
          solutionValidation: 'Informe o resultado final da desinstalação.',
          validationLabel: 'Conferência final e entrega',
          validationHint:
              'Registre volumes, responsáveis, ressalvas e condição do local.',
          validationValidation: 'Informe a conferência final da desinstalação.',
          confidenceLabel: 'Confiabilidade do registro',
          followUpLabel: 'Necessita retorno, coleta ou etapa complementar',
        );
      default:
        return const _ActivityCopy(
          openingSubtitle: 'Equipamento e falha relatada',
          primaryFieldLabel: 'Falha relatada',
          primaryFieldHint:
              'Descreva o relato do cliente, quando começou e o impacto percebido.',
          primaryFieldValidation: 'Informe a falha relatada.',
          referenceLabel: 'Código de erro (opcional)',
          subsystemLabel: 'Subsistema (opcional)',
          initialNotesLabel: 'Mensagem de erro / observações iniciais',
          impactLabel: 'Impacto operacional',
          executionStepTitle: 'Diagnóstico',
          executionSummaryLabel: 'Sintomas observados',
          executionSummaryHint:
              'Condições de ocorrência, intermitência, sequência e reprodução.',
          measurementsLabel: 'Testes e medições',
          measurementsHint:
              'Ação executada, valor medido, unidade e resultado.',
          deviationLabel: 'Causa-raiz ou hipótese atual',
          progressEntryLabel: 'Andamento técnico do dia',
          progressEntryHint:
              'Ex.: Coletados logs, inspecionadas fontes e reproduzida a falha após 20 minutos.',
          conclusionStepTitle: 'Conclusão',
          conclusionSubtitle: 'Solução, validação e retorno',
          solutionLabel: 'Solução aplicada',
          solutionHint:
              'Descreva peças, ajustes, configurações e sequência executada.',
          solutionValidation: 'A solução é obrigatória para concluir.',
          validationLabel: 'Validação final',
          validationHint:
              'Testes funcionais, ciclos, calibrações e critérios de aceite.',
          validationValidation: 'A validação é obrigatória para concluir.',
          confidenceLabel: 'Confiança da solução',
          followUpLabel: 'Necessita retorno ou acompanhamento',
        );
    }
  }
}
