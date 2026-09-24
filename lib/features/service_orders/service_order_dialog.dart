import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/orion_theme.dart';
import '../../data/models/equipment.dart';
import '../../data/models/service_case.dart';
import '../shell/service_log_controller.dart';
import 'service_order.dart';
import 'service_order_archive.dart';
import 'service_order_pdf.dart';

/// Monta a OS com o que o controlador sabe sobre o equipamento, o local e
/// o cliente do atendimento.
ServiceOrder assembleServiceOrder({
  required ServiceLogController controller,
  required ServiceCase item,
  required String organizationName,
  required String issuerName,
  required DateTime issuedAt,
}) {
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
  return ServiceOrder.assemble(
    item: item,
    equipment: equipment,
    site: site,
    customer: customer,
    organizationName: organizationName,
    issuerName: issuerName,
    issuedAt: issuedAt,
  );
}

/// Janela da OS de um atendimento: emite, lista as emitidas e abre.
///
/// Devolve verdadeiro se alguma OS foi emitida, para a lista de
/// atendimentos atualizar a marca de "OS emitida".
Future<bool> showServiceOrderDialog(
  BuildContext context, {
  required ServiceLogController controller,
  required ServiceCase item,
  required String organizationName,
  required String issuerName,
}) async {
  final archive = ServiceOrderScope.maybeOf(context);
  if (archive == null) return false;
  final issued = await showDialog<bool>(
    context: context,
    builder: (_) => _ServiceOrderDialog(
      archive: archive,
      controller: controller,
      item: item,
      organizationName: organizationName,
      issuerName: issuerName,
    ),
  );
  return issued ?? false;
}

class _ServiceOrderDialog extends StatefulWidget {
  const _ServiceOrderDialog({
    required this.archive,
    required this.controller,
    required this.item,
    required this.organizationName,
    required this.issuerName,
  });

  final ServiceOrderArchive archive;
  final ServiceLogController controller;
  final ServiceCase item;
  final String organizationName;
  final String issuerName;

  @override
  State<_ServiceOrderDialog> createState() => _ServiceOrderDialogState();
}

class _ServiceOrderDialogState extends State<_ServiceOrderDialog> {
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm');

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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
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
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível ler as OS emitidas: $error';
      });
    }
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
    final order = assembleServiceOrder(
      controller: widget.controller,
      item: _item,
      organizationName: widget.organizationName,
      issuerName: widget.issuerName,
      issuedAt: DateTime.now(),
    );
    final bytes = await buildServiceOrderPdf(
      order,
      await ServiceOrderAssets.load(),
    );
    final issued = await widget.archive.record(
      caseId: _item.id,
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

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final palette = context.orion;
    final openSession = item.progressEntries.any((entry) => entry.isOpen);

    return AlertDialog(
      title: Text('Ordem de serviço · OS ${item.caseNumber}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
                    Text(
                      'Gera um PDF com cliente, equipamento, chamado, '
                      'execução, conclusão, sessões e tempos deste '
                      'atendimento.',
                      style: TextStyle(color: palette.textMuted, height: 1.4),
                    ),
                    if (_provisional) ...[
                      const SizedBox(height: 14),
                      _Notice(
                        color: palette.warning,
                        icon: Icons.sync_problem_rounded,
                        text:
                            'Este atendimento foi criado neste computador e '
                            'ainda não passou pelo servidor. O número '
                            '${item.caseNumber} é provisório e pode mudar ao '
                            'sincronizar. Sincronize antes de emitir, para a '
                            'OS não sair com um número que depois deixa de '
                            'existir.',
                        action: TextButton.icon(
                          onPressed: _busy ? null : _sync,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('Sincronizar agora'),
                        ),
                      ),
                    ] else if (!item.isResolved) ...[
                      const SizedBox(height: 14),
                      _Notice(
                        color: palette.accent,
                        icon: Icons.info_outline_rounded,
                        text:
                            'O atendimento ainda não foi concluído. A OS sai '
                            'com a situação "${ServiceOrder.labelForStatus(item.status)}" '
                            'e só com o que já foi registrado.',
                      ),
                    ],
                    if (!_provisional && openSession) ...[
                      const SizedBox(height: 10),
                      _Notice(
                        color: palette.accent,
                        icon: Icons.timer_outlined,
                        text:
                            'Há uma sessão de trabalho em aberto. Ela sai sem '
                            'horário de fim e não entra no tempo técnico.',
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Emitidas neste computador',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
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
          onPressed: _busy
              ? null
              : () => Navigator.of(context).pop(_issuedSomething),
          child: const Text('Fechar'),
        ),
        FilledButton.icon(
          onPressed: _loading || _busy || _provisional ? null : _issue,
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
