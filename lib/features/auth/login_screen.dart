import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/orion_theme.dart';
import '../../shared/widgets/orion_brand.dart';
import 'password_recovery_screen.dart';
import '../../shared/widgets/labeled_field.dart';

/// Mensagem a exibir depois de um cadastro que não abriu sessão.
///
/// O Supabase não revela quais e-mails já estão cadastrados: em vez de
/// recusar, devolve sucesso com a lista de identidades vazia e não envia
/// mensagem nenhuma. Tratar isso como cadastro novo manda o usuário
/// esperar um e-mail que nunca chega — foi o que aconteceu em campo.
String? signUpFeedback({
  required bool hasSession,
  required int? identityCount,
}) {
  if (hasSession) return null;
  if (identityCount == 0) {
    return 'Este e-mail já tem conta. Volte para "Entrar" e use a sua senha. '
        'Se a esqueceu, peça a redefinição ao administrador.';
  }
  return 'Conta criada. Confirme o e-mail antes de entrar no sistema.';
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _createAccount = false;
  bool _loading = false;
  bool _obscure = true;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      if (_createAccount) {
        final response = await Supabase.instance.client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
        final feedback = signUpFeedback(
          hasSession: response.session != null,
          identityCount: response.user?.identities?.length,
        );
        if (feedback != null && mounted) {
          setState(() => _message = feedback);
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openRecovery() {
    // Leva o e-mail já digitado: quem esqueceu a senha quase sempre acabou
    // de tentar entrar com ele.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PasswordRecoveryScreen(initialEmail: _email.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Um formulário só, no meio da tela. O painel lateral com slogan e
    // etiquetas de recursos era propaganda para quem já é usuário.
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: _LoginForm(
                formKey: _formKey,
                email: _email,
                password: _password,
                createAccount: _createAccount,
                obscure: _obscure,
                loading: _loading,
                message: _message,
                onModeChanged: (value) => setState(() {
                  _createAccount = value;
                  _message = null;
                }),
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                onSubmit: _submit,
                onForgotPassword: _openRecovery,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.email,
    required this.password,
    required this.createAccount,
    required this.obscure,
    required this.loading,
    required this.onModeChanged,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onForgotPassword,
    this.message,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool createAccount;
  final bool obscure;
  final bool loading;
  final String? message;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final palette = context.orion;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: OrionBrand(height: 34),
          ),
          const SizedBox(height: 32),
          Text(
            createAccount ? 'Criar conta' : 'Entrar',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (createAccount) ...[
            const SizedBox(height: 4),
            Text(
              'Depois do cadastro você cria a sua organização.',
              style: TextStyle(color: palette.textMuted),
            ),
          ],
          const SizedBox(height: 24),
          LabeledField(
            label: 'E-mail',
            child: TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (!text.contains('@') || !text.contains('.')) {
                  return 'Informe um e-mail válido.';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: 'Senha',
            child: TextFormField(
              controller: password,
              obscureText: obscure,
              autofillHints: [
                createAccount
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              onFieldSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: obscure ? 'Mostrar senha' : 'Ocultar senha',
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                ),
              ),
              validator: (value) {
                if ((value ?? '').length < 8) {
                  return 'Use pelo menos 8 caracteres.';
                }
                return null;
              },
            ),
          ),
          if (!createAccount)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: loading ? null : onForgotPassword,
                child: const Text('Esqueci minha senha'),
              ),
            )
          else
            const SizedBox(height: 14),
          if (message != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.panel,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(OrionTheme.radius),
              ),
              child: Text(message!),
            ),
            const SizedBox(height: 14),
          ],
          FilledButton(
            onPressed: loading ? null : onSubmit,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(createAccount ? 'Criar conta' : 'Entrar'),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                createAccount ? 'Já tem conta?' : 'Ainda não tem conta?',
                style: TextStyle(color: palette.textMuted),
              ),
              TextButton(
                onPressed: loading ? null : () => onModeChanged(!createAccount),
                child: Text(createAccount ? 'Entrar' : 'Criar conta'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
