import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/service_case.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/status_chip.dart';
import '../shell/service_log_controller.dart';
import '../../shared/widgets/labeled_field.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.controller});
  final ServiceLogController controller;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _query = TextEditingController();
  final _errorCode = TextEditingController();
  final _subsystem = TextEditingController();
  String? _equipmentId;
  bool _searching = false;
  bool _searched = false;
  List<SimilarCaseResult> _results = const [];

  @override
  void dispose() {
    _query.dispose();
    _errorCode.dispose();
    _subsystem.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_query.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Descreva a falha com pelo menos 5 caracteres.'),
        ),
      );
      return;
    }
    setState(() {
      _searching = true;
      _searched = true;
    });
    try {
      final results = await widget.controller.search(
        SimilarCaseQuery(
          text: _query.text,
          equipmentId: _equipmentId,
          errorCode: _errorCode.text,
          subsystem: _subsystem.text,
        ),
      );
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SectionHeader(
          title: 'Assistente técnico',
          subtitle:
              'Recupere casos semelhantes e soluções já validadas pela sua própria equipe.',
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Descreva a falha atual',
                  child: TextFormField(
                    controller: _query,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText:
                          'Ex.: aquisição interrompe após 20 minutos; baixa dose funciona; temperatura elevada no módulo...',
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(bottom: 60),
                        child: Icon(Icons.auto_awesome_rounded),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fields = [
                      LabeledField(
                        label: 'Equipamento (opcional)',
                        child: DropdownButtonFormField<String>(
                          initialValue: _equipmentId ?? '',
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Qualquer equipamento'),
                            ),
                            ...widget.controller.equipment.map(
                              (item) => DropdownMenuItem<String>(
                                value: item.id,
                                child: Text(
                                  '${item.displayName} · ${item.serialLabel}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) => setState(
                            () => _equipmentId = value == null || value.isEmpty
                                ? null
                                : value,
                          ),
                        ),
                      ),
                      LabeledField(
                        label: 'Código de erro',
                        child: TextField(controller: _errorCode),
                      ),
                      LabeledField(
                        label: 'Subsistema',
                        child: TextField(controller: _subsystem),
                      ),
                    ];
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: [
                          for (var i = 0; i < fields.length; i++) ...[
                            fields[i],
                            if (i < fields.length - 1)
                              const SizedBox(height: 12),
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        for (var i = 0; i < fields.length; i++) ...[
                          Expanded(flex: i == 0 ? 2 : 1, child: fields[i]),
                          if (i < fields.length - 1) const SizedBox(width: 12),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final warning = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: context.orion.accent,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'As sugestões são evidências históricas, não procedimento oficial do fabricante nem diagnóstico autônomo.',
                            style: TextStyle(
                              color: context.orion.textMuted,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    );
                    final button = FilledButton.icon(
                      onPressed: _searching ? null : _search,
                      icon: _searching
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search_rounded),
                      label: Text(
                        _searching
                            ? 'Pesquisando...'
                            : 'Buscar casos semelhantes',
                      ),
                    );
                    if (constraints.maxWidth < 700) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [warning, const SizedBox(height: 14), button],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: warning),
                        const SizedBox(width: 20),
                        button,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (!_searched)
          const EmptyState(
            icon: Icons.manage_search_rounded,
            title: 'Pronto para pesquisar',
            message:
                'Descreva o comportamento observado. Quanto mais específico o registro, melhor será a recuperação dos casos.',
          )
        else if (_searching)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_results.isEmpty)
          const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Nenhum caso suficientemente semelhante',
            message:
                'Isso não significa que a falha seja inédita. Tente ampliar a descrição ou remover filtros específicos.',
          )
        else ...[
          Text(
            '${_results.length} casos recuperados',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ..._results.map(
            (result) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ResultCard(result: result),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final SimilarCaseResult result;

  @override
  Widget build(BuildContext context) {
    final item = result.serviceCase;
    final percentage = (result.score * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final heading = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Caso #${item.caseNumber}',
                          style: TextStyle(
                            color: context.orion.accent,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        StatusChip(
                          value: item.solutionConfidence,
                          compact: true,
                        ),
                        if (item.errorCode?.isNotEmpty == true)
                          _Tag(item.errorCode!),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.equipmentLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                );
                final score = Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: context.orion.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$percentage% similar',
                    style: TextStyle(
                      color: context.orion.emphasis,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                );
                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [heading, const SizedBox(height: 12), score],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 14),
                    score,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (result.explanation != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.orion.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: context.orion.emphasis,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result.explanation!,
                        style: TextStyle(
                          color: context.orion.emphasis,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            _EvidenceBlock(
              label: 'Falha registrada',
              text: item.reportedFailure,
            ),
            if (item.observedSymptoms?.isNotEmpty == true)
              _EvidenceBlock(label: 'Sintomas', text: item.observedSymptoms!),
            if (item.rootCause?.isNotEmpty == true)
              _EvidenceBlock(label: 'Causa-raiz', text: item.rootCause!),
            if (item.solutionDetails?.isNotEmpty == true)
              _EvidenceBlock(
                label: 'Solução aplicada',
                text: item.solutionDetails!,
              ),
            if (item.validationResult?.isNotEmpty == true)
              _EvidenceBlock(label: 'Validação', text: item.validationResult!),
            if (result.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: result.reasons.map(_Tag.new).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EvidenceBlock extends StatelessWidget {
  const _EvidenceBlock({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: context.orion.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(text, style: const TextStyle(height: 1.42)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: context.orion.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.orion.border),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
