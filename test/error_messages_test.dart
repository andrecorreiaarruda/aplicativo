import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/core/errors/error_messages.dart';

void main() {
  test('falta de rede vira uma frase que tranquiliza', () {
    final message = describeError(
      "ClientException with SocketException: Failed host lookup: "
      "'abc.supabase.co' (OS Error: Temporary failure in name resolution)",
    );
    expect(message, startsWith('Sem conexão com o servidor.'));
    expect(message, contains('fica guardado'));
  });

  test('sessão expirada pede novo login', () {
    expect(
      describeError('AuthException(message: JWT expired, statusCode: 401)'),
      contains('sessão expirou'),
    );
  });

  test('recusa de permissão do banco é explicada', () {
    expect(
      describeError(
        'PostgrestException(message: Write permission is required, '
        'code: 42501, details: , hint: null)',
      ),
      'Seu perfil não tem permissão para esta alteração.',
    );
  });

  test('erro do banco mostra só a mensagem', () {
    expect(
      describeError(
        'PostgrestException(message: Só registros arquivados podem ser '
        'excluídos., code: P0001, details: , hint: null)',
      ),
      'Só registros arquivados podem ser excluídos.',
    );
  });

  test('mensagens do próprio aplicativo passam sem mudança', () {
    expect(
      describeError(StateError('Há 2 atendimentos dependentes.')),
      'Há 2 atendimentos dependentes.',
    );
    expect(describeError(Exception('Falhou.')), 'Falhou.');
  });
}
