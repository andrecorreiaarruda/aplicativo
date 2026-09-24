import 'package:flutter/material.dart';

import '../../core/theme/orion_theme.dart';
import 'password_recovery.dart';

/// Primeira metade da recuperação: pede o código e o confere.
///
/// Quando o código é aceito, o Supabase abre uma sessão de recuperação e o
/// [AuthGate] troca a tela de login pela de senha nova. Esta tela foi
/// empilhada por cima do gate, então sai da frente sozinha — do contrário
/// ficaria cobrindo justamente o passo seguinte.
class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    this.initialEmail = '',
    PasswordRecoveryService? service,
  }) : _service = service;

  final String initialEmail;
  final PasswordRecoveryService? _service;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _codeForm = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _code = TextEditingController();
  late final PasswordRecoveryService _service;

  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
    _service = widget._service ?? SupabasePasswordRecoveryService();
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = describeRecoveryError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode() async {
    if (!_emailForm.currentState!.validate()) return;
    await _run(() async {
      await _service.sendCode(_email.text);
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _verifyCode() async {
    if (!_codeForm.currentState!.validate()) return;
    await _run(() async {
      await _service.verifyCode(_email.text, _code.text);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar senha')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _codeSent ? 'Digite o código' : 'Esqueceu a senha?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _codeSent
                      ? 'Se houver uma conta com ${normalizeEmail(_email.text)}, '
                            'um código chegou por e-mail. Confira também a '
                            'caixa de spam. O código vale por uma hora.'
                      : 'Informe o e-mail da sua conta. Enviaremos um código '
                            'para você definir uma senha nova.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                if (!_codeSent) _emailStep() else _codeStep(),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailStep() {
    return Form(
      key: _emailForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onFieldSubmitted: (_) => _sendCode(),
            decoration: const InputDecoration(
              labelText: 'E-mail',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (!text.contains('@') || !text.contains('.')) {
                return 'Informe um e-mail válido.';
              }
              return null;
            },
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _loading ? null : _sendCode,
            icon: _progressOr(Icons.send_rounded),
            label: const Text('Enviar código'),
          ),
        ],
      ),
    );
  }

  Widget _codeStep() {
    return Form(
      key: _codeForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _code,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            autofocus: true,
            onFieldSubmitted: (_) => _verifyCode(),
            decoration: const InputDecoration(
              labelText: 'Código',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            validator: validateRecoveryCode,
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _loading ? null : _verifyCode,
            icon: _progressOr(Icons.verified_rounded),
            label: const Text('Confirmar código'),
          ),
          const SizedBox(height: 10),
          TextButton(
            // Volta ao passo do e-mail em vez de reenviar direto: se o
            // código não chegou, o e-mail digitado pode estar errado.
            onPressed: _loading
                ? null
                : () => setState(() {
                    _codeSent = false;
                    _code.clear();
                    _error = null;
                  }),
            child: const Text('Não recebi o código'),
          ),
        ],
      ),
    );
  }

  Widget _progressOr(IconData icon) => _loading
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(icon);
}
