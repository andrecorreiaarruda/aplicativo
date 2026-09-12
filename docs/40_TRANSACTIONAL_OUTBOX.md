# Outbox transacional — segunda entrega da 0.5.0

Base: commit `3499a9d` (primeira entrega, autorização do backend).

## Comportamento entregue

- Cada alteração local grava o snapshot e suas operações pendentes em uma única
  transação SQLite. Uma falha reverte o banco e o estado em memória; a chamada
  de salvamento só conclui com sucesso depois do commit.
- Cadastro combinado de cliente e local também é uma única transação.
- Edições ainda não enviadas são compactadas sem perder a versão anterior caso
  a gravação falhe. A ordem persistente da fila mantém pais antes dos dependentes.
- Antes de enviar, a tentativa é registrada em disco. A partir daí, UUID e payload
  são preservados para replay, inclusive após timeout e reabertura do aplicativo.
  Edições posteriores criam uma operação sucessora.
- A confirmação remota atualiza a revisão local, remove a operação confirmada e
  ajusta a revisão base das sucessoras não tentadas no mesmo commit.
- Mutações e leituras locais são serializadas por instância do repositório.
  Requisições de rede não bloqueiam novas edições locais.
- Um download remoto não substitui o snapshot enquanto houver operações locais
  pendentes. Edições durante envio/download permanecem disponíveis, e o controller
  agenda outra tentativa quando restam pendências após uma sincronização.
- Falha ao abrir o SQLite exibe uma tela de recuperação com nova tentativa.
  O aplicativo não abre uma área de trabalho gravável em RAM como alternativa.
  Snapshots inválidos geram erro e são preservados, sem sobrescrita silenciosa.

## Migração e integração

A abertura do banco migra automaticamente o SQLite de v1 para v2, adicionando
`queue_order`. A fila existente mantém a ordem anterior por `created_at`, com
`rowid` como desempate, e preserva UUIDs, payloads e tentativas. Não é necessário
apagar o banco local. Esta entrega não altera migrations ou contratos do backend.

`MemorySnapshotStore` continua disponível para uso explícito em testes/demo,
com as mesmas regras de compactação. A inicialização normal exige SQLite.

O arquivo `pubspec.lock` acompanha a resolução feita pelo Flutter 3.47.2 / Dart
3.13.2 utilizado na validação: matcher, meta, test_api e vector_math foram
atualizados conforme as dependências desse SDK.

## Validação

- Suíte Flutter: 44 testes aprovados, sendo 14 novos.
- SQLite real em arquivos temporários: rollback por falhas injetadas com triggers,
  cadastro composto, falha na compactação e confirmação, namespaces, migração
  v1/v2 com ordem física diferente da cronológica, reabertura, escritas concorrentes
  e preservação de snapshot corrompido.
- Remoto simulado: edição durante envio, resposta perdida após aplicação no
  servidor, replay idempotente e edição durante download.
- Widget: falha de abertura bloqueia a área de trabalho; nova tentativa a libera
  somente após abertura bem-sucedida.

Comandos executados na raiz do repositório:

```sh
flutter --suppress-analytics --no-version-check analyze --no-pub
flutter --suppress-analytics --no-version-check test --no-pub --reporter expanded
```

## Limites e sequência

Os testes de reabertura simulam retomada usando o mesmo arquivo SQLite. Não
substituem testes em aparelhos com encerramento forçado, falta de espaço e
alternância real de conectividade. O teste remoto é simulado; esta entrega não
foi validada ponta a ponta contra um backend implantado nem publicada.

A exclusão mútua local pressupõe uma instância do repositório por namespace;
esta entrega não oferece coordenação de múltiplos processos sobre o snapshot.

Permanecem para as próximas entregas: paginação/sincronização incremental (incluindo
remoção do limite de 300 registros), revisão concorrente no servidor e tratamento
de conflitos/erros que hoje podem interromper a fila. O adiamento do download com
pendências evita sobrescrever edições, mas ainda não é um protocolo incremental.
