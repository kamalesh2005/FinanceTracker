import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AppUser? _user;
  bool _loading = true;
  String? _error;

  bool _useAsStockWatchList = false;
  double _effectiveRecommendationFluctuationPct = 5.0;
  double _defaultRecommendationFluctuationPct = 5.0;
  double? _recommendationFluctuationPct;

  AppUser? get user => _user;
  bool get isLoading => _loading;
  bool get isAuthenticated => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  String? get error => _error;

  bool get useAsStockWatchList => _useAsStockWatchList;
  double get effectiveRecommendationFluctuationPct =>
      _effectiveRecommendationFluctuationPct;
  double get defaultRecommendationFluctuationPct =>
      _defaultRecommendationFluctuationPct;
  double? get recommendationFluctuationPct => _recommendationFluctuationPct;

  Future<void> bootstrap() async {
    _loading = true;
    notifyListeners();
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null || token.isEmpty) {
        _user = null;
        ApiService.setToken(null);
        _resetPreferences();
        return;
      }
      ApiService.setToken(token);
      _user = await ApiService.getMe();
      await loadPreferences();
    } catch (_) {
      await _clearSession();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String identifier, String password) async {
    _error = null;
    try {
      final result = await ApiService.login(identifier, password);
      await _persistSession(result['token'] as String, result['user'] as AppUser);
      await loadPreferences();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    String? email,
    String? mobile,
    required String password,
  }) async {
    _error = null;
    try {
      final result = await ApiService.register(
        email: email,
        mobile: mobile,
        password: password,
      );
      await _persistSession(result['token'] as String, result['user'] as AppUser);
      await loadPreferences();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _clearSession();
    notifyListeners();
  }

  Future<void> loadPreferences() async {
    try {
      final data = await ApiService.getPreferences();
      _applyPreferences(data);
      notifyListeners();
    } catch (_) {
      // Keep defaults if preferences fail to load.
    }
  }

  Future<Map<String, dynamic>> savePreferences({
    bool? useAsStockWatchList,
    double? recommendationFluctuationPct,
    bool clearRecommendationFluctuation = false,
  }) async {
    final data = await ApiService.savePreferences(
      useAsStockWatchList: useAsStockWatchList,
      recommendationFluctuationPct: recommendationFluctuationPct,
      clearRecommendationFluctuation: clearRecommendationFluctuation,
    );
    _applyPreferences(data);
    notifyListeners();
    return data;
  }

  void _applyPreferences(Map<String, dynamic> data) {
    _useAsStockWatchList = data['use_as_stock_watch_list'] == true;
    _defaultRecommendationFluctuationPct =
        (data['default_recommendation_fluctuation_pct'] as num?)?.toDouble() ??
            5.0;
    _effectiveRecommendationFluctuationPct =
        (data['effective_recommendation_fluctuation_pct'] as num?)?.toDouble() ??
            _defaultRecommendationFluctuationPct;
    final raw = data['recommendation_fluctuation_pct'];
    if (raw == null) {
      _recommendationFluctuationPct = null;
    } else {
      _recommendationFluctuationPct = (raw as num).toDouble();
    }
  }

  void _resetPreferences() {
    _useAsStockWatchList = false;
    _effectiveRecommendationFluctuationPct = 5.0;
    _defaultRecommendationFluctuationPct = 5.0;
    _recommendationFluctuationPct = null;
  }

  Future<void> _persistSession(String token, AppUser user) async {
    await _storage.write(key: _tokenKey, value: token);
    ApiService.setToken(token);
    _user = user;
    _error = null;
    notifyListeners();
  }

  Future<void> _clearSession() async {
    await _storage.delete(key: _tokenKey);
    ApiService.setToken(null);
    _user = null;
    _resetPreferences();
  }
}
