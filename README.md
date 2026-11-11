# ORION ServiceLog AI

Registro de atendimentos de engenharia clínica: clientes, equipamentos,
manutenções, instalações e desinstalações, com histórico pesquisável e
ordem de serviço em PDF. Funciona sem internet e sincroniza com o Supabase
quando há conexão.

## O que faz

- **Cadastros**: clientes e locais, fabricantes e modelos, equipamentos.
- **Atendimentos**: abertura, diário de sessões de trabalho, conclusão.
  O tempo técnico sai das sessões; a indisponibilidade é calculada pelo
  servidor.
- **Ordem de serviço**: PDF de uma página no modelo da ORION, emitido a
  partir do atendimento, com os dados do emitente guardados no computador.
- **Histórico**: busca de atendimentos resolvidos parecidos com uma falha
  nova — por similaridade no servidor, ou por texto quando offline.
- **Arquivados**: arquivar, restaurar e excluir de vez (só administrador).
- **Offline primeiro**: tudo é gravado no SQLite local e entra numa fila;
  a fila é enviada quando há rede. Conflitos de edição têm tela própria.
- **Aparência**: claro, escuro ou conforme o sistema.

## Rodar no Linux

```bash
sudo apt install -y libsqlite3-0 libsqlite3-dev
flutter pub get
flutter analyze
flutter test
flutter run -d linux --dart-define-from-file=.env
```

Sem o `.env`, o aplicativo abre em modo de demonstração, só com dados
locais.

## Instalar como aplicativo (Linux)

```bash
./scripts/install-linux.sh
```

Compila em modo release, instala em `~/.local/share/orion-servicelog` e
cria o atalho no menu. Não precisa de root. Para atualizar depois de
baixar código novo, rode de novo.

```bash
./scripts/install-linux.sh --uninstall   # remove, preservando os dados locais
./scripts/install-linux.sh --no-build    # reinstala o que já foi compilado
```

## Configuração (`.env`)

Copie `.env.example` para `.env` e preencha. O arquivo fica fora do Git.

| Chave | Para quê |
|---|---|
| `SUPABASE_URL` | Endereço do projeto no Supabase |
| `SUPABASE_PUBLISHABLE_KEY` | Chave **publicável** (`sb_publishable_…`) |
| `ORION_EMITENTE_*` | Dados padrão do emitente da OS (opcional) |

**Nunca** coloque a chave secreta (`sb_secret_…` ou `service_role`) no
`.env` nem no código: ela ignora todas as regras de acesso do banco, e o
`.env` é embutido no aplicativo compilado.

## Banco de dados

As migrations ficam em `supabase/migrations/` e são aplicadas em ordem:

```bash
npx supabase db push
```

Ou cole o arquivo da migration nova no SQL Editor do painel do Supabase.
`README_SUPABASE.md` cobre o vínculo do projeto e os segredos das funções
de busca.

Os testes do banco (pgTAP) ficam em `supabase/tests/`:

```bash
npx supabase test db --local
```

## Onde ficam os dados

| O quê | Onde |
|---|---|
| Banco local e sessão | `~/.local/share/br.com.orionmed.servicelog_ai/` (só o dono lê) |
| PDFs das OS | `Documentos/ORION ServiceLog/Ordens de serviço/` |
| Dados compartilhados | Supabase, isolados por organização |

## Documentação

- `docs/10_OFFLINE_SYNC.md` — como a fila e a sincronização funcionam
- `docs/20_KNOWN_LIMITATIONS.md` — o que ainda não faz
- `docs/30_BACKEND_AUTHORIZATION.md` — quem pode o quê no banco
- `docs/40_TRANSACTIONAL_OUTBOX.md` — garantias da fila local
- `docs/50_REVISAO_GERAL.md` — revisão de segurança, falhas e desempenho
- `docs/historico/` — notas de versões antigas
