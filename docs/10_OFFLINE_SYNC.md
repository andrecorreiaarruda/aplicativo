# Offline-first e sincronização — 0.4.0-alpha.2

## Estado implementado

O aplicativo usa o SQLite como fonte operacional no dispositivo. Toda gravação de cliente, local, modelo, equipamento ou atendimento ocorre primeiro no banco local e é imediatamente disponibilizada à interface, mesmo sem conexão.

A versão alpha.2 implementa:

- snapshot local persistente no SQLite;
- IDs UUID gerados no dispositivo;
- fila persistente de operações;
- compactação de múltiplas alterações da mesma entidade;
- envio automático após gravações e na abertura do aplicativo;
- nova tentativa com espera progressiva após falha de rede;
- tentativa de sincronização ao retornar ao aplicativo;
- sincronização manual pelo cabeçalho;
- replay idempotente no Supabase;
- recibos de operações já aplicadas;
- revisão otimista por registro;
- registro de conflitos no servidor;
- download seguro do estado remoto após o envio;
- cache local do perfil e organização para reabertura offline;
- pesquisa local como fallback quando a consulta remota não estiver disponível.

## Fluxo de gravação

```text
Formulário Flutter
      ↓
Repositório offline-first
      ↓
Snapshot SQLite + fila persistente
      ↓
Interface atualizada imediatamente
      ↓
RPC apply_offline_operation quando houver conexão
      ↓
Recibo idempotente + revisão do servidor
      ↓
Reconciliação do snapshot remoto
```

## Idempotência

Cada operação recebe um UUID. O servidor registra o resultado em `sync_operation_receipts`. Se o mesmo UUID for reenviado após uma queda de conexão, o RPC devolve o resultado anterior sem criar uma duplicata.

## Revisões e conflitos

O payload local contém `_base_revision`, correspondente à última revisão remota conhecida. O servidor compara esse valor com `sync_revision`.

Quando as revisões divergem:

1. a alteração não é aplicada automaticamente;
2. o servidor grava `client_payload` e `server_payload` em `sync_conflicts`;
3. a operação permanece na fila local;
4. o cabeçalho indica a existência do conflito;
5. causa-raiz, solução e validação não são sobrescritas silenciosamente.

A interface completa de resolução de conflitos ainda é o próximo marco. Nesta versão, o conflito é preservado e exige intervenção técnica no backend ou em futura tela específica.

## Pull remoto

Depois que todas as operações pendentes são aceitas, o aplicativo baixa um snapshot remoto completo e substitui sua cópia local. Esta estratégia é deliberadamente conservadora para o primeiro ciclo de homologação.

O pull incremental por cursor, paginação e tombstones será implementado antes do beta. O snapshot completo atual não é adequado para bases muito grandes e está sujeito aos limites de linhas das consultas remotas.

## Retry

Falhas temporárias agendam nova tentativa aproximadamente em 15, 30, 60, 120 e 300 segundos. Uma sincronização bem-sucedida reinicia essa progressão. Também há nova tentativa quando o aplicativo volta ao estado `resumed`.

## Estruturas locais

### `app_snapshots`

Um documento JSON por namespace contém o estado operacional local.

### `sync_queue`

Cada operação contém UUID, namespace, entidade, ID, operação, payload, data, número de tentativas e último erro.

### `app_metadata`

Armazena perfil em cache, última sincronização, último erro e metadados do repositório.

## Estruturas remotas

- `sync_operation_receipts`: idempotência;
- `sync_conflicts`: evidências para resolução;
- `sync_revision`: controle otimista;
- `client_updated_at`: data informada pelo dispositivo;
- `deleted_at`: preparação para exclusão lógica.

## Tratamento de falhas no replay

Cada operação da fila é enviada de forma independente. Uma operação recusada
pelo servidor é registrada e mantida na fila, mas não interrompe o envio das
seguintes nem impede o pull do snapshot remoto. O primeiro erro é preservado e
relançado ao final, para que a interface continue reportando a falha.

Antes desta mudança, o laço abortava na primeira recusa: uma única operação
problemática bloqueava indefinidamente todo o restante da fila.

## Conflitos por chave natural

