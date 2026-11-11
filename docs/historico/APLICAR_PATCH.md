# ORION ServiceLog 0.2.5

Este patch substitui o ciclo manual de `setState` por `AnimatedBuilder`, inicia a carga antes do registro do listener, apresenta uma tela de carregamento explícita e adiciona captura visível de erros de renderização.

```bash
cd ~/Projetos/orion-servicelog
unzip -o ~/Downloads/orion-servicelog-flutter-runtime-stability-patch-0.2.5.zip -d .
flutter clean
rm -rf .dart_tool build
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d linux
```
