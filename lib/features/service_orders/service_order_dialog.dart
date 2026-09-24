import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/equipment.dart';
import '../../data/models/service_case.dart';
import '../../shared/widgets/labeled_field.dart';
import '../shell/service_log_controller.dart';
import 'issuer_dialog.dart';
import 'service_order.dart';
import 'service_order_archive.dart';
import 'service_order_details.dart';
import 'service_order_issuer.dart';
import 'service_order_pdf.dart';

/// Equipamento, local e cliente do atendimento, como o controlador os
/// conhece. Qualquer um pode faltar.
({Equipment? equipment, SiteOption? site, CustomerOption? customer})
lookupServiceOrderContext(ServiceLogController controller, ServiceCase item) {
  Equipment? equipment;
  for (final candidate in controller.equipment) {
    if (candidate.id == item.equipmentId) equipment = candidate;
  }
  SiteOption? site;
  for (final candidate in controller.catalog.sites) {
    if (candidate.id == equipment?.siteId) site = candidate;
  }
  CustomerOption? customer;
  for (final candidate in controller.catalog.customers) {
    if (candidate.id == site?.customerId) customer = candidate;
  }
  return (equipment: equipment, site: site, customer: customer);
}

/// Janela da OS de um atendimento: complementos, emissão e emitidas.
///
/// Devolve verdadeiro se alguma OS foi emitida, para a lista de
/// atendimentos atualizar a marca de "OS emitida".
Future<bool> showServiceOrderDialog(
  BuildContext context, {
  required ServiceLogController controller,
  required ServiceCase item,
}) async {
  final archive = ServiceOrderScope.maybeOf(context);
  if (archive == null) return false;
  final issued = await showDialog<bool>(
    context: context,
    // Um toque fora não pode descartar o que foi digitado.
    barrierDismissible: false,
    builder: (_) => _ServiceOrderDialog(
      archive: archive,
      controller: controller,
      item: item,
    ),
  );
  return issued ?? false;
}

class _MaterialRow {
  _MaterialRow([ServiceOrderMaterial material = const ServiceOrderMaterial()])
    : description = TextEditingController(text: material.description),
      partNumber = TextEditingController(text: material.partNumber),
      quantity = TextEditingController(text: material.quantity),
      warranty = TextEditingController(text: material.warranty);

  final TextEditingController description;
  final TextEditingController partNumber;
  final TextEditingController quantity;
  final TextEditingController warranty;

  ServiceOrderMaterial get value => ServiceOrderMaterial(
    description: description.text.trim(),
    partNumber: partNumber.text.trim(),
    quantity: quantity.text.trim(),
    warranty: warranty.text.trim(),
  );

  void dispose() {
    description.dispose();
    partNumber.dispose();
    quantity.dispose();
    warranty.dispose();
  }
}

class _ServiceOrderDialog extends StatefulWidget {
  const _ServiceOrderDialog({
    required this.archive,
    required this.controller,
    required this.item,
  });

  final ServiceOrderArchive archive;
  final ServiceLogController controller;
  final ServiceCase item;

  @override
  State<_ServiceOrderDialog> createState() => _ServiceOrderDialogState();
}

class _ServiceOrderDialogState extends State<_ServiceOrderDialog> {
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm');

  final _requester = TextEditingController();
  final _sector = TextEditingController();
  final _assetTag = TextEditingController();
  final _recommendations = TextEditingController();
  final _materials = <_MaterialRow>[];
  Set<ServiceOrderCheck> _checks = {};
  ServiceOrderSituation? _situation;

  ServiceOrderIssuer _issuer = ServiceOrderIssuer.empty;
  List<IssuedServiceOrder> _issued = const [];
  Set<String> _missing = const {};
  String? _folder;
  bool _provisional = false;
  bool _loading = true;
  bool _busy = false;
  bool _issuedSomething = false;
  String? _error;

  /// O atendimento como está agora no controlador. A lista pode ter sido
  /// recarregada — por uma sincronização, por exemplo — desde que a
  /// janela abriu, e a OS deve sair com os dados mais novos.
  ServiceCase get _item {
    for (final candidate in widget.controller.cases) {
      if (candidate.id == widget.item.id) return candidate;
    }
    return widget.item;
  }

