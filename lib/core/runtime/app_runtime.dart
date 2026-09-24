import '../storage/local_snapshot_store.dart';
import '../theme/appearance_controller.dart';
import '../../features/service_orders/service_order_archive.dart';

class AppRuntime {
  AppRuntime({
    required this.localStore,
    this.storageWarning,
    AppearanceController? appearance,
    ServiceOrderArchive? serviceOrders,
  }) : appearance = appearance ?? AppearanceController(store: localStore),
       serviceOrders = serviceOrders ?? ServiceOrderArchive(store: localStore);

  final LocalSnapshotStore localStore;
  final String? storageWarning;

  /// Preferência de aparência deste computador. Quem não a carrega do
  /// banco (testes, recuperação de armazenamento) começa em "Sistema".
  final AppearanceController appearance;

  /// Ordens de serviço emitidas neste computador.
  final ServiceOrderArchive serviceOrders;
}
