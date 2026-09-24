import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import 'password_recovery.dart';

/// Segunda metade da recuperação: define a senha nova.
///
/// Aparece no lugar do sistema enquanto a sessão de recuperação estiver
/// aberta. Entrar direto no sistema seria mais cômodo, mas deixaria a
/// pessoa logada sem senha que ela conheça — e ela voltaria a esquecer
/// na próxima vez que o login fosse pedido.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({
    super.key,
    required this.onCompleted,
    PasswordRecoveryService? service,
  }) : _service = service;

  /// Chamado depois que a senha foi gravada no servidor.
  final VoidCallback onCompleted;
  final PasswordRecoveryService? _service;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late final PasswordRecoveryService _service;

  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget._service ?? SupabasePasswordRecoveryService();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.updatePassword(_password.text);
      if (mounted) widget.onCompleted();
    } catch (error) {
      if (mounted) setState(() => _error = describeRecoveryError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _loading = true);
    try {
      await _service.cancel();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Defina a senha nova',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'O código foi aceito. Escolha a senha que você vai usar '
                    'daqui em diante.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofocus: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Senha nova',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                    ),
                    validator: validateNewPassword,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmation,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    onFieldSubmitted: (_) => _save(),
                    decoration: const InputDecoration(
                      labelText: 'Repita a senha nova',
                      prefixIcon: Icon(Icons.lock_reset_rounded),
                    ),
                    validator: (value) =>
                        validatePasswordConfirmation(value, _password.text),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: OrionColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: OrionColors.danger),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _loading ? null : _save,
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Salvar senha'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _loading ? null : _cancel,
                    child: const Text('Cancelar e voltar ao login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