  ServiceOrderDetails get _details => ServiceOrderDetails(
    requester: _requester.text.trim(),
    sector: _sector.text.trim(),
    assetTag: _assetTag.text.trim(),
    materials: [
      for (final row in _materials)
        if (!row.value.isEmpty) row.value,
    ],
    checks: _checks,
    situation: _situation,
    recommendations: _recommendations.text.trim(),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requester.dispose();
    _sector.dispose();
    _assetTag.dispose();
    _recommendations.dispose();
    for (final row in _materials) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final saved = await widget.archive.loadDetails(widget.item.id);
      final lookup = lookupServiceOrderContext(widget.controller, _item);
      final details =
          saved ??
          ServiceOrderDetails.suggest(
            item: _item,
            equipment: lookup.equipment,
            site: lookup.site,
            customer: lookup.customer,
          );
      _issuer = await widget.archive.loadIssuer();
      _requester.text = details.requester;
      _sector.text = details.sector;
      _assetTag.text = details.assetTag;
      _recommendations.text = details.recommendations;
      _materials.addAll(details.materials.map(_MaterialRow.new));
      _checks = {...details.checks};
      _situation = details.situation;
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível abrir a OS: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Emitidas, arquivos presentes e número provisório.
  Future<void> _refresh() async {
    final files = widget.archive.files;
    final issued = await widget.archive.issuedFor(widget.item.id);
    final missing = <String>{
      for (final entry in issued)
        if (!await files.exists(entry.path)) entry.path,
    };
    final provisional = await widget.controller.isCaseNumberProvisional(
      widget.item.id,
    );
    String? folder;
    try {
      folder = await files.folderPath();
    } on UnsupportedError {
      folder = null;
    }
    if (!mounted) return;
    setState(() {
      _issued = issued;
      _missing = missing;
      _provisional = provisional;
      _folder = folder;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on UnsupportedError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _issue() => _run(() async {
    final item = _item;
    final details = _details;
    await widget.archive.saveDetails(item.id, details);
    final lookup = lookupServiceOrderContext(widget.controller, item);
    final order = ServiceOrder.assemble(
      item: item,
      equipment: lookup.equipment,
      site: lookup.site,
      customer: lookup.customer,
      issuer: _issuer,
      details: details,
      issuedAt: DateTime.now(),
    );
    final bytes = await buildServiceOrderPdf(
      order,
      await ServiceOrderAssets.load(),
    );
    final issued = await widget.archive.record(
      caseId: item.id,
      fileName: order.fileName,
      bytes: bytes,
      issuedAt: order.issuedAt,
    );
    _issuedSomething = true;
    await _refresh();
    // Abre na hora: quem acabou de emitir quer conferir antes de enviar.
    await widget.archive.files.open(issued.path);
  });

  Future<void> _sync() => _run(() async {
    await widget.controller.syncNow();
    await _refresh();
  });

  Future<void> _editIssuer() async {
    final saved = await showIssuerDialog(context);
    if (saved != null && mounted) setState(() => _issuer = saved);
  }

  /// Fechar guarda os complementos mesmo sem emitir: preencher metade
  /// hoje e emitir amanhã é o uso normal.
  Future<void> _close() async {
    if (!_loading) {
      try {
        await widget.archive.saveDetails(widget.item.id, _details);
      } catch (error) {
        debugPrint('ORION: complementos da OS não salvos: $error');
      }
    }
    if (mounted) Navigator.of(context).pop(_issuedSomething);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final palette = context.orion;
    final canIssue = !_loading && !_busy && !_provisional && _issuer.isComplete;

    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text('Ordem de serviço · OS ${item.caseNumber}'),
      content: SizedBox(
        width: 760,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._notices(item, palette),
                    _heading(context, 'Complementos da OS'),
                    Text(
                      'O resto vem do atendimento. O que for preenchido aqui '
                      'fica guardado para a próxima emissão.',
                      style: TextStyle(color: palette.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    _pair(
                      _field('Solicitante', _requester),
                      _field('Setor', _sector),
                    ),
                    const SizedBox(height: 12),
                    _pair(
                      _field('Patrimônio', _assetTag),
                      const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 18),
                    _heading(context, 'Materiais aplicados'),
                    ..._materialRows(palette),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _materials.add(_MaterialRow())),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Adicionar material'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _heading(context, 'Testes e verificações finais'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final check in ServiceOrderCheck.values)
                          FilterChip(
                            label: Text(check.label),
                            selected: _checks.contains(check),
                            onSelected: (selected) => setState(() {
                              _checks = {..._checks};
                              selected
                                  ? _checks.add(check)
                                  : _checks.remove(check);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _heading(context, 'Situação final'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final situation in ServiceOrderSituation.values)
                          ChoiceChip(
                            label: Text(situation.label),
                            selected: _situation == situation,
                            // Tocar de novo desmarca: a OS pode sair sem
                            // situação, para marcar à mão.
                            onSelected: (selected) => setState(
                              () => _situation = selected ? situation : null,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _field('Recomendações', _recommendations, lines: 3),
                    const SizedBox(height: 22),
                    _heading(context, 'Emitidas neste computador'),
                    if (_issued.isEmpty)
                      Text(
                        'Nenhuma OS emitida ainda para este atendimento.',
                        style: TextStyle(color: palette.textMuted),
                      )
                    else
                      for (final entry in _issued)
                        _IssuedTile(
                          entry: entry,
                          label: _dateTime.format(entry.issuedAt),
                          missing: _missing.contains(entry.path),
                          onOpen: _busy
                              ? null
                              : () => _run(
                                  () => widget.archive.files.open(entry.path),
                                ),
                        ),
                    if (_folder != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Os arquivos ficam em $_folder',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(widget.archive.files.openFolder),
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('Abrir pasta'),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: TextStyle(color: palette.danger)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _close,
          child: const Text('Fechar'),
        ),
        FilledButton.icon(
          onPressed: canIssue ? _issue : null,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_issued.isEmpty ? 'Emitir OS' : 'Emitir nova versão'),
        ),
      ],
    );
  }

  List<Widget> _notices(ServiceCase item, OrionPalette palette) {
    final openSession = item.progressEntries.any((entry) => entry.isOpen);
    final notices = <Widget>[
      if (!_issuer.isComplete)
        _Notice(
          color: palette.warning,
          icon: Icons.badge_outlined,
          text:
              'Preencha os dados do emitente — empresa e responsável técnico '
              '— antes da primeira OS. Eles saem no rodapé e na assinatura.',
          action: TextButton.icon(
            onPressed: _busy ? null : _editIssuer,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Dados do emitente'),
          ),
        ),
      if (_provisional)
        _Notice(
          color: palette.warning,
          icon: Icons.sync_problem_rounded,
          text:
              'Este atendimento foi criado neste computador e ainda não passou '
              'pelo servidor. O número ${item.caseNumber} é provisório e pode '
              'mudar ao sincronizar. Sincronize antes de emitir, para a OS não '
              'sair com um número que depois deixa de existir.',
          action: TextButton.icon(
            onPressed: _busy ? null : _sync,
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Sincronizar agora'),
          ),
        )
      else if (!item.isResolved)
        _Notice(
          color: palette.accent,
          icon: Icons.info_outline_rounded,
          text:
              'O atendimento ainda não foi concluído. A OS sai só com o que já '
              'foi registrado, e sem término.',
        ),
      if (!_provisional && openSession)
        _Notice(
          color: palette.accent,
          icon: Icons.timer_outlined,
          text:
              'Há uma sessão de trabalho em aberto. O término da OS usa o fim '
              'da última sessão encerrada.',
        ),
    ];
    return [
      for (final notice in notices) ...[notice, const SizedBox(height: 10)],
      if (notices.isNotEmpty) const SizedBox(height: 6),
    ];
  }

  List<Widget> _materialRows(OrionPalette palette) {
    if (_materials.isEmpty) {
      return [
        Text(
          'Nenhum material. A OS sai com "Nenhum material aplicado."',
          style: TextStyle(color: palette.textMuted),
        ),
      ];
    }
    return [
      for (final (index, row) in _materials.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final remove = IconButton(
                tooltip: 'Remover material',
                onPressed: () => setState(() {
                  _materials.removeAt(index).dispose();
                }),
                icon: const Icon(Icons.delete_outline_rounded),
              );
              final description = _field(
                index == 0 ? 'Descrição' : null,
                row.description,
              );
              final rest = [
                _field(index == 0 ? 'Código / PN' : null, row.partNumber),
                _field(index == 0 ? 'Qtd.' : null, row.quantity),
                _field(index == 0 ? 'Garantia' : null, row.warranty),
              ];
              if (constraints.maxWidth < 620) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: description),
                        remove,
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(flex: 3, child: rest[0]),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: rest[1]),
                        const SizedBox(width: 8),
                        Expanded(flex: 3, child: rest[2]),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(flex: 6, child: description),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: rest[0]),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: rest[1]),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: rest[2]),
                  remove,
                ],
              );
            },
          ),
        ),
    ];
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  /// Campo com o nome acima; sem nome nas linhas seguintes da lista de
  /// materiais, onde o cabeçalho da primeira linha já diz o que é.
  Widget _field(
    String? label,
    TextEditingController controller, {
    int lines = 1,
  }) {
    final input = TextField(
      controller: controller,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 3,
    );
    return label == null ? input : LabeledField(label: label, child: input);
  }

  Widget _pair(Widget a, Widget b) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 460
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [a, const SizedBox(height: 12), b],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.color,
    required this.icon,
    required this.text,
    this.action,
  });

  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
            ],
          ),
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action),
        ],
      ),
    );
  }
}

class _IssuedTile extends StatelessWidget {
  const _IssuedTile({
    required this.entry,
    required this.label,
    required this.missing,
    required this.onOpen,
  });

  final IssuedServiceOrder entry;
  final String label;
  final bool missing;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.orion;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            Icons.picture_as_pdf_outlined,
            size: 20,
            color: missing ? palette.textMuted : palette.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  missing
                      ? 'Arquivo movido ou apagado da pasta'
                      : entry.fileName,
                  style: TextStyle(color: palette.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (!missing)
            TextButton(onPressed: onOpen, child: const Text('Abrir')),
        ],
      ),
    );
  }
}
