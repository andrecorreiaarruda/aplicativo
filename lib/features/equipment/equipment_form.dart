import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/equipment.dart';
import '../../shared/widgets/responsive_dialog.dart';
import '../shell/service_log_controller.dart';
import '../../shared/widgets/labeled_field.dart';

class EquipmentForm extends StatefulWidget {
  const EquipmentForm({super.key, required this.controller, this.equipment});

  final ServiceLogController controller;

  /// Quando informado, o formulário edita este equipamento em vez de
  /// cadastrar um novo.
  final Equipment? equipment;

  bool get isEditing => equipment != null;

  @override
  State<EquipmentForm> createState() => _EquipmentFormState();
}

class _EquipmentFormState extends State<EquipmentForm> {
  final _formKey = GlobalKey<FormState>();
  final _serial = TextEditingController();
  final _software = TextEditingController();
  final _hardware = TextEditingController();
  final _notes = TextEditingController();
  TextEditingController? _modelFieldController;
  FocusNode? _modelFocusNode;
  TextEditingController? _siteFieldController;
  FocusNode? _siteFocusNode;
  String? _modelId;
  String? _siteId;
  String _status = 'operational';

  @override
  void initState() {
    super.initState();
    final existente = widget.equipment;
    if (existente == null) return;
    _serial.text = existente.serialNumber;
    _software.text = existente.softwareVersion ?? '';
    _hardware.text = existente.hardwareVersion ?? '';
    _notes.text = existente.notes ?? '';
    _modelId = existente.modelId;
    _siteId = existente.siteId;
    _status = existente.status;
  }

  @override
  void dispose() {
    _serial.dispose();
    _software.dispose();
    _hardware.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _newModel({String initialQuery = ''}) async {
    final modelId = await showResponsiveDialog<String>(
      context: context,
      maxWidth: 660,
      child: EquipmentModelForm(
        controller: widget.controller,
        initialQuery: initialQuery,
      ),
    );
    if (modelId == null || !mounted) return;

    final model = _modelById(modelId);
    setState(() => _modelId = modelId);
    if (model != null) {
      _modelFieldController?.text = model.label;
      _modelFieldController?.selection = TextSelection.collapsed(
        offset: model.label.length,
      );
    }
    _modelFocusNode?.unfocus();
  }

  Future<void> _newCustomerSite({String initialQuery = ''}) async {
    final siteId = await showResponsiveDialog<String>(
      context: context,
      maxWidth: 660,
      child: CustomerSiteForm(
        controller: widget.controller,
        initialQuery: initialQuery,
      ),
    );
    if (siteId == null || !mounted) return;

    final site = _siteById(siteId);
    setState(() => _siteId = siteId);
    if (site != null) {
      _siteFieldController?.text = site.label;
      _siteFieldController?.selection = TextSelection.collapsed(
        offset: site.label.length,
      );
    }
    _siteFocusNode?.unfocus();
  }

  Future<void> _selectModelChoice(_EquipmentModelChoice choice) async {
    if (choice.isCreate) {
      await _newModel(initialQuery: choice.query);
      return;
    }

    final model = choice.model!;
    setState(() => _modelId = model.id);
    _modelFocusNode?.unfocus();
  }

  Future<void> _selectSiteChoice(_SiteChoice choice) async {
    if (choice.isCreate) {
      await _newCustomerSite(initialQuery: choice.query);
      return;
    }

    final site = choice.site!;
    setState(() => _siteId = site.id);
    _siteFocusNode?.unfocus();
  }

  Iterable<_SiteChoice> _siteSuggestions(String rawQuery) {
    final query = _normalize(rawQuery);
    if (query.isEmpty) return const <_SiteChoice>[];

    final tokens = query.split(' ').where((token) => token.isNotEmpty).toList();
    final ranked = <_RankedSite>[];

    for (final site in widget.controller.catalog.sites) {
      final customer = _normalize(site.customer);
      final siteName = _normalize(site.site);
      final city = _normalize(site.city ?? '');
      final state = _normalize(site.state ?? '');
      final fullName = _normalize(site.label);
      final searchable = '$customer $siteName $city $state';

      if (!tokens.every(searchable.contains)) continue;

      var score = 40;
      if (fullName == query) {
        score = 100;
      } else if (siteName == query) {
        score = 95;
      } else if (fullName.startsWith(query)) {
        score = 85;
      } else if (customer.startsWith(query)) {
        score = 80;
      } else if (siteName.startsWith(query)) {
        score = 75;
      }
      ranked.add(_RankedSite(site: site, score: score));
    }

    ranked.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.site.label.compareTo(b.site.label);
    });

