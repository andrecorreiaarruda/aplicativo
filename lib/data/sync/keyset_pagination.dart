/// Percurso de todas as páginas de uma consulta, por chave.
///
/// O PostgREST limita cada resposta (`max_rows`, 1000 por padrão) e o
/// projeto ainda somava a isso um `limit(300)` explícito nos atendimentos.
/// O corte era silencioso: a aplicação exibia o que coubesse e não havia
/// como distinguir "essa é a base inteira" de "essa é a primeira página".
///
/// A paginação é por chave, não por deslocamento. Deslocamento é instável
/// quando a base muda durante a leitura: um registro inserido antes da
/// posição atual empurra os demais e faz a página seguinte repetir ou
/// pular linhas. Avançar por `id` não tem esse problema, porque o cursor
/// é o último registro efetivamente lido.
///
/// A ordem de exibição não vem daqui: as consultas percorrem por `id` e
/// quem chama ordena depois, sobre o conjunto completo.
library;

/// Lê uma página a partir de [after] (exclusivo), no máximo [limit] linhas,
/// ordenada pela chave de forma crescente.
typedef PageReader<T> = Future<List<T>> Function(String? after, int limit);

/// Percorre todas as páginas e devolve o conjunto completo.
///
/// Lança [StateError] ao ultrapassar [maxPages]. É deliberado: um corte
/// silencioso é exatamente o defeito que esta função existe para eliminar,
/// e devolver um resultado parcial sem aviso o reintroduziria por outro
/// caminho. O limite é alto o bastante para não ser alcançado em uso
/// normal; alcançá-lo indica base grande demais para carga integral, que
/// é o caso a ser resolvido por sincronização incremental.
Future<List<T>> fetchAllPages<T>({
  required PageReader<T> readPage,
  required String Function(T row) keyOf,
  int pageSize = 500,
  int maxPages = 200,
}) async {
  if (pageSize < 1) {
    throw ArgumentError.value(pageSize, 'pageSize', 'Precisa ser positivo.');
  }
  if (maxPages < 1) {
    throw ArgumentError.value(maxPages, 'maxPages', 'Precisa ser positivo.');
  }

  final todos = <T>[];
  String? cursor;

  for (var pagina = 0; pagina < maxPages; pagina++) {
    final linhas = await readPage(cursor, pageSize);
    todos.addAll(linhas);

    // Página incompleta significa fim: não há o que buscar adiante.
    if (linhas.length < pageSize) return todos;

    final proximo = keyOf(linhas.last);
    // Cursor parado indicaria chave repetida ou consulta que ignora o
    // `after`; seguir adiante repetiria a mesma página para sempre.
    if (proximo == cursor) {
      throw StateError(
        'Paginação não avançou: a chave "$proximo" repetiu entre páginas.',
      );
    }
    cursor = proximo;
  }

  throw StateError(
    'Paginação excedeu $maxPages páginas de $pageSize registros. '
    'A carga integral não é adequada a esta base; use sincronização '
    'incremental.',
  );
}
