import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import '../../shared/widgets/labeled_field.dart';
import 'service_order_archive.dart';
import 'service_order_issuer.dart';

/// Dados do emitente da OS. Devolve o que foi salvo, ou nulo se a janela
/// foi fechada sem salvar.
Future<ServiceOrderIssuer?> showIssuerDialog(BuildContext context) async {
  final archive = ServiceOrderScope.maybeOf(context);
  if (archive == null) return null;
  final current = await archive.loadIssuer();
  if (!context.mounted) return null;
  return showDialog<ServiceOrderIssuer>(
    context: context,
    builder: (_) => _IssuerDialog(archive: archive, initial: current),
  );
}

class _IssuerDialog extends StatefulWidget {
  const _IssuerDialog({required this.archive, required this.initial});

  final ServiceOrderArchive archive;
  final ServiceOrderIssuer initial;

  @override
  State<_IssuerDialog> createState() => _IssuerDialogState();
}

class _IssuerDialogState extends State<_IssuerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _company = TextEditingController(text: widget.initial.companyName);
  late final _taxId = TextEditingController(text: widget.initial.taxId);
  late final _address = TextEditingController(text: widget.initial.address);
  late final _city = TextEditingController(text: widget.initial.city);
  late final _name = TextEditingController(
    text: widget.initial.responsibleName,
  );
  late final _title = TextEditingController(
    text: widget.initial.responsibleTitle,
  );
  late final _registration = TextEditingController(
    text: widget.initial.registration,
  );
  late final _phone = TextEditingController(text: widget.initial.phone);
  late final _email = TextEditingController(text: widget.initial.email);
  bool _saving = false;
  String? _error;

  List<TextEditingController> get _all => [
    _company,
    _taxId,
    _address,
    _city,
    _name,
    _title,
    _registration,
    _phone,
    _email,
  ];

  @override
  void initState() {
    super.initState();
    // A prévia do rodapé acompanha a digitação.
    for (final controller in _all) {
      controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  /// Troca o que está na tela pelo padrão do `.env`. Não salva: dá para
  /// conferir e ajustar antes.
  void _useDefault() {
    final issuer = widget.archive.defaultIssuer;
    _company.text = issuer.companyName;
    _taxId.text = issuer.taxId;
    _address.text = issuer.address;
    _city.text = issuer.city;
    _name.text = issuer.responsibleName;
    _title.text = issuer.responsibleTitle;
    _registration.text = issuer.registration;
    _phone.text = issuer.phone;
    _email.text = issuer.email;
  }

  @override
  void dispose() {
    for (final controller in _all) {
      controller.dispose();
    }
    super.dispose();
  }

  ServiceOrderIssuer get _issuer => ServiceOrderIssuer(
    companyName: _company.text.trim(),
    taxId: _taxId.text.trim(),
    address: _address.text.trim(),
    city: _city.text.trim(),
    responsibleName: _name.text.trim(),
    responsibleTitle: _title.text.trim(),
    registration: _registration.text.trim(),
    phone: _phone.text.trim(),
    email: _email.text.trim(),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final issuer = _issuer;
      await widget.archive.saveIssuer(issuer);
      if (mounted) Navigator.of(context).pop(issuer);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Não foi possível salvar: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.orion;
    String? required(String? value) =>
        (value?.trim().isEmpty ?? true) ? 'Obrigatório na OS.' : null;

    Widget field(
      String label,
      TextEditingController controller, {
      String? hint,
      bool mandatory = false,
      TextInputType? keyboard,
    }) => LabeledField(
      label: label,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(hintText: hint),
        validator: mandatory ? required : null,
      ),
    );

    Widget pair(Widget a, Widget b) => LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 460
          ? Column(children: [a, const SizedBox(height: 12), b])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: a),
                const SizedBox(width: 12),
                Expanded(child: b),
              ],
            ),
    );

    final issuer = _issuer;
    return AlertDialog(
      title: const Text('Dados do emitente da OS'),
      // Largura fixa, e não máxima: o AlertDialog mede a largura intrínseca
      // do conteúdo, e os LayoutBuilder das linhas duplas não a informam.
      // Em tela estreita, o próprio diálogo reduz a largura.
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Saem no rodapé e na assinatura de toda OS emitida neste '
                  'computador.',
                  style: TextStyle(color: palette.textMuted),
                ),
                const SizedBox(height: 16),
                field('Empresa', _company, mandatory: true),
                const SizedBox(height: 12),
                pair(
                  field('CNPJ', _taxId),
                  field(
                    'Cidade da assinatura',
                    _city,
                    hint: 'Ex.: Curitiba/PR',
                  ),
                ),
                const SizedBox(height: 12),
                field('Endereço', _address),
                const SizedBox(height: 12),
                field('Responsável técnico', _name, mandatory: true),
                const SizedBox(height: 12),
                pair(
                  field(
                    'Formação',
                    _title,
                    hint: 'Ex.: Engenheiro Eletricista',
                  ),
                  field(
                    'Registro profissional',
                    _registration,
                    hint: 'Ex.: CREA-PR 000000/D',
                  ),
                ),
                const SizedBox(height: 12),
                pair(
                  field('Telefone', _phone, keyboard: TextInputType.phone),
                  field('E-mail', _email, keyboard: TextInputType.emailAddress),
                ),
                const SizedBox(height: 18),
                Text(
                  'Rodapé',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    [issuer.companyLine, issuer.responsibleLine]
                        .where((line) => line.isNotEmpty)
                        .join('\n')
                        .ifEmpty('Preencha os campos para ver como fica.'),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: palette.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.archive.defaultIssuer.isComplete)
          TextButton.icon(
            onPressed: _saving ? null : _useDefault,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Usar meus dados padrão'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