    final suggestions = ranked
        .take(8)
        .map((entry) => _SiteChoice.existing(entry.site))
        .toList();

    final hasExactMatch = widget.controller.catalog.sites.any((site) {
      final values = [
        site.label,
        site.site,
        '${site.customer} ${site.site}',
      ].map(_normalize);
      return values.contains(query);
    });

    if (!hasExactMatch) {
      suggestions.add(_SiteChoice.create(rawQuery.trim()));
    }
    return suggestions;
  }

  Iterable<_EquipmentModelChoice> _modelSuggestions(String rawQuery) {
    final query = _normalize(rawQuery);
    if (query.isEmpty) return const <_EquipmentModelChoice>[];

    final tokens = query.split(' ').where((token) => token.isNotEmpty).toList();
    final ranked = <_RankedEquipmentModel>[];

    for (final model in widget.controller.catalog.models) {
      final manufacturer = _normalize(model.manufacturer);
      final family = _normalize(model.family);
      final modelName = _normalize(model.model);
      final modality = _normalize(model.modality);
      final fullName = _normalize('${model.manufacturer} ${model.model}');
      final searchable = '$manufacturer $family $modelName $modality';

      if (!tokens.every(searchable.contains)) continue;

      var score = 40;
      if (modelName == query) {
        score = 100;
      } else if (fullName == query) {
        score = 95;
      } else if (modelName.startsWith(query)) {
        score = 85;
      } else if (fullName.startsWith(query)) {
        score = 80;
      } else if (manufacturer.startsWith(query)) {
        score = 70;
      } else if (family.startsWith(query)) {
        score = 60;
      }
      ranked.add(_RankedEquipmentModel(model: model, score: score));
    }

    ranked.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.model.label.compareTo(b.model.label);
    });

    final suggestions = ranked
        .take(8)
        .map((entry) => _EquipmentModelChoice.existing(entry.model))
        .toList();

    final hasExactMatch = widget.controller.catalog.models.any((model) {
      final values = [
        model.model,
        '${model.manufacturer} ${model.model}',
        model.label,
      ].map(_normalize);
      return values.contains(query);
    });

    if (!hasExactMatch) {
      suggestions.add(_EquipmentModelChoice.create(rawQuery.trim()));
    }
    return suggestions;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final draft = EquipmentDraft(
      modelId: _modelId!,
      serialNumber: _serial.text,
      siteId: _siteId,
      softwareVersion: _software.text,
      hardwareVersion: _hardware.text,
      status: _status,
      notes: _notes.text,
    );
    final existente = widget.equipment;
    final ok = existente == null
        ? await widget.controller.createEquipment(draft)
        : await widget.controller.updateEquipment(existente.id, draft);
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DialogHeader(
          title: widget.isEditing
              ? 'Editar equipamento'
              : 'Cadastrar equipamento',
          onClose: () => Navigator.of(context).pop(),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Autocomplete<_EquipmentModelChoice>(
                    displayStringForOption: (choice) => choice.displayText,
                    optionsBuilder: (textEditingValue) =>
                        _modelSuggestions(textEditingValue.text),
                    onSelected: _selectModelChoice,
                    fieldViewBuilder:
                        (
                          context,
                          textEditingController,
                          focusNode,
                          onFieldSubmitted,
                        ) {
                          _modelFieldController = textEditingController;
                          _modelFocusNode = focusNode;
                          return LabeledField(
                            label: 'Fabricante / modelo',
                            child: TextFormField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                hintText:
                                    'Digite, por exemplo: Azurion, Allura ou Versa HD',
                                prefixIcon: const Icon(Icons.search_rounded),
                                helperText:
                                    'Selecione uma correspondência ou cadastre o modelo sem sair deste formulário.',
                                suffixIcon: textEditingController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Limpar modelo',
                                        onPressed: () {
                                          textEditingController.clear();
                                          setState(() => _modelId = null);
                                          focusNode.requestFocus();
                                        },
                                        icon: const Icon(Icons.clear_rounded),
                                      ),
                              ),
                              onChanged: (value) {
                                final selected = _modelById(_modelId);
                                if (selected != null &&
                                    _normalize(value) ==
                                        _normalize(selected.label)) {
                                  return;
                                }
                                if (_modelId != null) {
                                  setState(() => _modelId = null);
                                } else {
                                  setState(() {});
                                }
                              },
                              onFieldSubmitted: (_) => onFieldSubmitted(),
                              validator: (_) => _modelId == null
                                  ? 'Selecione uma correspondência ou cadastre um novo modelo.'
                                  : null,
                            ),
                          );
                        },
                    optionsViewBuilder: (context, onSelected, options) {
                      final choices = options.toList();
                      final width = math.min(
                        MediaQuery.sizeOf(context).width - 48,
                        650.0,
                      );
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 10,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: 360,
                              maxWidth: width,
                              minWidth: math.min(width, 420.0),
                            ),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: choices.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final choice = choices[index];
                                if (choice.isCreate) {
                                  return ListTile(
                                    leading: const Icon(
                                      Icons.add_circle_outline_rounded,
                                    ),
                                    title: Text(
                                      'Cadastrar “${choice.query}”',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'Nenhuma correspondência exata. Abrir cadastro rápido do modelo.',
                                    ),
                                    onTap: () => onSelected(choice),
                                  );
                                }

                                final model = choice.model!;
                                final details = [
                                  if (model.family.trim().isNotEmpty)
                                    model.family.trim(),
                                  if (model.modality.trim().isNotEmpty &&
                                      model.modality != 'Não informada')
                                    model.modality.trim(),
                                ];
                                return ListTile(
                                  leading: const Icon(
                                    Icons.precision_manufacturing_outlined,
                                  ),
                                  title: Text(
                                    '${model.manufacturer} ${model.model}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: details.isEmpty
                                      ? null
                                      : Text(details.join(' · ')),
                                  onTap: () => onSelected(choice),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Número de série',
                    child: TextFormField(
                      controller: _serial,
                      decoration: const InputDecoration(
                        helperText:
                            'Opcional. Deixe em branco se não for possível '
                            'identificar; quando informado, precisa ser único.',
                        helperMaxLines: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Autocomplete<_SiteChoice>(
                    displayStringForOption: (choice) => choice.displayText,
                    optionsBuilder: (textEditingValue) =>
                        _siteSuggestions(textEditingValue.text),
                    onSelected: _selectSiteChoice,
                    fieldViewBuilder:
                        (
                          context,
                          textEditingController,
                          focusNode,
                          onFieldSubmitted,
                        ) {
                          _siteFieldController = textEditingController;
                          _siteFocusNode = focusNode;
                          return LabeledField(
                            label: 'Cliente / local de instalação',
                            child: TextFormField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                hintText:
                                    'Digite o hospital, clínica, sala, bunker ou cidade',
                                prefixIcon: const Icon(Icons.business_outlined),
                                helperText:
                                    'Selecione uma correspondência ou cadastre o cliente/local sem sair do equipamento.',
                                suffixIcon: textEditingController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Limpar cliente/local',
                                        onPressed: () {
                                          textEditingController.clear();
                                          setState(() => _siteId = null);
                                          focusNode.requestFocus();
                                        },
                                        icon: const Icon(Icons.clear_rounded),
                                      ),
                              ),
                              onChanged: (value) {
                                final selected = _siteById(_siteId);
                                if (selected != null &&
                                    _normalize(value) ==
                                        _normalize(selected.label)) {
                                  return;
                                }
                                if (_siteId != null) {
                                  setState(() => _siteId = null);
                                } else {
                                  setState(() {});
                                }
                              },
                              onFieldSubmitted: (_) => onFieldSubmitted(),
                            ),
                          );
                        },
                    optionsViewBuilder: (context, onSelected, options) {
                      final choices = options.toList();
                      final width = math.min(
                        MediaQuery.sizeOf(context).width - 48,
                        650.0,
                      );
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 10,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: 340,
                              maxWidth: width,
                              minWidth: math.min(width, 420.0),
                            ),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: choices.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final choice = choices[index];
                                if (choice.isCreate) {
                                  return ListTile(
                                    leading: const Icon(
                                      Icons.add_business_outlined,
                                    ),
                                    title: Text(
                                      'Cadastrar cliente/local “${choice.query}”',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'Crie o cliente e o local sem perder os dados deste equipamento.',
                                    ),
                                    onTap: () => onSelected(choice),
                                  );
                                }

                                final site = choice.site!;
                                return ListTile(
                                  leading: const Icon(
                                    Icons.location_on_outlined,
                                  ),
                                  title: Text(
                                    site.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: site.locationLabel.isEmpty
                                      ? null
                                      : Text(site.locationLabel),
                                  onTap: () => onSelected(choice),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.controller.saving
                          ? null
                          : () => _newCustomerSite(),
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Cadastrar cliente/local manualmente'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fields = [
                        LabeledField(
                          label: 'Versão de software',
                          child: TextFormField(controller: _software),
                        ),
                        LabeledField(
                          label: 'Versão de hardware',
                          child: TextFormField(controller: _hardware),
                        ),
                      ];
                      if (constraints.maxWidth < 520) {
                        return Column(
                          children: [
                            fields[0],
                            const SizedBox(height: 14),
                            fields[1],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: fields[0]),
                          const SizedBox(width: 14),
                          Expanded(child: fields[1]),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Condição atual',
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      items: const [
                        DropdownMenuItem(
                          value: 'operational',
                          child: Text('Operacional'),
                        ),
                        DropdownMenuItem(
                          value: 'degraded',
                          child: Text('Degradado'),
                        ),
                        DropdownMenuItem(
                          value: 'stopped',
                          child: Text('Parado'),
                        ),
                        DropdownMenuItem(
                          value: 'decommissioned',
                          child: Text('Desativado'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _status = value!),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Observações',
                    child: TextFormField(
                      controller: _notes,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText:
                            'Configuração especial, acessórios, histórico relevante...',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        _DialogActions(
          saving: widget.controller.saving,
          onCancel: () => Navigator.of(context).pop(),
          onSave: _save,
          saveLabel: 'Salvar equipamento',
        ),
      ],
    );
  }

  EquipmentModelOption? _modelById(String? id) {
    if (id == null) return null;
    for (final model in widget.controller.catalog.models) {
      if (model.id == id) return model;
    }
    return null;
  }

  SiteOption? _siteById(String? id) {
    if (id == null) return null;
    for (final site in widget.controller.catalog.sites) {
      if (site.id == id) return site;
    }
    return null;
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

class _RankedEquipmentModel {
  const _RankedEquipmentModel({required this.model, required this.score});

  final EquipmentModelOption model;
  final int score;
}

class _EquipmentModelChoice {
  const _EquipmentModelChoice.existing(this.model) : query = '';
  const _EquipmentModelChoice.create(this.query) : model = null;

  final EquipmentModelOption? model;
  final String query;

  bool get isCreate => model == null;
  String get displayText => model?.label ?? query;
}

class _RankedSite {
  const _RankedSite({required this.site, required this.score});

  final SiteOption site;
  final int score;
}

class _SiteChoice {
  const _SiteChoice.existing(this.site) : query = '';
  const _SiteChoice.create(this.query) : site = null;

  final SiteOption? site;
  final String query;

  bool get isCreate => site == null;
  String get displayText => site?.label ?? query;
}

class EquipmentModelForm extends StatefulWidget {
  const EquipmentModelForm({
    super.key,
    required this.controller,
    this.initialQuery = '',
  });

  final ServiceLogController controller;
  final String initialQuery;

  @override
  State<EquipmentModelForm> createState() => _EquipmentModelFormState();
}

class _EquipmentModelFormState extends State<EquipmentModelForm> {
  final _formKey = GlobalKey<FormState>();
  final _manufacturer = TextEditingController();
  final _family = TextEditingController();
  final _model = TextEditingController();
  final _modality = TextEditingController();
  final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prefillFromSearch(widget.initialQuery);
  }

  void _prefillFromSearch(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    final manufacturers =
        widget.controller.catalog.models
            .map((item) => item.manufacturer.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));

    for (final manufacturer in manufacturers) {
      final normalizedQuery = query.toLowerCase();
      final normalizedManufacturer = manufacturer.toLowerCase();
      if (normalizedQuery == normalizedManufacturer) {
        _manufacturer.text = manufacturer;
        return;
      }
      if (normalizedQuery.startsWith('$normalizedManufacturer ')) {
        _manufacturer.text = manufacturer;
        _model.text = query.substring(manufacturer.length).trim();
        return;
      }
    }

    _model.text = query;
  }

  @override
  void dispose() {
    _manufacturer.dispose();
    _family.dispose();
    _model.dispose();
    _modality.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final id = await widget.controller.createEquipmentModel(
      EquipmentModelDraft(
        manufacturer: _manufacturer.text,
        family: _family.text,
        model: _model.text,
        modality: _modality.text,
        description: _description.text,
      ),
    );
    if (id != null && mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DialogHeader(
          title: 'Cadastrar fabricante e modelo',
          onClose: () => Navigator.of(context).pop(),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  LabeledField(
                    label: 'Fabricante',
                    child: TextFormField(
                      controller: _manufacturer,
                      textCapitalization: TextCapitalization.words,
                      validator: _required,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Família / linha (opcional)',
                    child: TextFormField(
                      controller: _family,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Ex.: Allura Xper, Azurion, Versa HD',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Modelo',
                    child: TextFormField(
                      controller: _model,
                      textCapitalization: TextCapitalization.words,
                      validator: _required,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Modalidade (opcional)',
                    child: TextFormField(
                      controller: _modality,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText:
                            'Ex.: Angiografia, Radioterapia, Tomografia, RM',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Descrição opcional',
                    child: TextFormField(controller: _description, maxLines: 3),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        _DialogActions(
          saving: widget.controller.saving,
          onCancel: () => Navigator.of(context).pop(),
          onSave: _save,
          saveLabel: 'Salvar modelo',
        ),
      ],
    );
  }

  static String? _required(String? value) =>
      (value?.trim().isEmpty ?? true) ? 'Campo obrigatório.' : null;
}

class CustomerForm extends StatefulWidget {
  const CustomerForm({super.key, required this.controller, this.customer});

  final ServiceLogController controller;
  final CustomerOption? customer;

  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _taxId = TextEditingController();
  final _contactName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    if (customer == null) return;
    _name.text = customer.name;
    _taxId.text = customer.taxId ?? '';
    _contactName.text = customer.contactName ?? '';
    _email.text = customer.email ?? '';
    _phone.text = customer.phone ?? '';
    _address.text = customer.addressLine ?? '';
    _city.text = customer.city ?? '';
    _state.text = customer.state ?? '';
    _notes.text = customer.notes ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _taxId.dispose();
    _contactName.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final draft = CustomerDraft(
      name: _name.text,
      taxId: _taxId.text,
      contactName: _contactName.text,
      email: _email.text,
      phone: _phone.text,
      addressLine: _address.text,
      city: _city.text,
      state: _state.text,
      notes: _notes.text,
    );

    final current = widget.customer;
    if (current == null) {
      final id = await widget.controller.createCustomer(draft);
      if (id != null && mounted) Navigator.of(context).pop(id);
      return;
    }

    final ok = await widget.controller.updateCustomer(current.id, draft);
    if (ok && mounted) Navigator.of(context).pop(current.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DialogHeader(
          title: widget.customer == null
              ? 'Cadastrar cliente'
              : 'Editar cliente',
          onClose: () => Navigator.of(context).pop(),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabeledField(
                    label: 'Nome do cliente',
                    child: TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        helperText: 'Este é o único campo obrigatório.',
                      ),
                      validator: _required,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'CNPJ / identificação (opcional)',
                    child: TextFormField(controller: _taxId),
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Pessoa de contato (opcional)',
                    child: TextFormField(
                      controller: _contactName,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final phone = LabeledField(
                        label: 'Telefone (opcional)',
                        child: TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                        ),
                      );
                      final email = LabeledField(
                        label: 'E-mail (opcional)',
                        child: TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                        ),
                      );
                      if (constraints.maxWidth < 520) {
                        return Column(
                          children: [phone, const SizedBox(height: 14), email],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: phone),
                          const SizedBox(width: 14),
                          Expanded(child: email),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Endereço (opcional)',
                    child: TextFormField(
                      controller: _address,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final city = LabeledField(
                        label: 'Cidade (opcional)',
                        child: TextFormField(
                          controller: _city,
                          textCapitalization: TextCapitalization.words,
                        ),
                      );
                      final state = LabeledField(
                        label: 'UF (opcional)',
                        child: TextFormField(
                          controller: _state,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 2,
                          decoration: const InputDecoration(counterText: ''),
                        ),
                      );
                      if (constraints.maxWidth < 440) {
                        return Column(
                          children: [city, const SizedBox(height: 14), state],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: city),
                          const SizedBox(width: 14),
                          Expanded(child: state),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Observações (opcional)',
                    child: TextFormField(
                      controller: _notes,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText:
                            'Informações úteis para atendimento, acesso e faturamento.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        _DialogActions(
          saving: widget.controller.saving,
          onCancel: () => Navigator.of(context).pop(),
          onSave: _save,
          saveLabel: widget.customer == null
              ? 'Salvar cliente'
              : 'Salvar alterações',
        ),
      ],
    );
  }

  static String? _required(String? value) =>
      (value?.trim().isEmpty ?? true) ? 'Informe o nome do cliente.' : null;
}

class SiteForm extends StatefulWidget {
  const SiteForm({
    super.key,
    required this.controller,
    this.initialCustomerId,
    this.site,
  });

  final ServiceLogController controller;
  final String? initialCustomerId;
  final SiteOption? site;

  @override
  State<SiteForm> createState() => _SiteFormState();
}

class _SiteFormState extends State<SiteForm> {
  final _formKey = GlobalKey<FormState>();
  final _site = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _notes = TextEditingController();
  String? _customerId;

  @override
  void initState() {
    super.initState();
    final site = widget.site;
    _customerId = site?.customerId ?? widget.initialCustomerId;
    if (site == null) return;
    _site.text = site.site;
    _city.text = site.city ?? '';
    _state.text = site.state ?? '';
    _notes.text = site.notes ?? '';
  }

  @override
  void dispose() {
    _site.dispose();
    _city.dispose();
    _state.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final draft = SiteDraft(
      customerId: _customerId!,
      siteName: _site.text,
      city: _city.text,
      state: _state.text,
      notes: _notes.text,
    );

    final current = widget.site;
    if (current == null) {
      final id = await widget.controller.createSite(draft);
      if (id != null && mounted) Navigator.of(context).pop(id);
      return;
    }

    final ok = await widget.controller.updateSite(current.id, draft);
    if (ok && mounted) Navigator.of(context).pop(current.id);
  }

  @override
  Widget build(BuildContext context) {
    final customers = widget.controller.catalog.customers;
    return Column(
      children: [
        _DialogHeader(
          title: widget.site == null
              ? 'Cadastrar local do cliente'
              : 'Editar local do cliente',
          onClose: () => Navigator.of(context).pop(),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabeledField(
                    label: 'Cliente',
                    child: DropdownButtonFormField<String>(
                      initialValue: _customerId,
                      isExpanded: true,
                      items: customers
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _customerId = value),
                      validator: (value) =>
                          value == null ? 'Selecione o cliente.' : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Unidade / sala / bunker',
                    child: TextFormField(
                      controller: _site,
                      textCapitalization: TextCapitalization.words,
                      validator: _required,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final city = LabeledField(
                        label: 'Cidade (opcional)',
                        child: TextFormField(
                          controller: _city,
                          textCapitalization: TextCapitalization.words,
                        ),
                      );
                      final state = LabeledField(
                        label: 'UF (opcional)',
                        child: TextFormField(
                          controller: _state,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 2,
                          decoration: const InputDecoration(counterText: ''),
                        ),
                      );
                      if (constraints.maxWidth < 440) {
                        return Column(
                          children: [city, const SizedBox(height: 14), state],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: city),
                          const SizedBox(width: 14),
                          Expanded(child: state),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Observações do local (opcional)',
                    child: TextFormField(
                      controller: _notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText:
                            'Acesso, andar, sala técnica, contato local...',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        _DialogActions(
          saving: widget.controller.saving,
          onCancel: () => Navigator.of(context).pop(),
          onSave: _save,
          saveLabel: widget.site == null ? 'Salvar local' : 'Salvar alterações',
        ),
      ],
    );
  }

  static String? _required(String? value) =>
      (value?.trim().isEmpty ?? true) ? 'Informe o local.' : null;
}

class CustomerSiteForm extends StatefulWidget {
  const CustomerSiteForm({
    super.key,
    required this.controller,
    this.initialQuery = '',
  });

  final ServiceLogController controller;
  final String initialQuery;

  @override
  State<CustomerSiteForm> createState() => _CustomerSiteFormState();
}

class _CustomerSiteFormState extends State<CustomerSiteForm> {
  final _formKey = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _taxId = TextEditingController();
  final _site = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController(text: 'PR');
  String? _customerId;
  late bool _newCustomer;

  @override
  void initState() {
    super.initState();
    _newCustomer = widget.controller.catalog.customers.isEmpty;
    _prefillFromSearch(widget.initialQuery);
  }

  void _prefillFromSearch(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    final customers = [...widget.controller.catalog.customers]
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    final normalizedQuery = query.toLowerCase();

    for (final customer in customers) {
      final normalizedCustomer = customer.name.toLowerCase();
      if (normalizedQuery == normalizedCustomer) {
        _newCustomer = false;
        _customerId = customer.id;
        return;
      }
      if (normalizedQuery.startsWith('$normalizedCustomer ') ||
          normalizedQuery.startsWith('$normalizedCustomer -') ||
          normalizedQuery.startsWith('$normalizedCustomer —')) {
        _newCustomer = false;
        _customerId = customer.id;
        _site.text = query
            .substring(customer.name.length)
            .replaceFirst(RegExp(r'^\s*[-—/]\s*'), '')
            .trim();
        return;
      }
    }

    final parts = query.split(RegExp(r'\s+[-—/]\s+'));
    if (parts.length >= 2) {
      _customer.text = parts.first.trim();
      _site.text = parts.skip(1).join(' - ').trim();
      _newCustomer = true;
      return;
    }

    _customer.text = query;
    _newCustomer = true;
  }

  @override
  void dispose() {
    _customer.dispose();
    _taxId.dispose();
    _site.dispose();
    _city.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    String? customerId = _customerId;
    if (_newCustomer) {
      customerId = await widget.controller.createCustomer(
        CustomerDraft(name: _customer.text, taxId: _taxId.text),
      );
      if (customerId == null) return;
    }

    final siteId = await widget.controller.createSite(
      SiteDraft(
        customerId: customerId!,
        siteName: _site.text,
        city: _city.text,
        state: _state.text,
      ),
    );
    if (siteId != null && mounted) Navigator.of(context).pop(siteId);
  }

  @override
  Widget build(BuildContext context) {
    final customers = widget.controller.catalog.customers;
    return Column(
      children: [
        _DialogHeader(
          title: 'Cadastrar cliente e local',
          onClose: () => Navigator.of(context).pop(),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (customers.isNotEmpty) ...[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cadastrar um novo cliente'),
                      subtitle: const Text(
                        'Desative para adicionar um novo local a cliente existente.',
                      ),
                      value: _newCustomer,
                      onChanged: (value) {
                        setState(() {
                          _newCustomer = value;
                          if (value) _customerId = null;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_newCustomer) ...[
                    LabeledField(
                      label: 'Nome do cliente',
                      child: TextFormField(
                        controller: _customer,
                        textCapitalization: TextCapitalization.words,
                        validator: _required,
                      ),
                    ),
                    const SizedBox(height: 14),
                    LabeledField(
                      label: 'CNPJ / identificação opcional',
                      child: TextFormField(controller: _taxId),
                    ),
                  ] else
                    LabeledField(
                      label: 'Cliente existente',
                      child: DropdownButtonFormField<String>(
                        initialValue: _customerId,
                        isExpanded: true,
                        items: customers
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.id,
                                child: Text(
                                  item.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _customerId = value),
                        validator: (value) => !_newCustomer && value == null
                            ? 'Selecione o cliente.'
                            : null,
                      ),
                    ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Unidade / sala / bunker',
                    child: TextFormField(
                      controller: _site,
                      textCapitalization: TextCapitalization.words,
                      validator: _required,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final city = LabeledField(
                        label: 'Cidade (opcional)',
                        child: TextFormField(
                          controller: _city,
                          textCapitalization: TextCapitalization.words,
                        ),
                      );
                      final state = LabeledField(
                        label: 'UF (opcional)',
                        child: TextFormField(
                          controller: _state,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 2,
                          decoration: const InputDecoration(counterText: ''),
                        ),
                      );
                      if (constraints.maxWidth < 440) {
                        return Column(
                          children: [city, const SizedBox(height: 14), state],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: city),
                          const SizedBox(width: 14),
                          Expanded(child: state),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        _DialogActions(
          saving: widget.controller.saving,
          onCancel: () => Navigator.of(context).pop(),
          onSave: _save,
          saveLabel: 'Salvar cliente e local',
        ),
      ],
    );
  }

  static String? _required(String? value) =>
      (value?.trim().isEmpty ?? true) ? 'Campo obrigatório.' : null;
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
        ],
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.saving,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: saving ? null : onCancel,
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saveLabel),
          ),
        ],
      ),
    );
  }
}
