# Revisão geral — novembro de 2026

Revisão do projeto inteiro em quatro frentes: segurança, falhas e
inconsistências, desempenho e interface. Este documento registra o que foi
encontrado, o que foi corrigido e o que ficou para decisão.

## Como foi verificado

- **Banco**: PostgreSQL 16 local com as 20 migrations aplicadas em ordem,
  pgvector e pgTAP. Auditoria do estado final (RLS, políticas, concessões,
  funções `SECURITY DEFINER`) e os testes do projeto: **215 verificações**
  (195 + 6 existentes, 14 novas).
- **Aplicativo**: `flutter analyze` sem avisos e **144 testes**.
- **Funções do servidor**: checagem de tipos em modo estrito.
- **Interface**: capturas de todas as telas, em claro e escuro, antes e
  depois.
- **Histórico do Git**: busca por chaves e tokens em todos os commits —
  nenhum encontrado.

## Segurança

### Corrigido

| Achado | Gravidade | Correção |
|---|---|---|
| A RPC devolvia o recibo de uma operação já aplicada antes de conferir o papel. Um usuário de Consulta que reenviasse o identificador recebia o resultado em vez da recusa. | Média | Migration `20261110120000`: papel conferido primeiro. |
| Técnico, gestor e engenheiro podiam apagar clientes, locais, equipamentos e atendimentos direto pela API, contornando as travas da exclusão definitiva. | Média | Exclusão direta só do administrador. |
| A busca por casos semelhantes devolvia atendimentos arquivados. | Baixa | Filtro `deleted_at is null`. |
| `bootstrap_organization`, `search_similar_cases` e auxiliares executáveis por `anon`. | Baixa | `EXECUTE` revogado de `anon` e `public`. |
| Funções `SECURITY DEFINER` sem `pg_temp` no fim do `search_path`. | Baixa | `search_path = public, pg_temp`. |
| Funções de busca sem limite de tamanho de entrada: qualquer conta autenticada podia gerar custo na OpenAI e na Anthropic com textos enormes. | Média | Teto de caracteres, UUID validado, limite inteiro, texto do modelo com tamanho limitado. |
| No Linux e no macOS, a pasta com o banco local e a sessão do Supabase nascia legível por todos os usuários do sistema. | Média | Pasta passa a modo 700 na abertura. |
| O repositório Supabase tinha um caminho de escrita direta nas tabelas, sem uso, que contornava as regras da RPC. | Baixa | Removido. |

### Conferido e sem problema

- Todas as tabelas têm RLS; nenhuma concessão a `anon`.
- As políticas isolam por organização, com o perfil ativo lido do banco.
- `orion_private` não está nos schemas expostos pela API.
- O aplicativo usa só a chave publicável; a secreta não aparece no código
  nem no histórico.
- As funções do servidor validam a sessão antes de qualquer chamada paga
  e usam a chave de serviço só para gravar o embedding do atendimento que
  o usuário já podia ler.

### Fica para decisão

- **O repositório é público.** O código não tem segredos, mas o histórico
  guarda um número de registro profissional num comentário antigo.
  Torná-lo privado é em Settings → General → Danger Zone no GitHub.
- **Banco local sem criptografia** e **dados que permanecem após sair da
  conta**: aceitável em computador pessoal; em máquina compartilhada ou
  notebook de campo, criptografia de disco resolve os dois.
- **Sem limite de consultas por usuário** nas funções de busca.
- Ver `20_KNOWN_LIMITATIONS.md` para a lista completa.

## Falhas e inconsistências

| Achado | Correção |
|---|---|
| As revisões usadas na detecção de conflito vinham de consultas sem paginação. Acima de mil registros numa tabela, o resto ficava com revisão zero, o que desliga a verificação de conflito no servidor. | Revisões coletadas pelas próprias consultas paginadas do download. |
| Uma sincronização que terminasse depois de sair da conta avisava um controlador já descartado e lançava erro. | Avisos ignorados após o descarte. |
| Gravação com referência a registro que não existe mais mostrava "No element". | Mensagem que diz o que sumiu e o que fazer. |
| Erros de rede e do Supabase apareciam em inglês técnico. | `describeError` e `describeLoginError`. |
| A contagem de equipamentos por cliente comparava pelo nome do cliente. | Compara pelo local. |
| Estilos de texto soltos em botões e na barra lateral perdiam a fonte do tema. | Derivados da tipografia do tema. |
| O teste 191 do banco falhava desde a migration de exclusão definitiva. | Corrigido junto com a regressão que ele acusava. |

## Desempenho

Medido com 3.000 atendimentos (base local de 4,1 MB).

| O quê | Antes | Depois |
|---|---|---|
| Salvar um atendimento e recarregar as listas | ~460 ms¹ | 57 ms |
| Suíte de testes | 30 s | 17 s |

¹ Estimado: 102 ms medidos depois de tirar os atrasos, mais os três
atrasos fixos de 120 ms que essa operação atravessava. O valor "depois"
foi medido.

- O repositório local tinha **120 ms de atraso fixo** em cada leitura e
  gravação, herdado do modo de demonstração e ativo também no modo real.
  Eram 21 pontos; abrir o aplicativo esperava três vezes, salvar, três.
- Cada gravação **serializava a base inteira duas vezes**. A cópia de
  segurança agora só é lida se a gravação falhar, e o JSON de cada
  atendimento fica guardado junto do objeto, que é imutável.
- A sincronização fazia **cinco consultas a mais** por download, só para
  ler revisões.
- As listagens montavam **todos os cartões de uma vez** e refaziam o texto
  de busca de cada registro a cada letra digitada. Agora montam só as
  linhas visíveis, e o filtro é reaproveitado enquanto nada muda.
- Os números do painel eram recalculados a cada reconstrução da tela.

Testado e descartado: o modo WAL do SQLite não trouxe ganho mensurável
nesta carga (a gravação é uma linha grande por transação), então não foi
adotado.

## Interface

O objetivo foi tirar a cara de modelo pronto: muito enfeite, pouca
densidade, texto explicando o óbvio.

- **Tema**: cinzas neutros no lugar do azulado geral; cantos de 6–8 px;
  pesos de fonte 400–600 no lugar de 800–900; barra lateral clara.
- **Listagens**: linhas numa caixa só, no lugar de cartões com ícone em
  quadrado colorido. Cabe cerca do triplo na tela.
- **Situação**: ponto colorido e texto, no lugar da pílula.
- **Painel**: uma faixa de números e duas listas — o que está em aberto e
  o que foi concluído por último.
- **Login**: um formulário no centro, sem painel de slogan.
- **Textos**: saíram os subtítulos que descreviam cada tela e as caixas de
  dica. Os subtítulos que ficaram mostram contagens.
- **"Assistente" virou "Histórico"**, com ícone de busca: é o que a tela
  faz.

## O que precisa ser feito fora do código

1. Aplicar a migration `supabase/migrations/20261110120000_review_hardening.sql`
   no Supabase (SQL Editor, ou `npx supabase db push`).
2. Reimplantar as duas funções:
   `npx supabase functions deploy search-similar-cases` e
   `npx supabase functions deploy generate-case-embedding`.
3. Atualizar o aplicativo: `git pull` e `./scripts/install-linux.sh`.
