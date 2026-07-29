# Hotfix 0.4.0-alpha.2+15

Corrige a resolução estática do contrato `SyncAwareRepository` no
`ServiceLogController`.

O compilador mantinha a variável local com tipo estático
`ServiceLogRepository` após a checagem `is!`, portanto os métodos
`syncPendingChanges()` e `fetchSyncStatus()` não eram resolvidos.

A correção cria explicitamente uma referência tipada como
`SyncAwareRepository?` antes de chamar os métodos.

Arquivos alterados:
- `lib/features/shell/service_log_controller.dart`
- `pubspec.yaml`
