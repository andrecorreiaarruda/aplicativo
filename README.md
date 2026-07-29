# ORION ServiceLog AI — Flutter 0.4.0-alpha.2

Segundo marco da fundação offline-first.

## Implementado

- SQLite local como fonte operacional;
- repositório offline-first para Supabase;
- gravação local imediata;
- UUID gerado no dispositivo;
- fila compactada e persistente;
- replay automático, manual e com retry;
- cache de perfil para reabertura offline;
- reconciliação por snapshot remoto;
- conflitos por revisão;
- fallback local para pesquisa.

## Execução Linux

```bash
sudo apt install -y libsqlite3-0 libsqlite3-dev
flutter pub get
dart run sqflite_common_ffi_web:setup --force
flutter analyze
flutter test
flutter run -d linux
```

## Backend

Aplique todas as migrations, inclusive:

```text
supabase/migrations/0008_offline_operation_replay.sql
```

```bash
npx supabase db push
```

Execute conectado:

```bash
flutter run -d linux --dart-define-from-file=.env
```

## Teste offline

Entre online uma vez, desconecte a rede, crie registros e reinicie o aplicativo. Depois restabeleça a conexão e use o chip de sincronização no cabeçalho.

## Limites

- pull completo, não incremental;
- conflitos sem tela de resolução;
- sem exclusões sincronizadas na interface;
- sem anexos offline.
