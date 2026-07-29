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
