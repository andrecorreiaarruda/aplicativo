#!/usr/bin/env bash
set -euo pipefail
FILE="lib/data/repositories/service_log_repository.dart"
test -f "$FILE"
grep -q "abstract class SyncAwareRepository" "$FILE"
grep -q "Future<SyncStatusSnapshot> fetchSyncStatus" "$FILE"
grep -q "Future<void> syncPendingChanges" "$FILE"
grep -q "version: 0.4.0-alpha.2+14" pubspec.yaml
echo "Contrato de sincronização consistente."
