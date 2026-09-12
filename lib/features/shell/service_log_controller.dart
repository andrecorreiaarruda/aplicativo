import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/dashboard_snapshot.dart';
import '../../data/models/equipment.dart';
import '../../data/models/service_case.dart';
import '../../data/repositories/service_log_repository.dart';
import '../../data/sync/sync_operation.dart';

class ServiceLogController extends ChangeNotifier {
  ServiceLogController(this.repository);

  final ServiceLogRepository repository;

  List<Equipment> equipment = const [];
  List<ServiceCase> cases = const [];
  EquipmentCatalog catalog = EquipmentCatalog.empty;
  bool loading = false;
  bool saving = false;
  bool syncing = false;
  String? errorMessage;
  SyncStatusSnapshot? syncStatus;
  Timer? _retryTimer;
  int _retryAttempt = 0;

  DashboardSnapshot get dashboard =>
      DashboardSnapshot.from(equipment: equipment, cases: cases);

  Future<void> load() async {
    await _loadLocalData(showLoading: true);
    if (!repository.isDemo) unawaited(syncNow(silent: true));
  }

  Future<void> _loadLocalData({required bool showLoading}) async {
    if (loading) return;
    if (showLoading) {
      loading = true;
      errorMessage = null;
      notifyListeners();
    }
    try {
      final values = await Future.wait<dynamic>([
        repository.fetchEquipments(),
        repository.fetchCases(),
        repository.fetchEquipmentCatalog(),
      ]);
      equipment = values[0] as List<Equipment>;
      cases = values[1] as List<ServiceCase>;
      catalog = values[2] as EquipmentCatalog;
      await _refreshSyncStatus();
    } catch (error) {
      errorMessage = _message(error);
    } finally {
      if (showLoading) loading = false;
      notifyListeners();
    }
  }

  Future<void> syncNow({bool silent = false}) async {
    if (syncing) return;
    final syncRepository = repository is SyncAwareRepository
        ? repository as SyncAwareRepository
        : null;
    if (syncRepository == null) return;
    syncing = true;
    if (!silent) errorMessage = null;
    notifyListeners();
    try {
      await syncRepository.syncPendingChanges();
      _retryAttempt = 0;
      _retryTimer?.cancel();
      await _loadLocalData(showLoading: false);
      await _refreshSyncStatus();
      if (syncStatus?.hasPendingChanges == true) _scheduleRetry();
    } catch (error) {
      await _refreshSyncStatus();
      _scheduleRetry();
      if (!silent) errorMessage = _message(error);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<String?> createEquipmentModel(EquipmentModelDraft draft) {
    return _saveValue(() async {
      final id = await repository.createEquipmentModel(draft);
      catalog = await repository.fetchEquipmentCatalog();
      return id;
    });
  }

  Future<String?> createCustomer(CustomerDraft draft) {
    return _saveValue(() async {
      final id = await repository.createCustomer(draft);
      catalog = await repository.fetchEquipmentCatalog();
      return id;
    });
  }

  Future<bool> updateCustomer(String id, CustomerDraft draft) {
    return _save(() async {
      await repository.updateCustomer(id, draft);
      catalog = await repository.fetchEquipmentCatalog();
      equipment = await repository.fetchEquipments();
    });
  }

  Future<String?> createSite(SiteDraft draft) {
    return _saveValue(() async {
      final id = await repository.createSite(draft);
      catalog = await repository.fetchEquipmentCatalog();
      return id;
    });
  }

  Future<bool> updateSite(String id, SiteDraft draft) {
    return _save(() async {
      await repository.updateSite(id, draft);
      catalog = await repository.fetchEquipmentCatalog();
      equipment = await repository.fetchEquipments();
    });
  }

  Future<String?> createCustomerSite(CustomerSiteDraft draft) {
    return _saveValue(() async {
      final id = await repository.createCustomerSite(draft);
      catalog = await repository.fetchEquipmentCatalog();
      return id;
    });
  }

  Future<bool> createEquipment(EquipmentDraft draft) async {
    return _save(() async {
      await repository.createEquipment(draft);
      equipment = await repository.fetchEquipments();
    });
  }

  Future<bool> saveCase(ServiceCaseDraft draft) async {
    return _save(() async {
      await repository.saveCase(draft);
      cases = await repository.fetchCases();
      equipment = await repository.fetchEquipments();
    });
  }

  Future<List<SimilarCaseResult>> search(SimilarCaseQuery query) async {
    errorMessage = null;
    notifyListeners();
    try {
      return await repository.searchSimilarCases(query);
    } catch (error) {
      errorMessage = _message(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() => repository.signOut();

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> _save(Future<void> Function() operation) async {
    if (saving) return false;
    saving = true;
    errorMessage = null;
    notifyListeners();
    try {
      await operation();
      await _refreshSyncStatus();
      if (!repository.isDemo) unawaited(syncNow(silent: true));
      return true;
    } catch (error) {
      errorMessage = _message(error);
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<T?> _saveValue<T>(Future<T> Function() operation) async {
    if (saving) return null;
    saving = true;
    errorMessage = null;
    notifyListeners();
    try {
      final value = await operation();
      await _refreshSyncStatus();
      if (!repository.isDemo) unawaited(syncNow(silent: true));
      return value;
    } catch (error) {
      errorMessage = _message(error);
      return null;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> refreshSyncStatus() async {
    await _refreshSyncStatus();
    notifyListeners();
  }

  Future<void> _refreshSyncStatus() async {
    final syncRepository = repository is SyncAwareRepository
        ? repository as SyncAwareRepository
        : null;
    if (syncRepository == null) {
      syncStatus = null;
      return;
    }
    syncStatus = await syncRepository.fetchSyncStatus();
  }

  void _scheduleRetry() {
    if (repository.isDemo || _retryTimer?.isActive == true) return;
    final seconds = switch (_retryAttempt) {
      0 => 15,
      1 => 30,
      2 => 60,
      3 => 120,
      _ => 300,
    };
    _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      unawaited(syncNow(silent: true));
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  static String _message(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text.startsWith('Bad state: ')
        ? text.substring('Bad state: '.length)
        : text;
  }
}
