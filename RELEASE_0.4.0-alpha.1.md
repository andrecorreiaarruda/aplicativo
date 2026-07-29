# Release 0.4.0-alpha.1

## Entrega

- SQLite multiplataforma;
- fallback seguro em memória;
- snapshot persistente da base local;
- fila SQL de alterações offline;
- metadados de última sincronização e erros;
- indicador de armazenamento no cabeçalho;
- testes de reidratação e fila;
- migration de fundação para conflitos no Supabase.

## Não concluído neste marco

O replay da fila e o pull incremental do Supabase serão implementados no alpha seguinte. Esta separação evita ativar sincronização bidirecional antes de existir uma política testada de conflito e exclusão lógica.
