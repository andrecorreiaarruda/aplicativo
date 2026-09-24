import 'package:flutter/material.dart';

import '../storage/local_snapshot_store.dart';

/// Escolha de aparência — Sistema, Claro ou Escuro — lembrada entre
/// aberturas.
///
/// Fica no banco local, e não no Supabase: é uma preferência deste
/// computador, não da conta. Quem usa o aplicativo em duas máquinas pode
/// querer o escuro numa e o claro na outra.
class AppearanceController extends ChangeNotifier {
  AppearanceController({
    required LocalSnapshotStore store,
    ThemeMode initial = ThemeMode.system,
  }) : _store = store,
       _mode = initial;

  static const _namespace = 'preferencias';
  static const _key = 'aparencia';

  final LocalSnapshotStore _store;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  /// Lê a escolha salva antes de a primeira tela ser desenhada. Carregar
  /// depois faria o aplicativo abrir claro e piscar para o escuro.
  static Future<AppearanceController> load(LocalSnapshotStore store) async {
    String? salvo;
    try {
      salvo = await store.readMetadata(_namespace, _key);
    } catch (error) {
      // Preferência visual não pode impedir o aplicativo de abrir.
      debugPrint('ORION: aparência salva ilegível, usando o sistema: $error');
    }
    return AppearanceController(store: store, initial: parse(salvo));
  }

  static ThemeMode parse(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    // A troca vale na hora; gravar é o passo que pode falhar, e falhar
    // nele só significa voltar ao padrão na próxima abertura.
    _mode = mode;
    notifyListeners();
    try {
      await _store.writeMetadata(_namespace, _key, mode.name);
    } catch (error) {
      debugPrint('ORION: não foi possível salvar a aparência: $error');
    }
  }
}

/// Dá acesso ao [AppearanceController] a partir de qualquer tela.
class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    super.key,
    required AppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppearanceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}
