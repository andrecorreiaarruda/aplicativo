# ORION ServiceLog Flutter — patch 0.2.1

Este patch atualiza o código para versões recentes do Flutter/Dart.

Correções:

- remove import não utilizado de `dart:math`;
- troca `DropdownButtonFormField.value` por `initialValue`;
- troca `Color.withOpacity()` por `Color.withValues(alpha:)`;
- adiciona chaves no validador apontado pelo linter;
- atualiza a versão para `0.2.1+3`.

## Aplicação

Extraia este ZIP sobre a raiz do projeto, permitindo substituir os arquivos existentes.

Depois execute:

```bash
dart format lib test
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

A mensagem sobre pacotes com versões mais novas é apenas informativa. Não execute `flutter pub upgrade --major-versions` nesta etapa.
