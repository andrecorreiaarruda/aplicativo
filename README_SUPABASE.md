# ORION ServiceLog AI — Backend Supabase 0.4.0-alpha.2

Este pacote deve ser extraído na raiz do projeto Flutter, no mesmo nível de `pubspec.yaml`.

Estrutura esperada:

```text
orion-servicelog/
├── pubspec.yaml
├── lib/
├── assets/
├── test/
└── supabase/
    ├── migrations/
    ├── functions/
    └── seed.sql
```

## Inicialização

Na raiz do projeto:

```bash
npx supabase init
```

Se a CLI perguntar se deve substituir a pasta existente, não apague os arquivos de migrations/functions. O objetivo é criar `supabase/config.toml`.

Depois:

```bash
npx supabase projects list
npx supabase link --project-ref SEU_REFERENCE_ID_REAL
npx supabase db push --dry-run
npx supabase db push
```

O Project Ref deve ser o Reference ID de 20 caracteres exibido no painel do Supabase, não o nome do projeto nem a URL.

## Segredos das Edge Functions

`SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` já são injetados automaticamente pelo runtime do Supabase — não precisam ser configurados manualmente. Os demais precisam ser definidos antes do deploy das functions:

```bash
npx supabase secrets set OPENAI_API_KEY=sk-...
# Opcional — padrão: text-embedding-3-small
npx supabase secrets set OPENAI_EMBEDDING_MODEL=text-embedding-3-small

npx supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
# Opcional — padrão: claude-sonnet-5
npx supabase secrets set ANTHROPIC_EXPLANATION_MODEL=claude-sonnet-5
```

`OPENAI_API_KEY` é usado por `generate-case-embedding` e `search-similar-cases` para gerar embeddings (essencial — sem ele a busca por IA não funciona). `ANTHROPIC_API_KEY` é usado só por `search-similar-cases`, para gerar uma explicação em linguagem natural de cada caso recuperado; é opcional em tempo de execução — se não estiver configurado, a busca continua funcionando normalmente, só sem essas explicações.

