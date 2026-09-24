import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/theme/orion_theme.dart';
import 'package:servicelog_ai/features/auth/new_password_screen.dart';
import 'package:servicelog_ai/features/auth/password_recovery.dart';
import 'package:servicelog_ai/features/auth/password_recovery_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('regras', () {
    test('código aceita espaços e hífens de quem copia do e-mail', () {
      expect(normalizeRecoveryCode(' 123 456 '), '123456');
      expect(normalizeRecoveryCode('123-456'), '123456');
      expect(validateRecoveryCode('123 456'), isNull);
    });

    test('código recusa letras e tamanho fora do padrão', () {
      expect(validateRecoveryCode(''), isNotNull);
      expect(validateRecoveryCode('12345'), isNotNull);
      expect(validateRecoveryCode('12a456'), isNotNull);
      expect(validateRecoveryCode('12345678901'), isNotNull);
    });

    test('senha nova segue a regra de tamanho do login', () {
      expect(validateNewPassword('1234567'), isNotNull);
      expect(validateNewPassword('12345678'), isNull);
      expect(validatePasswordConfirmation('abcdefgh', 'abcdefgi'), isNotNull);
      expect(validatePasswordConfirmation('abcdefgh', 'abcdefgh'), isNull);
    });

    test('recusas do servidor viram texto que orienta', () {
      expect(
        describeRecoveryError(
          const AuthException('Token has expired or is invalid'),
        ),
        contains('Peça um novo código'),
      );
      expect(
        describeRecoveryError(const AuthException('email rate limit exceeded')),
        contains('Aguarde'),
      );
      expect(
        describeRecoveryError(
          const AuthException(
            'New password should be different from the old password.',
          ),
        ),
        contains('diferente'),
      );
      expect(
        describeRecoveryError(
          const AuthException('qualquer texto', code: 'same_password'),
        ),
        contains('diferente'),
        reason: 'o código de erro decide mesmo que o texto mude',
      );
      expect(
        describeRecoveryError(const AuthException('Falha desconhecida')),
        'Falha desconhecida',
        reason: 'o que não for reconhecido passa como veio, sem esconder causa',
      );
    });
  });

  group('pedido do código', () {
    Future<_FakeRecovery> abrir(WidgetTester tester) async {
      final servico = _FakeRecovery();
      await tester.pumpWidget(
        MaterialApp(
          theme: OrionTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PasswordRecoveryScreen(
                        initialEmail: 'Tecnico@Orion.com ',
                        service: servico,
                      ),
                    ),
                  ),
                  child: const Text('tela de login'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('tela de login'));
      await tester.pumpAndSettle();
      return servico;
    }

    testWidgets('traz o e-mail já digitado e envia o código', (tester) async {
      final servico = await abrir(tester);

      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();

      expect(servico.emailsEnviados, ['Tecnico@Orion.com ']);
      expect(find.text('Digite o código'), findsOneWidget);
      expect(
        find.textContaining('tecnico@orion.com'),
        findsOneWidget,
        reason: 'o aviso mostra o e-mail normalizado, para conferência',
      );
    });

    testWidgets('código inválido não chega ao servidor', (tester) async {
      final servico = await abrir(tester);
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'abc');
      await tester.tap(find.text('Confirmar código'));
      await tester.pumpAndSettle();

      expect(find.textContaining('só números'), findsOneWidget);
      expect(servico.codigosConferidos, isEmpty);
    });

    testWidgets('código aceito tira a tela da frente', (tester) async {
      final servico = await abrir(tester);
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '123 456');
      await tester.tap(find.text('Confirmar código'));
      await tester.pumpAndSettle();

      expect(servico.codigosConferidos, ['123 456']);
      expect(
        find.text('tela de login'),
        findsOneWidget,
        reason:
            'a tela sai para o gate mostrar a senha nova, que fica por baixo',
      );
      expect(find.text('Digite o código'), findsNothing);
    });

    testWidgets('código recusado mostra o motivo e permanece', (tester) async {
      final servico = await abrir(tester);
      servico.falhaNaConferencia = const AuthException(
        'Token has expired or is invalid',
      );
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '000000');
      await tester.tap(find.text('Confirmar código'));
      await tester.pumpAndSettle();

      expect(find.textContaining('inválido ou expirado'), findsOneWidget);
      expect(find.text('Digite o código'), findsOneWidget);
    });
  });

  group('senha nova', () {
    Future<(_FakeRecovery, List<bool>)> abrir(WidgetTester tester) async {
      final servico = _FakeRecovery();
      final concluido = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: OrionTheme.light(),
          home: NewPasswordScreen(
            service: servico,
            onCompleted: () => concluido.add(true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (servico, concluido);
    }

    Future<void> preencher(
      WidgetTester tester,
      String senha,
      String repeticao,
    ) async {
      await tester.enterText(find.byType(TextFormField).at(0), senha);
      await tester.enterText(find.byType(TextFormField).at(1), repeticao);
      await tester.tap(find.text('Salvar senha'));
      await tester.pumpAndSettle();
    }

    testWidgets('senhas diferentes não são enviadas', (tester) async {
      final (servico, concluido) = await abrir(tester);
      await preencher(tester, 'orion-2026', 'orion-2027');

      expect(find.text('As senhas não conferem.'), findsOneWidget);
      expect(servico.senhasGravadas, isEmpty);
      expect(concluido, isEmpty);
    });

    testWidgets('senha válida é gravada e libera o sistema', (tester) async {
      final (servico, concluido) = await abrir(tester);
      await preencher(tester, 'orion-2026', 'orion-2026');

      expect(servico.senhasGravadas, ['orion-2026']);
      expect(concluido, [true]);
    });

    testWidgets('recusa do servidor mantém a tela com o motivo', (
      tester,
    ) async {
      final (servico, concluido) = await abrir(tester);
      servico.falhaNaGravacao = const AuthException(
        'New password should be different from the old password.',
      );
      await preencher(tester, 'orion-2026', 'orion-2026');

      expect(find.textContaining('diferente da anterior'), findsOneWidget);
      expect(concluido, isEmpty);
    });

    testWidgets('cancelar encerra a sessão de recuperação', (tester) async {
      final (servico, concluido) = await abrir(tester);
      await tester.tap(find.text('Cancelar e voltar ao login'));
      await tester.pumpAndSettle();

      expect(servico.cancelamentos, 1);
      expect(concluido, isEmpty);
    });
  });
}

class _FakeRecovery implements PasswordRecoveryService {
  final List<String> emailsEnviados = [];
  final List<String> codigosConferidos = [];
  final List<String> senhasGravadas = [];
  int cancelamentos = 0;
  Object? falhaNaConferencia;
  Object? falhaNaGravacao;

  @override
  Future<void> sendCode(String email) async => emailsEnviados.add(email);

  @override
  Future<void> verifyCode(String email, String code) async {
    final falha = falhaNaConferencia;
    if (falha != null) throw falha;
    codigosConferidos.add(code);
  }

  @override
  Future<void> updatePassword(String password) async {
    final falha = falhaNaGravacao;
    if (falha != null) throw falha;
    senhasGravadas.add(password);
  }

  @override
  Future<void> cancel() async => cancelamentos++;
}
