import '../storage/local_snapshot_store.dart';

class AppRuntime {
  const AppRuntime({required this.localStore, this.storageWarning});

  final LocalSnapshotStore localStore;
  final String? storageWarning;
}
