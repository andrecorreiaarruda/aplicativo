import 'package:supabase_flutter/supabase_flutter.dart';

/// Recuperação de senha por código, e não por link.
///
/// O fluxo padrão do Supabase manda um link que abre no navegador e volta
/// ao aplicativo por deep link. Num aplicativo de desktop Linux isso exige
/// registrar um esquema de URL no sistema, e o link ainda cairia no
/// navegador sem ter para onde voltar. O código de uso único evita tudo
/// isso: o usuário lê no e-mail e digita aqui.
///
/// Depende do modelo "Reset Password" do Supabase incluir `{{ .Token }}` —
/// o modelo de fábrica só traz o link.
abstract class PasswordRecoveryService {
  /// Pede o envio do código. Não informa se o e-mail existe: o Supabase
  /// responde igual nos dois casos, para não revelar quem tem conta.
  Future<void> sendCode(String email);

  /// Valida o código. Em caso de sucesso abre uma sessão de recuperação,
  /// e o [AuthGate] passa a exigir a senha nova antes de qualquer coisa.
  Future<void> verifyCode(String email, String code);

  /// Grava a senha nova na sessão de recuperação aberta por [verifyCode].
  Future<void> updatePassword(String password);

  /// Abandona a recuperação sem trocar a senha.
  Future<void> cancel();
}

class SupabasePasswordRecoveryService implements PasswordRecoveryService {
  SupabasePasswordRecoveryService({GoTrueClient? auth})
    : _auth = auth ?? Supabase.instance.client.auth;

  final GoTrueClient _auth;

  @override
  Future<void> sendCode(String email) =>
      _auth.resetPasswordForEmail(normalizeEmail(email));

  @override
  Future<void> verifyCode(String email, String code) async {
    await _auth.verifyOTP(
      email: normalizeEmail(email),
      token: normalizeRecoveryCode(code),
      type: OtpType.recovery,
    );
  }

  @override
  Future<void> updatePassword(String password) async {
    await _auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> cancel() => _auth.signOut();
}

String normalizeEmail(String email) => email.trim().toLowerCase();

/// Remove o que o usuário costuma trazer junto ao copiar do e-mail:
/// espaços, hífens e quebras de linha. "123 456" e "123-456" viram
/// "123456".
String normalizeRecoveryCode(String code) =>
    code.replaceAll(RegExp(r'[\s-]'), '');

/// O Supabase gera 6 dígitos por padrão e aceita configurar até 10.
String? validateRecoveryCode(String? value) {
  final code = normalizeRecoveryCode(value ?? '');
  if (code.isEmpty) return 'Informe o código recebido por e-mail.';
  if (!RegExp(r'^\d{6,10}$').hasMatch(code)) {
    return 'O código tem de 6 a 10 dígitos, só números.';
  }
  return null;
}

/// Mesma regra de tamanho da tela de login, para a senha nova não ser
/// aceita aqui e recusada lá.
String? validateNewPassword(String? value) {
  if ((value ?? '').length < 8) return 'Use pelo menos 8 caracteres.';
  return null;
}

String? validatePasswordConfirmation(String? value, String password) {
  if (value != password) return 'As senhas não conferem.';
  return null;
}

/// Traduz as recusas mais comuns do Supabase. O restante passa adiante
/// como veio, em vez de virar uma mensagem genérica que esconda a causa.
///
/// O código de erro vem antes do texto porque é o que o Supabase mantém
/// estável; o texto fica como reserva para versões que não mandam código.
String describeRecoveryError(Object error) {
  final code = error is AuthException ? error.code : null;
  final message = error is AuthException ? error.message : error.toString();
  final lower = message.toLowerCase();
  if (code == 'same_password' || lower.contains('different from the old')) {
    return 'A senha nova precisa ser diferente da anterior.';
  }
  if (code == 'otp_expired' ||
      lower.contains('expired') ||
      lower.contains('invalid')) {
    return 'Código inválido ou expirado. Peça um novo código.';
  }
  if (code == 'over_email_send_rate_limit' ||
      lower.contains('rate limit') ||
      lower.contains('too many')) {
    return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos.';
  }
  return message;
}
