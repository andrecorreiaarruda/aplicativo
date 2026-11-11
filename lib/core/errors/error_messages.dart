/// Texto para mostrar ao usuário a partir de um erro qualquer.
///
/// Os erros de rede e do Supabase chegam como texto técnico em inglês —
/// "ClientException with SocketException: Failed host lookup..." —, e era
/// isso que aparecia na faixa vermelha ao sincronizar sem internet. As
/// mensagens escritas pelo próprio aplicativo (StateError com texto em
/// português) passam sem mudança.
String describeError(Object error) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  bool has(Iterable<String> needles) => needles.any(lower.contains);

  if (has(const [
    'socketexception',
    'failed host lookup',
    'connection refused',
    'connection reset',
    'connection closed',
    'network is unreachable',
    'clientexception',
    'handshakeexception',
    'xmlhttprequest error',
  ])) {
    return 'Sem conexão com o servidor. O que foi alterado fica guardado '
        'neste computador e é enviado quando a conexão voltar.';
  }
  if (has(const ['timeoutexception', 'timed out'])) {
    return 'O servidor demorou a responder. Tente de novo em instantes.';
  }
  if (has(const [
    'jwt expired',
    'invalid jwt',
    'refresh token',
    'not authenticated',
    'authsessionmissing',
  ])) {
    return 'A sessão expirou. Saia e entre de novo para sincronizar.';
  }
  if (has(const ['42501', 'permission denied', 'write permission'])) {
    return 'Seu perfil não tem permissão para esta alteração.';
  }

  // Erros do banco trazem a mensagem útil num campo `message:`.
  final postgrest = RegExp(
    r'PostgrestException\(message: (.*?), code:',
    dotAll: true,
  ).firstMatch(raw);
  if (postgrest != null) return postgrest.group(1)!.trim();

  for (final prefix in const ['Exception: ', 'Bad state: ']) {
    if (raw.startsWith(prefix)) return raw.substring(prefix.length);
  }
  return raw;
}
