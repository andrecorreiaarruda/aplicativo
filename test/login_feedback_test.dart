import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/features/auth/login_screen.dart';

void main() {
  group('signUpFeedback', () {
    test('sessão aberta não produz mensagem', () {
      expect(
        signUpFeedback(hasSession: true, identityCount: 1),
        isNull,
      );
    });

    test('identidades vazias apontam e-mail já cadastrado', () {
      final mensagem = signUpFeedback(hasSession: false, identityCount: 0);
      expect(mensagem, contains('já tem conta'));
      expect(mensagem, isNot(contains('Confirme o e-mail')));
    });

    test('cadastro novo pede confirmação', () {
      expect(
        signUpFeedback(hasSession: false, identityCount: 1),
        contains('Confirme o e-mail'),
      );
    });

    test('identidades ausentes caem no caminho conservador', () {
      expect(
        signUpFeedback(hasSession: false, identityCount: null),
        contains('Confirme o e-mail'),
      );
    });
  });
}
