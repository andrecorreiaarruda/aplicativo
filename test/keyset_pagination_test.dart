import 'package:flutter_test/flutter_test.dart';
import 'package:servicelog_ai/data/sync/keyset_pagination.dart';

/// Base simulada, ordenada por chave, que responde como o PostgREST:
/// devolve no máximo `limit` linhas com chave maior que `after`.
class _BaseFalsa {
  _BaseFalsa(this.chaves);

  final List<String> chaves;
  final List<String?> cursoresRecebidos = [];

  Future<List<String>> lerPagina(String? after, int limit) async {
    cursoresRecebidos.add(after);
    final restantes = after == null
        ? chaves
        : chaves.where((c) => c.compareTo(after) > 0).toList();
    return restantes.take(limit).toList();
  }
}

String _chave(String linha) => linha;

List<String> _sequencia(int quantas) =>
    List.generate(quantas, (i) => 'k${i.toString().padLeft(4, '0')}');

void main() {
  test('base vazia devolve lista vazia sem segunda leitura', () async {
    final base = _BaseFalsa([]);
    final todos = await fetchAllPages(
      readPage: base.lerPagina,
      keyOf: _chave,
      pageSize: 10,
    );
    expect(todos, isEmpty);
    expect(base.cursoresRecebidos, [null]);
  });

  test('página incompleta encerra o percurso', () async {
    final base = _BaseFalsa(_sequencia(7));
    final todos = await fetchAllPages(
      readPage: base.lerPagina,
      keyOf: _chave,
      pageSize: 10,
    );
    expect(todos, hasLength(7));
    expect(base.cursoresRecebidos, hasLength(1));
  });

  test('percorre várias páginas sem repetir nem pular', () async {
    final esperado = _sequencia(25);
    final base = _BaseFalsa(esperado);
    final todos = await fetchAllPages(
      readPage: base.lerPagina,
      keyOf: _chave,
      pageSize: 10,
    );
    expect(todos, esperado);
    expect(todos.toSet(), hasLength(25));
    // Cada página avança a partir do último lido.
    expect(base.cursoresRecebidos, [null, 'k0009', 'k0019']);
  });

  test(
    'total múltiplo exato do tamanho da página faz leitura final vazia',
    () async {
      // Caso clássico de erro: sem a leitura extra, o código não sabe que
      // acabou; com ela, a página vazia encerra.
      final base = _BaseFalsa(_sequencia(20));
      final todos = await fetchAllPages(
        readPage: base.lerPagina,
        keyOf: _chave,
        pageSize: 10,
      );
      expect(todos, hasLength(20));
      expect(base.cursoresRecebidos, hasLength(3));
    },
  );

  test(
    'cursor que não avança é recusado em vez de repetir para sempre',
    () async {
      // Consulta que ignora o `after` devolveria a mesma página sempre.
      Future<List<String>> sempreIgual(String? after, int limit) async =>
          _sequencia(limit);

      await expectLater(
        fetchAllPages(readPage: sempreIgual, keyOf: _chave, pageSize: 5),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'mensagem',
            contains('repetiu'),
          ),
        ),
      );
    },
  );

  test(
    'excesso de páginas falha em voz alta, sem truncar em silêncio',
    () async {
      final base = _BaseFalsa(_sequencia(100));
      await expectLater(
        fetchAllPages(
          readPage: base.lerPagina,
          keyOf: _chave,
          pageSize: 10,
          maxPages: 3,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'mensagem',
            contains('incremental'),
          ),
        ),
      );
    },
  );

  test('tamanho de página inválido é recusado', () async {
    await expectLater(
      fetchAllPages<String>(
        readPage: (_, __) async => const <String>[],
        keyOf: _chave,
        pageSize: 0,
      ),
      throwsArgumentError,
    );
  });
}
