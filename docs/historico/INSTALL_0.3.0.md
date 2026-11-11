# Atualização ORION ServiceLog 0.3.0

Esta atualização elimina a dependência de listas compiladas para clientes e modelos de equipamentos.

## Aplicação no projeto Flutter atual

```bash
cd ~/Projetos/orion-servicelog
unzip -o ~/Downloads/orion-servicelog-dynamic-catalog-patch-0.3.0.zip -d .
flutter clean
rm -rf .dart_tool build
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d linux
```

## Supabase

Quando o aplicativo for conectado ao Supabase, aplique a migration:

```bash
npx supabase db push
```

Ou execute `supabase/migrations/0004_dynamic_master_data.sql` no SQL Editor.

## Novos fluxos

- `Equipamentos > Fabricante / modelo`: cadastra fabricante, família, modelo e modalidade.
- `Equipamentos > Cliente / local`: cadastra cliente ou adiciona novo local a cliente existente.
- `Novo equipamento`: possui atalhos internos para cadastrar modelo e cliente/local sem fechar o formulário.
- No modo demo, os dados passam a permanecer no dispositivo entre reinicializações.
