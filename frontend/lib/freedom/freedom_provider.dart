import 'package:flutter/foundation.dart';
import 'freedom_api.dart';
import 'models/ff_models.dart';

class FreedomProvider extends ChangeNotifier {
  FFSummary? _summary;
  bool _loading = false;
  String? _error;

  FFSummary? get summary => _summary;
  bool get isLoading => _loading;
  String? get error => _error;

  List<FFAsset> get assets => _summary?.assets ?? const [];
  List<FFJobIncome> get jobIncome => _summary?.jobIncome ?? const [];
  List<FFExpense> get expenses => _summary?.expenses ?? const [];
  List<FFOneTimeExpense> get oneTimeExpenses =>
      _summary?.oneTimeExpenses ?? const [];
  FFMetrics? get metrics => _summary?.metrics;
  List<FFRetireSimRow> get retireSimulation =>
      _summary?.retireSimulation ?? const [];
  FFLiveWellDetail? get liveWellDetail => _summary?.liveWellDetail;

  void clear() {
    _summary = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  Future<void> loadSummary() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _summary = await FreedomApi.getSummary();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
