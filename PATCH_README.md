# Patch 0.4.0-alpha.2 — replay offline

Este ZIP foi preparado para ser extraído diretamente na raiz do aplicativo Flutter, onde está o `pubspec.yaml`.

```bash
cd ~/Projetos/orion-servicelog
unzip -o ~/Downloads/orion-servicelog-offline-replay-patch-0.4.0-alpha.2.zip -d .
flutter clean
rm -rf .dart_tool build
flutter pub get
dart run sqflite_common_ffi_web:setup --force
dart format lib test
flutter analyze
flutter test
```

A pasta `supabase/` do patch contém apenas a nova migration para ser copiada/aplicada no repositório completo do backend:

```bash
npx supabase db push
```
