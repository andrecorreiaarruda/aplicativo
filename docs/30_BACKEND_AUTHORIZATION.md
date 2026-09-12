# Autorização do backend — primeira entrega da 0.5.0

Base: commit `b8447b446b8e0a50a41b3352f37a021e00c64878`.

A migration `20260907162623_backend_authorization.sql` protege as gravações
diretas e o replay offline. O contrato usado pelo Flutter permanece igual.
As migrations 0001–0010 não foram alteradas.

## Comportamento

| Operação | Consulta | Técnico / Gestor | Engenheiro / Administrador |
|---|---|---|---|
| Consultar dados da própria organização | Sim | Sim | Sim |
| Consultar catálogo global | Sim | Sim | Sim |
| Criar/editar/excluir dados operacionais da própria organização | Não | Sim | Sim |
| Criar fabricante/modelo/modelo de OS da própria organização | Não | Sim | Sim |
| Editar/excluir catálogo e modelos de OS da própria organização | Não | Não | Sim |
| Alterar catálogo global | Não | Não | Não |
| Gravar em outra organização | Não | Não | Não |

Políticas especiais existentes continuam em vigor: gestão de perfis é do
administrador; resolução de conflitos é de administrador/engenheiro;
leitura de auditoria é de administrador/engenheiro/gestor. Usuário inativo
não tem contexto de organização nem acesso de escrita.

## Mudanças

- Políticas `FOR ALL` permissivas substituídas por leitura e mutações separadas.
- Consulta bloqueado também em anexos, Storage, diário, consultas/feedback de IA
  e criação de itens do catálogo. O controle usa o perfil ativo no banco.
- Cada upsert remoto restringe a organização na cláusula de atualização.
  Uma escrita recusada gera erro `42501` e reverte a operação inteira.
- Atualizações de modelos pela RPC respeitam a restrição já existente nas
  políticas diretas para administrador/engenheiro.
- A implementação privilegiada foi movida para `orion_private`; a função
  pública é um wrapper `SECURITY INVOKER`. A implementação interna exige
  usuário autenticado, organização ativa e papel autorizado.
- Grants de tabelas, sequências e funções são explícitos. O cliente não recebe
  TRUNCATE nem escrita direta em recibos, embeddings ou auditoria.
- Equipamentos só podem referenciar modelos globais ou da mesma organização.
  Ambos os pais de um anexo são validados quando informados.
- O trigger compartilhado de organização usa ramos separados por tabela.
  Isso corrige o erro preexistente `record "new" has no field "site_id"` ao
  inserir um atendimento.
- Search paths dos triggers de datas e de usuário responsável foram fixados.

**Não exponha `orion_private` nos schemas da Data API.** A configuração local
versionada expõe somente `public` e `graphql_public`. O schema privado existe
para manter a implementação privilegiada fora dos endpoints automáticos.

## Validação local reproduzível

Requisitos: Docker em execução, Node/npm e portas 54320–54322 disponíveis.
Ambiente validado: Supabase CLI 2.116.0, PostgreSQL 17.

Na raiz do repositório:

```bash
npx --yes supabase@2.116.0 start --exclude gotrue,realtime,storage-api,imgproxy,kong,mailpit,postgrest,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
npx --yes supabase@2.116.0 test db --local
npx --yes supabase@2.116.0 db advisors --local --type security --level warn
npx --yes supabase@2.116.0 migration list --local
```

Para repetir a instalação limpa, o comando abaixo **recria o banco local**:

```bash
npx --yes supabase@2.116.0 db reset --local --no-seed
npx --yes supabase@2.116.0 test db --local
```

Os testes usam dados fictícios dentro de uma transação e executam rollback.
O seed demonstrativo foi desabilitado na configuração local porque usa um
`ON CONFLICT` incompatível com as constraints alteradas na migration 0004.
Esse seed não é necessário para os testes e não foi corrigido nesta entrega.

## Evidências

- Antes da correção: **5 dos 6 testes mínimos de regressão falharam**.
  O usuário Consulta conseguiu gravar; a RPC alterou um cliente de outra
  organização; as operações indevidas produziram recibos de sucesso.
- Depois da correção: **201 verificações passaram**, em dois arquivos pgTAP.
- A migration final foi aplicada a partir de um banco local recriado e os
  mesmos 201 testes passaram novamente.
- Cobertura: cinco papéis, usuário inativo, anônimo, duas organizações,
  catálogo global, CRUD direto sob o papel `authenticated`, replay via RPC,
  vínculos de anexos/equipamentos, recibos, conflito de revisão, diário e
  cálculo de tempos de atendimento resolvido.
- O advisor mantém um aviso preexistente: extensão `vector` no schema
  `public`. A mudança de schema dessa extensão e a busca semântica não fazem
  parte desta entrega.

Os testes verificam as políticas com os mesmos papéis e claims usados pelo
PostgREST. Não são testes HTTP, do fluxo de login, das Edge Functions ou da
interface em dispositivos. Nenhuma chamada foi feita ao backend de produção.

## Aplicação e próximos passos

Leve esta migration e os testes para a branch de integração e valide primeiro
no ambiente de homologação, com a configuração real da organização. O deploy
deve aplicar somente a nova migration, sem editar ou reaplicar manualmente as
anteriores. Confirme que `orion_private` permanece fora dos schemas expostos.

Esta entrega protege o backend. A interface ainda pode apresentar ações de
edição a usuários Consulta; operações assim serão recusadas pelo servidor.
A atualização da interface e o tratamento de erros permanentes da fila são
etapas seguintes. Não foram alterados o protocolo de concorrência, a
atomicidade SQLite/outbox nem o limite de 300 atendimentos nesta entrega.
