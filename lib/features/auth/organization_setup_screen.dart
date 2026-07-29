import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/orion_brand.dart';

class OrganizationSetupScreen extends StatefulWidget {
  const OrganizationSetupScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  State<OrganizationSetupScreen> createState() =>
      _OrganizationSetupScreenState();
}

class _OrganizationSetupScreenState extends State<OrganizationSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'ORION');
  final _fullName = TextEditingController();
  final _slug = TextEditingController(text: 'orion');
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final metadataName =
        Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'];
    if (metadataName is String) _fullName.text = metadataName;
  }

  @override
  void dispose() {
    _name.dispose();
    _fullName.dispose();
    _slug.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'bootstrap_organization',
        params: {
          'organization_name': _name.text.trim(),
          'organization_slug': _slug.text.trim().toLowerCase(),
          'owner_full_name': _fullName.text.trim(),
        },
      );
      widget.onCompleted();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: OrionBrand(),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Configurar ambiente',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Este procedimento cria a empresa e define sua conta como administradora.',
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _fullName,
                          decoration: const InputDecoration(
                            labelText: 'Seu nome completo',
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Nome da empresa',
                          ),
                          onChanged: (value) {
                            if (_slug.text == 'orion' || _slug.text.isEmpty) {
                              _slug.text = _slugify(value);
                            }
                          },
                          validator: _required,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _slug,
                          decoration: const InputDecoration(
                            labelText: 'Identificador da empresa',
                            helperText:
                                'Somente letras minúsculas, números e hífen.',
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (!RegExp(r'^[a-z0-9-]{3,40}$').hasMatch(text)) {
                              return 'Use de 3 a 40 caracteres válidos.';
                            }
                            return null;
                          },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _loading ? null : _submit,
                          icon: _loading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.apartment_rounded),
                          label: const Text('Criar ambiente ORION'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => Supabase.instance.client.auth.signOut(),
                          child: const Text('Sair desta conta'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _required(String? value) =>
      (value?.trim().isEmpty ?? true) ? 'Campo obrigatório.' : null;

  static String _slugify(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâãä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôõö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
