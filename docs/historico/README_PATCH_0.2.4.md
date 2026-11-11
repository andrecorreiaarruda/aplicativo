# Patch ORION ServiceLog 0.2.4

Corrige a incompatibilidade entre `ServiceLogWorkspace` e `OrionBrand`.

O workspace usa o parâmetro nomeado `showProductDetails`; este patch atualiza o construtor de `OrionBrand` para aceitar o parâmetro e mantém as três apresentações responsivas da marca:

- ícone em espaços estreitos;
- logotipo ORION em larguras intermediárias;
- logotipo + ServiceLog AI / Engenharia clínica em desktop amplo.

Aplicação:

```bash
unzip -o orion-servicelog-flutter-sync-patch-0.2.4.zip -d .
flutter clean
rm -rf .dart_tool build
flutter pub get
dart format lib test
flutter analyze
flutter test
```
