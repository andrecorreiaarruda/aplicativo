import 'package:flutter/foundation.dart';

import '../../data/models/dashboard_snapshot.dart';
import '../../data/models/equipment.dart';
import '../../data/models/service_case.dart';
import '../../data/repositories/service_log_repository.dart';

class ServiceLogController extends ChangeNotifier {
  ServiceLogController(this.repository);

  final ServiceLogRepository repository;

  List<Equipment> equipment = const [];
  List<ServiceCase> cases = const [];
  EquipmentCatalog catalog = EquipmentCatalog.empty;
  bool loading = false;
  bool saving = false;
  String? errorMessage;

  DashboardSnapshot get dashboard => DashboardSnapshot.from(
        equipment: equipment,
        cases: cases,
      );

  Future<void> load() async {
    if (loading) return;
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final values = await Future.wait<dynamic>([
        repository.fetchEquipments(),
        repository.fetchCases(),
        repository.fetchEquipmentCatalog(),
      ]);
      equipment = values[0] as List<Equipment>;
      cases = values[1] as List<ServiceCase>;
      catalog = values[2] as EquipmentCatalog;
    } catch (error) {
      errorMessage = _message(error);
    } finally {
      loading = false;
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
      return await operation();
    } catch (error) {
      errorMessage = _message(error);
      return null;
    } finally {
      saving = false;
      notifyListeners();
    }
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
