import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/orion_theme.dart';
import '../../shared/widgets/orion_brand.dart';

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
        if (response.session == null && mounted) {
          setState(() {
            _message =
                'Conta criada. Confirme o e-mail antes de entrar no sistema.';
          });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final form = _LoginForm(
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
          );
          if (!wide) {
            return SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: form,
                  ),
                ),
              ),
            );
          }
          return Row(
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  color: OrionColors.deepNavy,
                  padding: const EdgeInsets.all(56),
                  child: const _BrandPanel(),
                ),
              ),
              Expanded(
                flex: 4,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(48),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 450),
                      child: form,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OrionBrand(onDark: true, height: 48),
        const Spacer(),
        Text(
          'Conhecimento técnico que permanece com a equipe.',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.12,
              ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Registre falhas, organize diagnósticos e recupere soluções anteriores com rastreabilidade.',
          style: TextStyle(
            color: Color(0xFFD7E2F7),
            fontSize: 18,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 34),
        const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _FeatureTag(
                icon: Icons.history_rounded, label: 'Histórico técnico'),
            _FeatureTag(icon: Icons.security_rounded, label: 'Dados isolados'),
            _FeatureTag(
                icon: Icons.auto_awesome_rounded, label: 'Busca assistida'),
          ],
        ),
        const Spacer(),
        const Text(
          'A IA apresenta evidências históricas. A decisão técnica permanece com o profissional responsável.',
          style: TextStyle(color: Color(0xFF9FB1D4), height: 1.4),
        ),
      ],
    );
  }
}

class _FeatureTag extends StatelessWidget {
  const _FeatureTag({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: OrionColors.cyan, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
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

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(alignment: Alignment.centerLeft, child: OrionBrand()),
          const SizedBox(height: 38),
          Text(
            createAccount ? 'Criar acesso' : 'Acessar o sistema',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            createAccount
                ? 'Após o cadastro, configure o ambiente da sua empresa.'
                : 'Entre com sua conta profissional.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Entrar')),
              ButtonSegment(value: true, label: Text('Criar conta')),
            ],
            selected: {createAccount},
            onSelectionChanged:
                loading ? null : (values) => onModeChanged(values.first),
          ),
          const SizedBox(height: 22),
          TextFormField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
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
          const SizedBox(height: 14),
          TextFormField(
            controller: password,
            obscureText: obscure,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              labelText: 'Senha',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: onToggleObscure,
                icon: Icon(obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
              ),
            ),
            validator: (value) {
              if ((value ?? '').length < 8) {
                return 'Use pelo menos 8 caracteres.';
              }
              return null;
            },
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OrionColors.paleCyan,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(message!),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: loading ? null : onSubmit,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(createAccount
                    ? Icons.person_add_alt_1_rounded
                    : Icons.login_rounded),
            label: Text(createAccount ? 'Criar conta' : 'Entrar'),
          ),
        ],
      ),
    );
  }
}
