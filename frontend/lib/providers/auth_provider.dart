import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/recommendation_engine.dart';
import '../utils/flex_street_entry.dart';
import '../utils/jwt_utils.dart';

class AuthProvider extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Timer? _refreshTimer;
  bool _refreshInProgress = false;
  bool _handlingUnauthorized = false;

  Future<String?> _readStorage(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
  }

  Future<void> _writeStorage(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
      return;
    } catch (_) {
      // Fall through to prefs (e.g. HTTP non-secure context on web).
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _deleteStorage(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {
      // Ignore secure-storage failures on plain HTTP.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<String?> _readToken() => _readStorage(_tokenKey);
  Future<String?> _readRefreshToken() => _readStorage(_refreshTokenKey);

  Future<void> _writeToken(String token) => _writeStorage(_tokenKey, token);
  Future<void> _writeRefreshToken(String token) =>
      _writeStorage(_refreshTokenKey, token);

  Future<void> _deleteToken() => _deleteStorage(_tokenKey);
  Future<void> _deleteRefreshToken() => _deleteStorage(_refreshTokenKey);

  AppUser? _user;
  bool _loading = true;
  String? _error;
  String _activePortal = AppPortal.main;
  String? _pendingLearnerInvite;

  bool _useAsStockWatchList = false;
  bool _showZeroQuantityStocks = false;
  double _effectiveRecommendationFluctuationPct = 5.0;
  double _defaultRecommendationFluctuationPct = 5.0;
  double? _recommendationFluctuationPct;
  RecommendationRuleset _effectiveRecommendationRules =
      RecommendationRuleset.defaults();
  RecommendationRuleset _defaultRecommendationRules =
      RecommendationRuleset.defaults();
  bool _recommendationRulesIsUserOverride = false;
  bool _stockReviewEmailEnabled = true;
  bool _stockReviewEmailAvailable = false;
  bool _stockReviewEmailEffective = false;

  AppUser? get user => _user;
  bool get isLoading => _loading;
  bool get isAuthenticated => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  String? get error => _error;
  String get activePortal => _activePortal;
  String get defaultPortal =>
      AppPortal.normalize(_user?.defaultPortal);
  bool isDefaultPortal(String portal) => defaultPortal == portal;
  String? get pendingLearnerInvite => _pendingLearnerInvite;

  bool get useAsStockWatchList => _useAsStockWatchList;
  /// XIRR is always shown; the Configure preference was removed.
  bool get showXirr => true;
  bool get showZeroQuantityStocks => _showZeroQuantityStocks;
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
  bool get stockReviewEmailEnabled => _stockReviewEmailEnabled;
  bool get stockReviewEmailAvailable => _stockReviewEmailAvailable;
  bool get stockReviewEmailEffective => _stockReviewEmailEffective;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> bootstrap() async {
    _loading = true;
    notifyListeners();
    try {
      final token = await _readToken();
      final refreshToken = await _readRefreshToken();
      if ((token == null || token.isEmpty) &&
          (refreshToken == null || refreshToken.isEmpty)) {
        _user = null;
        ApiService.setToken(null);
        _resetPreferences();
        return;
      }

      if (token != null && token.isNotEmpty) {
        ApiService.setToken(token);
      }

      if (token == null ||
          token.isEmpty ||
          JwtUtils.shouldRefresh(token)) {
        final refreshed = await tryRefreshSession();
        if (!refreshed) {
          await _clearSession();
          return;
        }
      }

      _user = await ApiService.getMe();
      _syncActivePortalAfterAuth();
      await loadPreferences();
      _startSessionRefreshTimer();
    } catch (_) {
      final refreshed = await tryRefreshSession();
      if (refreshed) {
        try {
          _user = await ApiService.getMe();
          _syncActivePortalAfterAuth();
          await loadPreferences();
          _startSessionRefreshTimer();
          return;
        } catch (_) {
          // Fall through to clear session.
        }
      }
      await _clearSession();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Called when the app resumes or the browser tab becomes visible again.
  Future<void> onAppResumed() async {
    final token = await _readToken();
    final refreshToken = await _readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return;
    if (token == null || token.isEmpty || JwtUtils.shouldRefresh(token)) {
      final refreshed = await tryRefreshSession();
      if (refreshed) notifyListeners();
    }
  }

  /// Attempts a silent refresh before logging the user out on 401.
  Future<void> handleUnauthorized() async {
    if (_handlingUnauthorized) return;
    _handlingUnauthorized = true;
    try {
      final refreshed = await tryRefreshSession();
      if (!refreshed) {
        await logout();
      } else {
        notifyListeners();
      }
    } finally {
      _handlingUnauthorized = false;
    }
  }

  Future<bool> tryRefreshSession() async {
    if (_refreshInProgress) return false;
    final refreshToken = await _readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    _refreshInProgress = true;
    try {
      final result = await ApiService.refreshSession(refreshToken);
      await _persistSession(
        result['token'] as String,
        result['user'] as AppUser,
        refreshToken: result['refresh_token'] as String?,
        notify: false,
      );
      _startSessionRefreshTimer();
      return true;
    } catch (_) {
      return false;
    } finally {
      _refreshInProgress = false;
    }
  }

  Future<bool> login(String identifier, String password) async {
    _error = null;
    try {
      final result = await ApiService.login(identifier, password);
      await _persistSession(
        result['token'] as String,
        result['user'] as AppUser,
        refreshToken: result['refresh_token'] as String?,
      );
      await loadPreferences();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginWithGoogle(String idToken) async {
    _error = null;
    try {
      final result = await ApiService.loginWithGoogle(idToken);
      await _persistSession(
        result['token'] as String,
        result['user'] as AppUser,
        refreshToken: result['refresh_token'] as String?,
      );
      await loadPreferences();
      notifyListeners();
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
    String? turnstileToken,
  }) async {
    _error = null;
    try {
      final result = await ApiService.register(
        username: username,
        email: email,
        mobile: mobile,
        password: password,
        turnstileToken: turnstileToken,
      );
      await _persistSession(
        result['token'] as String,
        result['user'] as AppUser,
        refreshToken: result['refresh_token'] as String?,
      );
      await loadPreferences();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void openPortal(String portal) {
    final next = AppPortal.normalize(portal);
    if (_activePortal == next) return;
    _activePortal = next;
    notifyListeners();
  }

  void clearPendingLearnerInvite() {
    _pendingLearnerInvite = null;
  }

  Future<bool> setDefaultPortal(String portal) async {
    _error = null;
    try {
      _user = await ApiService.setDefaultPortal(AppPortal.normalize(portal));
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void _syncActivePortalAfterAuth() {
    _activePortal = AppPortal.normalize(_user?.defaultPortal);
    if (isFlexStreetEntry()) {
      _activePortal = AppPortal.learner;
    }
    final invite = Uri.base.queryParameters['learner_invite']?.trim();
    if (invite != null && invite.isNotEmpty) {
      _pendingLearnerInvite = invite;
      _activePortal = AppPortal.learner;
    }
  }

  Future<void> logout() async {
    await _clearSession();
    notifyListeners();
  }

  Future<bool> updateProfile({
    required String username,
    required String email,
    required String mobile,
  }) async {
    _error = null;
    try {
      _user = await ApiService.updateProfile(
        username: username,
        email: email,
        mobile: mobile,
      );
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _error = null;
    try {
      await ApiService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
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
    bool? showZeroQuantityStocks,
    bool? stockReviewEmailEnabled,
    double? recommendationFluctuationPct,
    bool clearRecommendationFluctuation = false,
    RecommendationRuleset? recommendationRules,
    bool clearRecommendationRules = false,
  }) async {
    final data = await ApiService.savePreferences(
      useAsStockWatchList: useAsStockWatchList,
      showZeroQuantityStocks: showZeroQuantityStocks,
      stockReviewEmailEnabled: stockReviewEmailEnabled,
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
    _showZeroQuantityStocks = data['show_zero_quantity_stocks'] == true;
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
    _stockReviewEmailEnabled = data['stock_review_email_enabled'] == true;
    _stockReviewEmailAvailable = data['stock_review_email_available'] == true;
    _stockReviewEmailEffective = data['stock_review_email_effective'] == true;
  }

  void _resetPreferences() {
    _useAsStockWatchList = false;
    _showZeroQuantityStocks = false;
    _effectiveRecommendationFluctuationPct = 5.0;
    _defaultRecommendationFluctuationPct = 5.0;
    _recommendationFluctuationPct = null;
    _effectiveRecommendationRules = RecommendationRuleset.defaults();
    _defaultRecommendationRules = RecommendationRuleset.defaults();
    _recommendationRulesIsUserOverride = false;
    _stockReviewEmailEnabled = true;
    _stockReviewEmailAvailable = false;
    _stockReviewEmailEffective = false;
  }

  Future<void> _persistSession(
    String token,
    AppUser user, {
    String? refreshToken,
    bool notify = true,
  }) async {
    await _writeToken(token);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _writeRefreshToken(refreshToken);
    }
    ApiService.setToken(token);
    _user = user;
    _error = null;
    _loading = false;
    _syncActivePortalAfterAuth();
    _startSessionRefreshTimer();
    if (notify) notifyListeners();
  }

  void _startSessionRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final token = await _readToken();
      if (token == null || token.isEmpty) return;
      if (!JwtUtils.shouldRefresh(token)) return;
      await tryRefreshSession();
    });
  }

  Future<void> _clearSession() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _deleteToken();
    await _deleteRefreshToken();
    ApiService.setToken(null);
    _user = null;
    _activePortal = AppPortal.main;
    _pendingLearnerInvite = null;
    _resetPreferences();
  }
}
