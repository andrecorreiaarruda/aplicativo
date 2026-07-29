# ORION ServiceLog AI 0.4.0-alpha.2 — instalação e validação

## 1. Pré-requisitos

- Flutter estável com Dart 3.9 ou superior;
- Git;
- Linux: `libsqlite3-0` e `libsqlite3-dev`;
- Windows desktop: Visual Studio com **Desktop development with C++**;
- Android: Android Studio, SDK e licenças aceitas.

No Ubuntu, Zorin, Linux Mint ou derivados:

```bash
sudo apt update
sudo apt install -y libsqlite3-0 libsqlite3-dev
```

## 2. Atualizar um projeto existente

Após descompactar o patch na raiz do projeto:

```bash
flutter clean
rm -rf .dart_tool build
flutter pub get
dart run sqflite_common_ffi_web:setup --force
dart format lib test
flutter analyze
flutter test
```

O comando de setup web cria:

```text
web/sqlite3.wasm
web/sqflite_sw.js
```

Sem esses arquivos, o app web usa o fallback em memória e apresenta um aviso; Linux e Windows continuam usando SQLite nativo.

## 3. Executar

Linux:

```bash
flutter run -d linux
```

Web em Chrome:

```bash
flutter run -d chrome
```

Web em Brave ou outro navegador:

```bash
flutter run -d web-server --web-port 8080
```

Windows:

```powershell
flutter run -d windows
```

## 4. Local do banco

Em plataformas nativas, o arquivo `orion_servicelog.sqlite` é salvo no diretório de suporte da aplicação. No navegador, o banco é persistido no IndexedDB e fica vinculado à origem/porta utilizada.

Ao testar web, mantenha a mesma porta para conservar os dados:

```bash
flutter run -d web-server --web-port 8080
```

## 5. Executar com Supabase

```bash
flutter run -d linux \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICAVEL
```

Ou:

```bash
flutter run -d linux --dart-define-from-file=.env
```

Nunca coloque `SUPABASE_SERVICE_ROLE_KEY` ou `OPENAI_API_KEY` no Flutter.

## 6. Aplicar as migrations

No projeto completo:

```bash
npx supabase link --project-ref SEU_PROJECT_REF
npx supabase db push
```

A migration `0007_offline_sync_foundation.sql` adiciona:

- `client_updated_at`;
- `sync_revision`;
- `deleted_at`;
- índices de cursor para sincronização incremental.

## 7. Resultado esperado

```text
No issues found!
All tests passed!
```

Ao criar um cliente ou equipamento no modo local, o chip de armazenamento passa a indicar uma alteração pendente. Isso confirma que a operação foi gravada no SQLite e registrada na fila.
