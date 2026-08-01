import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/recommendation_engine.dart';

class AuthProvider extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Prefer secure storage; fall back to SharedPreferences on plain HTTP web
  /// where FlutterSecureStorageWeb requires a secure context.
  Future<String?> _readToken() async {
    try {
      return await _secureStorage.read(key: _tokenKey);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    }
  }

  Future<void> _writeToken(String token) async {
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
      return;
    } catch (_) {
      // Fall through to prefs (e.g. HTTP non-secure context on web).
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> _deleteToken() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (_) {
      // Ignore secure-storage failures on plain HTTP.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  AppUser? _user;
  bool _loading = true;
  String? _error;

  bool _useAsStockWatchList = false;
  double _effectiveRecommendationFluctuationPct = 5.0;
  double _defaultRecommendationFluctuationPct = 5.0;
  double? _recommendationFluctuationPct;
  RecommendationRuleset _effectiveRecommendationRules =
      RecommendationRuleset.defaults();
  RecommendationRuleset _defaultRecommendationRules =
      RecommendationRuleset.defaults();
  bool _recommendationRulesIsUserOverride = false;

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
  RecommendationRuleset get effectiveRecommendationRules =>
      _effectiveRecommendationRules;
  RecommendationRuleset get defaultRecommendationRules =>
      _defaultRecommendationRules;
  bool get recommendationRulesIsUserOverride =>
      _recommendationRulesIsUserOverride;

  Future<void> bootstrap() async {
    _loading = true;
    notifyListeners();
    try {
      final token = await _readToken();
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
    required String username,
    String? email,
    String? mobile,
    required String password,
  }) async {
    _error = null;
    try {
      final result = await ApiService.register(
        username: username,
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
    RecommendationRuleset? recommendationRules,
    bool clearRecommendationRules = false,
  }) async {
    final data = await ApiService.savePreferences(
      useAsStockWatchList: useAsStockWatchList,
      recommendationFluctuationPct: recommendationFluctuationPct,
      clearRecommendationFluctuation: clearRecommendationFluctuation,
      recommendationRules: recommendationRules?.toJson(),
      clearRecommendationRules: clearRecommendationRules,
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
    final effectiveRules = data['effective_recommendation_rules'];
    if (effectiveRules is Map<String, dynamic>) {
      _effectiveRecommendationRules =
          RecommendationRuleset.fromJson(effectiveRules);
    } else {
      _effectiveRecommendationRules = RecommendationRuleset.defaults(
        fluctuationPct: _effectiveRecommendationFluctuationPct,
      );
    }
    final defaultRules = data['default_recommendation_rules'];
    if (defaultRules is Map<String, dynamic>) {
      _defaultRecommendationRules = RecommendationRuleset.fromJson(defaultRules);
    } else {
      _defaultRecommendationRules = RecommendationRuleset.defaults(
        fluctuationPct: _defaultRecommendationFluctuationPct,
      );
    }
    _recommendationRulesIsUserOverride =
        data['recommendation_rules_is_user_override'] == true;
  }

  void _resetPreferences() {
    _useAsStockWatchList = false;
    _effectiveRecommendationFluctuationPct = 5.0;
    _defaultRecommendationFluctuationPct = 5.0;
    _recommendationFluctuationPct = null;
    _effectiveRecommendationRules = RecommendationRuleset.defaults();
    _defaultRecommendationRules = RecommendationRuleset.defaults();
    _recommendationRulesIsUserOverride = false;
  }

  Future<void> _persistSession(String token, AppUser user) async {
    await _writeToken(token);
    ApiService.setToken(token);
    _user = user;
    _error = null;
    notifyListeners();
  }

  Future<void> _clearSession() async {
    await _deleteToken();
    ApiService.setToken(null);
    _user = null;
    _resetPreferences();
  }
}
