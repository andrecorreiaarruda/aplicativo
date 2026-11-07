# ORION ServiceLog AI

Aplicativo Flutter de registro técnico e histórico de atendimentos, com
funcionamento offline-first e sincronização com o Supabase.

Versão do pacote: `0.4.0-alpha.2+21` (ver `pubspec.yaml`).

## Funcionalidades

### Cadastros e atendimentos

- clientes, locais, equipamentos e atendimentos, todos editáveis;
- número de série opcional, mas único na organização quando informado;
- datas de abertura e conclusão informadas no formulário, para lançar
  histórico antigo com a data real;
- sessões de trabalho e tempos de atendimento calculados no servidor.

### Arquivamento e exclusão

- arquivar e restaurar clientes, equipamentos e atendimentos pela tela
  **Arquivados**; exige papel com permissão de escrita;
- arquivar é recusado enquanto houver histórico dependente, com a
  contagem na mensagem (ordem: atendimento, equipamento, cliente);
- exclusão definitiva a partir de **Arquivados**, só para registro já
  arquivado, só para o papel administrador e só sem dependentes, inclusive
  os arquivados.

### Ordem de serviço em PDF

- emitida a partir do cartão do atendimento, no modelo de OS da ORION,
  gerada no próprio aplicativo, sem rede;
- salva em `Documentos/ORION ServiceLog/Ordens de serviço`, com data e
  hora no nome do arquivo, e aberta para conferência;
- os dados do emitente (empresa, CNPJ, responsável, registro etc.) ficam
  numa tela própria no menu da conta e são obrigatórios para emitir;
- complementos que o atendimento não guarda (solicitante, patrimônio,
  materiais, testes, situação final) são preenchidos na janela da OS e
  lembrados para a próxima emissão;
- a emissão fica bloqueada para atendimento criado offline até ele
  sincronizar, porque o número ainda é provisório.

### Conta e aparência

- recuperação de senha por código de uso único enviado por e-mail;
- modo escuro, com seletor Sistema / Claro / Escuro no menu da conta,
  guardado no computador.

### Offline-first e sincronização

- SQLite local como fonte operacional;
- snapshot local e fila de envio gravados na mesma transação;
- UUID gerado no dispositivo;
- fila compactada e persistente, com replay idempotente automático,
  manual e com nova tentativa progressiva;
- cache de perfil para reabertura offline;
- download remoto paginado por chave, sem corte silencioso de registros;
- conflitos por revisão, com tela para descartar a alteração local ou
  sobrescrever o servidor;
- fallback local para pesquisa.

### Backend

- autorização por papel e isolamento por organização nas gravações
  diretas e no replay offline (ver `docs/30_BACKEND_AUTHORIZATION.md`).

## Execução Linux

```bash
sudo apt install -y libsqlite3-0 libsqlite3-dev
flutter pub get
dart run sqflite_common_ffi_web:setup --force
flutter analyze
flutter test
flutter run -d linux
```

## Instalação como aplicativo (Linux)

Para usar sem terminal, com ícone no menu:

```bash
./scripts/install-linux.sh
```

O script compila em modo release, instala o bundle em
`~/.local/share/orion-servicelog` e registra um lançador. Não requer root.

As credenciais do Supabase são resolvidas em tempo de compilação por
`String.fromEnvironment`, então o script passa `.env` ao build
automaticamente. Sem esse arquivo o aplicativo é instalado sem backend e
funciona apenas com dados locais — o script avisa quando isso acontece.

```bash
./scripts/install-linux.sh --uninstall   # remove, preservando os dados locais
./scripts/install-linux.sh --no-build    # reinstala o bundle já compilado
```

Para atualizar depois de mudar o código, rode o script de novo.

## Backend

Aplique todas as migrations de `supabase/migrations`, até a mais recente:

```text
supabase/migrations/20260918120000_purge_operations.sql
```

```bash
npx supabase db push
```

Bancos criados a partir da `0001` precisam da `0013` antes do primeiro uso
real: sem ela, um gatilho impede gravar atendimentos.

Não exponha o schema `orion_private` na Data API. A configuração local
versionada expõe somente `public` e `graphql_public`.

### E-mail de recuperação de senha

O modelo de fábrica do Supabase envia um link, que o aplicativo de desktop
não tem como receber. O modelo em `supabase/templates/recovery.html` envia
o código (`{{ .Token }}`) que a pessoa digita na tela **Recuperar senha**.

- Supabase local: já registrado em `supabase/config.toml`.
- Produção: cole o conteúdo do arquivo no painel, em
  Authentication → Emails → Templates → Reset Password.

### Execução conectada

```bash
flutter run -d linux --dart-define-from-file=.env
```

### Testes do banco

Os testes pgTAP de autorização ficam em `supabase/tests`. Os comandos e os
requisitos (Docker, Supabase CLI) estão em
`docs/30_BACKEND_AUTHORIZATION.md`.

## Teste offline

Entre online uma vez, desconecte a rede, crie registros e reinicie o
aplicativo. Depois restabeleça a conexão e use o chip de sincronização no
cabeçalho. Se houver conflito, o chip leva à tela de resolução.

## Documentação

- `docs/10_OFFLINE_SYNC.md` — fluxo offline-first e sincronização;
- `docs/20_KNOWN_LIMITATIONS.md` — limitações conhecidas;
- `docs/30_BACKEND_AUTHORIZATION.md` — autorização do backend e testes pgTAP;
- `docs/40_TRANSACTIONAL_OUTBOX.md` — outbox transacional no SQLite.

## Limites

- download remoto completo, não incremental: cada tabela é lida em páginas
  de 500 registros, e uma base acima de 200 páginas falha com erro em vez
  de ser truncada;
- anexos não funcionam offline;
- a OS sai num modelo único e fica só no computador que a emitiu: o PDF,
  os complementos e os dados do emitente não sobem para o servidor, e não
  há assinatura digital;
- sem gestão de usuários e convites;
- o assistente local usa busca heurística, sem embeddings.