O `on conflict (id)` do corpo da RPC resolve apenas colisão de chave primária.
Quando dois dispositivos criam offline a mesma entidade natural — o mesmo
cliente, o mesmo número de série — cada um gera um UUID próprio, e a segunda
gravação viola a restrição de chave natural.

Essas violações passaram a ser capturadas e registradas em `sync_conflicts`,
com a constraint violada em `server_payload`. O cliente as recebe como
`status: 'conflict'`, o mesmo tratamento já usado para conflito de revisão.
Antes, subiam como exceção genérica e o dispositivo retentava sem nunca
progredir.

A criação implícita de fabricante é a exceção: ela usa um "select, e se nulo
insere" que não é atômico, então uma corrida entre dispositivos não indica
divergência de dados — o vencedor gravou exatamente o que o perdedor queria.
Nesse caso a operação é repetida uma vez, e a segunda tentativa reaproveita o
registro já commitado.

## Arquivamento

`archive` e `restore` entraram na fila como operações próprias, ao lado de
`upsert`. Elas preenchem e limpam `deleted_at`, coluna criada na `0001` e
até então sem uso: o registro sai das listagens e continua no banco.

Arquivar é recusado enquanto houver histórico dependente — um cliente com
equipamentos, um equipamento com atendimentos. A ordem obrigatória é
atendimento, equipamento, cliente. A checagem existe no cliente, para
resposta imediata, e no servidor, que é quem decide: offline o dispositivo
não enxerga o que os outros criaram. A recusa do servidor chega como
conflito, com as contagens em `server_payload`.

O pull descarta registros com `deleted_at` preenchido, então o espelho
local só conhece os arquivamentos feitos no próprio dispositivo e ainda
não sincronizados. A tela de restauração consulta o servidor à parte, com
o estado local como alternativa quando não há rede.

## Estrutura da RPC

O corpo vive em `orion_private.apply_offline_operation`, com isolamento
por organização reforçado. A função pública é um invólucro fino que trata
`archive`/`restore` e violação de chave natural, e delega o restante.

Duas linhas de trabalho chegaram a essa separação de forma independente —
uma pela `0011`, outra pela migration de autorização. A migration
`20260912120000` reconcilia as duas, mantendo um único corpo.

## Estrutura da RPC (histórico)

A lógica de `apply_offline_operation` vive em uma única definição,
`apply_offline_operation_impl`. A função pública é um invólucro fino que
delega a ela e traduz `unique_violation` em conflito registrado.

Até a migration `0010`, cada alteração reescrevia por completo as cerca de 460
linhas do corpo, e havia três cópias divergentes no repositório. A partir da
`0011`, mudanças na lógica alteram o corpo e mudanças no tratamento de erro
alteram o invólucro, sem que uma exija copiar a outra.

## Paginação do download

Todas as leituras remotas percorrem a tabela inteira em páginas, em vez de
aceitar o corte do servidor. Antes, os atendimentos tinham `limit(300)`
explícito e as demais consultas eram truncadas em silêncio pelo `max_rows`
do PostgREST — não havia como distinguir "esta é a base inteira" de "esta é
a primeira página".

O percurso é por chave (`id`), não por deslocamento. Deslocamento é instável
quando a base muda durante a leitura: um registro inserido antes da posição
atual empurra os demais e faz a página seguinte repetir ou pular linhas.
A ordem de exibição é aplicada depois, sobre o conjunto completo.

Ultrapassar o limite de páginas lança erro em vez de devolver resultado
parcial. Um corte silencioso é o defeito que a paginação existe para
eliminar, e devolvê-lo por outro caminho seria o mesmo problema com outro
nome. Alcançar esse limite indica base grande demais para carga integral —
o caso da sincronização incremental, ainda não implementada.

## Limites atuais

- pull remoto completo e paginado, ainda não incremental: toda
  sincronização relê a base inteira;
- conflitos são detectados e isolados, mas não resolvidos pela interface;
- exclusões e tombstones ainda não estão expostos no Flutter;
- anexos não são armazenados offline;
- a sessão autenticada ainda depende do comportamento de persistência do cliente Supabase; o perfil e a organização são armazenados localmente após o primeiro acesso online;
- o snapshot operacional ainda é JSON dentro do SQLite, não tabelas normalizadas por entidade.
