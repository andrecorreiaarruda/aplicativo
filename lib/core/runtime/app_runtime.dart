import '../storage/local_snapshot_store.dart';
import '../theme/appearance_controller.dart';

class AppRuntime {
  AppRuntime({
    required this.localStore,
    this.storageWarning,
    AppearanceController? appearance,
  }) : appearance = appearance ?? AppearanceController(store: localStore);

  final LocalSnapshotStore localStore;
  final String? storageWarning;

  /// Preferência de aparência deste computador. Quem não a carrega do
  /// banco (testes, recuperação de armazenamento) começa em "Sistema".
  final AppearanceController appearance;
}
