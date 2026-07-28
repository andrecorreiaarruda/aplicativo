# ORION ServiceLog – patch 0.2.3

Este patch corrige a inicialização da área de trabalho no Flutter Desktop:

- adia o primeiro carregamento para depois do primeiro frame;
- deixa de construir as quatro páginas simultaneamente;
- monta apenas a página selecionada, reduzindo conflitos de layout/semântica;
- preserva a identidade visual e as regras de negócio;
- atualiza a versão para `0.2.3+5`.

## Aplicação

Na raiz do projeto:

```bash
unzip -o ~/Downloads/orion-servicelog-flutter-runtime-patch-0.2.3.zip -d .
flutter clean
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d linux
```
