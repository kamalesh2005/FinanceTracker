import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../models/mutual_fund.dart';
import '../models/global_mutual_fund.dart';
import '../models/symbol_mapping.dart';
import '../models/mf_scheme_mapping.dart';
import '../models/user.dart';

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  );
  static String? _token;
  static void Function()? onUnauthorized;

  static void setToken(String? token) {
    _token = token;
  }

  static Map<String, String> _headers({bool jsonBody = false}) {
    final headers = <String, String>{};
    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  static void _checkUnauthorized(http.Response response) {
    if (response.statusCode == 401) {
      onUnauthorized?.call();
    }
  }

  static String _errorMessage(http.Response response, String fallback) {
    if (response.statusCode == 429) {
      try {
        final body = json.decode(response.body);
        if (body is Map && body['error'] != null) {
          return body['error'].toString();
        }
      } catch (_) {}
      return 'Too many attempts, please try again later';
    }
    try {
      final body = json.decode(response.body);
      if (body is Map && body['error'] != null) {
        return body['error'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  static Future<Map<String, dynamic>> captchaConfig() async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/captcha-config'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_errorMessage(response, 'Failed to load captcha config'));
  }

  /// Decodes a JSON list body; treats null / non-list as an empty list.
  static List<dynamic> _decodeList(String body) {
    final decoded = json.decode(body);
    if (decoded is List) return decoded;
    return <dynamic>[];
  }

  // Auth APIs
  static Future<Map<String, dynamic>> login(String identifier, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers(jsonBody: true),
      body: json.encode({'identifier': identifier, 'password': password}),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return {
        'token': data['token'],
        'user': AppUser.fromJson(data['user'] as Map<String, dynamic>),
      };
    }
    throw Exception(_errorMessage(response, 'Login failed'));
  }

  static Future<bool> checkUsername(String username) async {
    final uri = Uri.parse('$baseUrl/auth/check-username').replace(
      queryParameters: {'username': username},
    );
    final response = await http.get(uri, headers: _headers());
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return data['available'] == true;
    }
    throw Exception(_errorMessage(response, 'Failed to check username'));
  }

  static Future<bool> checkEmail(String email) async {
    final uri = Uri.parse('$baseUrl/auth/check-email').replace(
      queryParameters: {'email': email},
    );
    final response = await http.get(uri, headers: _headers());
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return data['available'] == true;
    }
    throw Exception(_errorMessage(response, 'Failed to check email'));
  }

  static Future<bool> checkMobile(String mobile) async {
    final uri = Uri.parse('$baseUrl/auth/check-mobile').replace(
      queryParameters: {'mobile': mobile},
    );
    final response = await http.get(uri, headers: _headers());
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return data['available'] == true;
    }
    throw Exception(_errorMessage(response, 'Failed to check mobile'));
  }

  static Future<AppUser> updateProfile({
    String? username,
    String? email,
    String? mobile,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/auth/profile'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        if (username != null) 'username': username,
        if (email != null) 'email': email,
        if (mobile != null) 'mobile': mobile,
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return AppUser.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_errorMessage(response, 'Failed to update profile'));
  }

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/change-password'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Failed to change password'));
    }
  }

  static Future<Map<String, dynamic>> register({
    required String username,
    String? email,
    String? mobile,
    required String password,
    String? turnstileToken,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'username': username,
        if (email != null && email.isNotEmpty) 'email': email,
        if (mobile != null && mobile.isNotEmpty) 'mobile': mobile,
        'password': password,
        'turnstileToken': turnstileToken ?? '',
      }),
    );
    if (response.statusCode == 201) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return {
        'token': data['token'],
        'user': AppUser.fromJson(data['user'] as Map<String, dynamic>),
      };
    }
    throw Exception(_errorMessage(response, 'Registration failed'));
  }

  static Future<void> forgotPassword(String identifier) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: _headers(jsonBody: true),
      body: json.encode({'identifier': identifier}),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Failed to send reset code'));
    }
  }

  static Future<void> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'identifier': identifier,
        'code': code,
        'new_password': newPassword,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Failed to reset password'));
    }
  }

  static Future<AppUser> getMe() async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return AppUser.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_errorMessage(response, 'Failed to load profile'));
  }

  static Future<List<AppUser>> getUsers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/users'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = _decodeList(response.body);
      return data.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception(_errorMessage(response, 'Failed to load users'));
  }

  static Future<AppUser> createUser({
    String? username,
    String? email,
    String? mobile,
    required String password,
    String role = 'user',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/users'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        if (username != null && username.isNotEmpty) 'username': username,
        if (email != null && email.isNotEmpty) 'email': email,
        if (mobile != null && mobile.isNotEmpty) 'mobile': mobile,
        'password': password,
        'role': role,
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 201) {
      return AppUser.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_errorMessage(response, 'Failed to create user'));
  }

  static Future<AppUser> setUserEnabled(int id, bool enabled) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/users/$id/enabled'),
      headers: _headers(jsonBody: true),
      body: json.encode({'enabled': enabled}),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return AppUser.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_errorMessage(response, 'Failed to update user'));
  }

  // Stock APIs
  static Future<List<Stock>> getStocks() async {
    final response = await http.get(
      Uri.parse('$baseUrl/stocks'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = _decodeList(response.body);
      return data.map((json) => Stock.fromJson(json)).toList();
    }
    throw Exception('Failed to load stocks');
  }

  /// Paginated Global_Stocks catalog (admin only).
  static Future<
      ({
        List<Stock> items,
        int total,
        int page,
        int pageSize,
      })> getAdminStocks({
    String q = '',
    String series = '',
    String listingCategory = '',
    String pullData = '',
    int page = 1,
    int pageSize = 50,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
    };
    if (q.trim().isNotEmpty) params['q'] = q.trim();
    if (series.trim().isNotEmpty) params['series'] = series.trim();
    if (listingCategory.trim().isNotEmpty) {
      params['listing_category'] = listingCategory.trim();
    }
    if (pullData.trim().isNotEmpty) params['pull_data'] = pullData.trim();

    final response = await http.get(
      Uri.parse('$baseUrl/admin/stocks').replace(queryParameters: params),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final list = (data['items'] as List<dynamic>? ?? [])
          .map((e) => Stock.fromJson(e as Map<String, dynamic>))
          .toList();
      return (
        items: list,
        total: (data['total'] as num?)?.toInt() ?? list.length,
        page: (data['page'] as num?)?.toInt() ?? page,
        pageSize: (data['page_size'] as num?)?.toInt() ?? pageSize,
      );
    }
    throw Exception(_errorMessage(response, 'Failed to load admin stocks'));
  }

  /// Upload NSE_All CSV to upsert Global_Stocks catalog (admin only).
  static Future<
      ({
        int created,
        int updated,
        int skipped,
        int errors,
      })> importNseCatalog(List<int> bytes, String filename) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/admin/stocks/import-nse'),
    );
    if (_token != null && _token!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (
        created: (data['created'] as num?)?.toInt() ?? 0,
        updated: (data['updated'] as num?)?.toInt() ?? 0,
        skipped: (data['skipped'] as num?)?.toInt() ?? 0,
        errors: (data['errors'] as num?)?.toInt() ?? 0,
      );
    }
    throw Exception(_errorMessage(response, 'NSE catalog import failed'));
  }

  static Future<
      ({
        int created,
        int updated,
        int skipped,
        int unmatched,
        int errors,
      })> importClosingPrices(List<int> bytes, String filename) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/admin/stocks/import-closes'),
    );
    if (_token != null && _token!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (
        created: (data['created'] as num?)?.toInt() ?? 0,
        updated: (data['updated'] as num?)?.toInt() ?? 0,
        skipped: (data['skipped'] as num?)?.toInt() ?? 0,
        unmatched: (data['unmatched'] as num?)?.toInt() ?? 0,
        errors: (data['errors'] as num?)?.toInt() ?? 0,
      );
    }
    throw Exception(_errorMessage(response, 'Closing prices import failed'));
  }

  /// Upload ETF CSV to upsert Global_Stocks fields (admin only).
  static Future<
      ({
        int created,
        int updated,
        int skipped,
        int errors,
      })> importEtfCsv(List<int> bytes, String filename) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/admin/stocks/import-etf'),
    );
    if (_token != null && _token!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (
        created: (data['created'] as num?)?.toInt() ?? 0,
        updated: (data['updated'] as num?)?.toInt() ?? 0,
        skipped: (data['skipped'] as num?)?.toInt() ?? 0,
        errors: (data['errors'] as num?)?.toInt() ?? 0,
      );
    }
    throw Exception(_errorMessage(response, 'ETF catalog import failed'));
  }

  /// Paginated Global_MutualFunds catalog for admins.
  static Future<
      ({
        List<GlobalMutualFund> items,
        int total,
        int page,
        int pageSize,
      })> getAdminMutualFunds({
    String q = '',
    int page = 1,
    int pageSize = 50,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
    };
    if (q.trim().isNotEmpty) params['q'] = q.trim();

    final response = await http.get(
      Uri.parse('$baseUrl/admin/mutualfunds').replace(queryParameters: params),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final list = (data['items'] as List<dynamic>? ?? [])
          .map((e) => GlobalMutualFund.fromJson(e as Map<String, dynamic>))
          .toList();
      return (
        items: list,
        total: (data['total'] as num?)?.toInt() ?? list.length,
        page: (data['page'] as num?)?.toInt() ?? page,
        pageSize: (data['page_size'] as num?)?.toInt() ?? pageSize,
      );
    }
    throw Exception(_errorMessage(response, 'Failed to load admin mutual funds'));
  }

  /// Upload catalog xlsx/csv or MF_VAR NAV csv (admin only).
  static Future<
      ({
        String kind,
        int created,
        int updated,
        int skipped,
        int errors,
      })> importMutualFunds(List<int> bytes, String filename) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/admin/mutualfunds/import'),
    );
    if (_token != null && _token!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (
        kind: data['kind']?.toString() ?? '',
        created: (data['created'] as num?)?.toInt() ?? 0,
        updated: (data['updated'] as num?)?.toInt() ?? 0,
        skipped: (data['skipped'] as num?)?.toInt() ?? 0,
        errors: (data['errors'] as num?)?.toInt() ?? 0,
      );
    }
    throw Exception(_errorMessage(response, 'Mutual fund import failed'));
  }

  /// Looks up a Global_MutualFunds row by ISIN.
  static Future<
      ({
        String isin,
        String symbol,
        String schemeName,
        double currentNav,
      })?> lookupGlobalMutualFund(String isin) async {
    final trimmed = isin.trim();
    if (trimmed.isEmpty) return null;
    final response = await http.get(
      Uri.parse(
        '$baseUrl/mutualfunds/lookup?isin=${Uri.encodeQueryComponent(trimmed)}',
      ),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 404) return null;
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (
        isin: data['isin']?.toString() ?? trimmed.toUpperCase(),
        symbol: data['symbol']?.toString() ?? '',
        schemeName: data['scheme_name']?.toString() ?? '',
        currentNav: (data['current_nav'] as num?)?.toDouble() ?? 0.0,
      );
    }
    throw Exception(_errorMessage(response, 'Failed to look up mutual fund'));
  }

  /// Catalog search for Manual Add autocomplete.
  static Future<
      List<
          ({
            String isin,
            String symbol,
            String schemeName,
            double currentNav,
          })>> searchGlobalMutualFunds(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri = Uri.parse('$baseUrl/mutualfunds/search').replace(
      queryParameters: {
        'q': q,
        'limit': '$limit',
      },
    );
    final response = await http.get(uri, headers: _headers());
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      return list.map((e) {
        final data = e as Map<String, dynamic>;
        return (
          isin: data['isin']?.toString() ?? '',
          symbol: data['symbol']?.toString() ?? '',
          schemeName: data['scheme_name']?.toString() ?? '',
          currentNav: (data['current_nav'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    }
    throw Exception(_errorMessage(response, 'Failed to search mutual funds'));
  }

  /// Looks up a Global_Stocks row by symbol (no holding required).
  /// Returns null when the symbol is not in the catalog.
  static Future<({String symbol, String name, double currentPrice})?>
      lookupGlobalStock(String symbol) async {
    final trimmed = symbol.trim();
    if (trimmed.isEmpty) return null;
    final response = await http.get(
      Uri.parse(
        '$baseUrl/stocks/lookup?symbol=${Uri.encodeQueryComponent(trimmed)}',
      ),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 404) return null;
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (
        symbol: data['symbol']?.toString() ?? trimmed.toUpperCase(),
        name: data['name']?.toString() ?? '',
        currentPrice: (data['current_price'] as num?)?.toDouble() ?? 0.0,
      );
    }
    throw Exception(_errorMessage(response, 'Failed to look up stock'));
  }

  /// Catalog search for Manual Add autocomplete.
  static Future<List<({String symbol, String name, double currentPrice})>>
      searchGlobalStocks(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri = Uri.parse('$baseUrl/stocks/search').replace(
      queryParameters: {
        'q': q,
        'limit': '$limit',
      },
    );
    final response = await http.get(uri, headers: _headers());
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      return list.map((e) {
        final data = e as Map<String, dynamic>;
        return (
          symbol: data['symbol']?.toString() ?? '',
          name: data['name']?.toString() ?? '',
          currentPrice: (data['current_price'] as num?)?.toDouble() ?? 0.0,
        );
      }).where((e) => e.symbol.isNotEmpty).toList();
    }
    throw Exception(_errorMessage(response, 'Failed to search stocks'));
  }

  static Future<Stock> createStock(Stock stock) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stocks'),
      headers: _headers(jsonBody: true),
      body: json.encode(stock.toJson()),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 201) {
      return Stock.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to create stock');
  }

  static Future<List<Stock>> createStocksBulk(List<Stock> stocks) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stocks/bulk'),
      headers: _headers(jsonBody: true),
      body: json.encode(stocks.map((s) => s.toJson()).toList()),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 201) {
      final data = _decodeList(response.body);
      return data.map((json) => Stock.fromJson(json)).toList();
    }
    throw Exception('Failed to create stocks');
  }

  static Future<Stock> updateStock(int id, Stock stock) async {
    final response = await http.put(
      Uri.parse('$baseUrl/stocks/$id'),
      headers: _headers(jsonBody: true),
      body: json.encode(stock.toJson()),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return Stock.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to update stock');
  }

  static Future<Stock> updateStockHoldings({
    required int stockId,
    required String symbol,
    required double quantity,
    required double price,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/stocks/$stockId/holdings'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'symbol': symbol,
        'quantity': quantity,
        'price': price,
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return Stock.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to update stock holdings');
  }

  static Future<Stock> updateStockAdminFields(
    int id, {
    String? name,
    String? sector,
    String? industry,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (sector != null) body['sector'] = sector;
    if (industry != null) body['industry'] = industry;

    final response = await http.put(
      Uri.parse('$baseUrl/stocks/$id/admin'),
      headers: _headers(jsonBody: true),
      body: json.encode(body),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return Stock.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to update stock admin fields');
  }

  static Future<void> deleteStock(int id, {String source = 'Manual Add'}) async {
    final uri = Uri.parse('$baseUrl/stocks/$id/holdings').replace(
      queryParameters: {'source': source},
    );
    final response = await http.delete(
      uri,
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete stock');
    }
  }

  // Symbol mapping APIs
  static Future<List<SymbolMapping>> getSymbolMappings({String? query}) async {
    final uri = query != null && query.isNotEmpty
        ? Uri.parse('$baseUrl/symbol-mappings?q=${Uri.encodeQueryComponent(query)}')
        : Uri.parse('$baseUrl/symbol-mappings');
    final response = await http.get(uri, headers: _headers());
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = _decodeList(response.body);
      return data.map((json) => SymbolMapping.fromJson(json)).toList();
    }
    throw Exception('Failed to load symbol mappings');
  }

  static Future<SymbolMapping> createSymbolMapping(SymbolMapping mapping) async {
    final response = await http.post(
      Uri.parse('$baseUrl/symbol-mappings'),
      headers: _headers(jsonBody: true),
      body: json.encode(mapping.toJson()),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 201) {
      return SymbolMapping.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to create symbol mapping');
  }

  static Future<SymbolMapping> updateSymbolMapping(int id, SymbolMapping mapping) async {
    final response = await http.put(
      Uri.parse('$baseUrl/symbol-mappings/$id'),
      headers: _headers(jsonBody: true),
      body: json.encode(mapping.toJson()),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return SymbolMapping.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to update symbol mapping');
  }

  static Future<void> deleteSymbolMapping(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/symbol-mappings/$id'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete symbol mapping');
    }
  }

  // MF scheme mapping APIs
  static Future<List<MFSchemeMapping>> getMFSchemeMappings({String? query}) async {
    final uri = query != null && query.isNotEmpty
        ? Uri.parse(
            '$baseUrl/mf-scheme-mappings?q=${Uri.encodeQueryComponent(query)}',
          )
        : Uri.parse('$baseUrl/mf-scheme-mappings');
    final response = await http.get(uri, headers: _headers());
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = _decodeList(response.body);
      return data.map((json) => MFSchemeMapping.fromJson(json)).toList();
    }
    throw Exception('Failed to load MF scheme mappings');
  }

  static Future<List<MFSchemeMapping>> getUnmappedMFSchemes() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/unmapped-mf-schemes'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = _decodeList(response.body);
      return data.map((json) => MFSchemeMapping.fromJson(json)).toList();
    }
    throw Exception('Failed to load unmapped MF schemes');
  }

  static Future<MFSchemeMapping> createMFSchemeMapping(
    MFSchemeMapping mapping,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mf-scheme-mappings'),
      headers: _headers(jsonBody: true),
      body: json.encode(mapping.toJson()),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 201) {
      return MFSchemeMapping.fromJson(json.decode(response.body));
    }
    throw Exception(_errorMessage(response, 'Failed to create MF scheme mapping'));
  }

  static Future<MFSchemeMapping> updateMFSchemeMapping(
    int id,
    MFSchemeMapping mapping,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/mf-scheme-mappings/$id'),
      headers: _headers(jsonBody: true),
      body: json.encode(mapping.toJson()),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return MFSchemeMapping.fromJson(json.decode(response.body));
    }
    throw Exception(_errorMessage(response, 'Failed to update MF scheme mapping'));
  }

  static Future<void> deleteMFSchemeMapping(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/mf-scheme-mappings/$id'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete MF scheme mapping');
    }
  }

  static Future<List<UnmappedStock>> getUnmappedStocks() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/unmapped-stocks'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = _decodeList(response.body);
      return data.map((json) => UnmappedStock.fromJson(json)).toList();
    }
    throw Exception('Failed to load unmapped stocks');
  }

  // Transaction APIs
  static Future<Map<String, dynamic>> createBuyTransaction({
    required String symbol,
    required double quantity,
    required double price,
    required DateTime transactionDate,
    String source = 'Manual Add',
    String name = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/transactions/buy'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'symbol': symbol,
        'quantity': quantity,
        'price': price,
        'transaction_date': transactionDate.toUtc().toIso8601String(),
        'source': source,
        if (name.isNotEmpty) 'name': name,
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 201) {
      return json.decode(response.body);
    }
    throw Exception(_errorMessage(response, 'Failed to create buy transaction'));
  }

  static Future<int> replaceBuyTransactionsBySource({
    required String source,
    required List<Stock> stocks,
    required DateTime transactionDate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/transactions/buy/replace-by-source'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'source': source,
        'items': stocks
            .map((stock) => {
                  'symbol': stock.symbol,
                  'quantity': stock.quantity,
                  'price': stock.buyPrice,
                  'transaction_date': transactionDate.toUtc().toIso8601String(),
                  if (stock.name.isNotEmpty) 'name': stock.name,
                  if (stock.isin != null && stock.isin!.isNotEmpty) 'isin': stock.isin,
                  if (stock.sector.isNotEmpty) 'sector': stock.sector,
                })
            .toList(),
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 201) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (data['count'] as num?)?.toInt() ?? stocks.length;
    }
    throw Exception('Failed to replace buy transactions by source');
  }

  static Future<Map<String, dynamic>> createSellTransaction({
    required String symbol,
    required double quantity,
    required double price,
    required DateTime transactionDate,
    String source = 'Manual Add',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/transactions/sell'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'symbol': symbol,
        'quantity': quantity,
        'price': price,
        'transaction_date': transactionDate.toUtc().toIso8601String(),
        'source': source,
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 201) {
      return json.decode(response.body);
    }
    throw Exception(_errorMessage(response, 'Failed to create sell transaction'));
  }

  static Future<Map<String, dynamic>> markStockHold({
    required int stockId,
    required double price,
    required String source,
    DateTime? heldAt,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stocks/$stockId/hold'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'price': price,
        'source': source,
        'held_at': (heldAt ?? DateTime.now()).toUtc().toIso8601String(),
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_errorMessage(response, 'Failed to mark stock as hold'));
  }

  static Future<Map<String, dynamic>> setStockThresholds({
    required int stockId,
    required String source,
    required double setBuyPrice,
    required double setProfitBookingPrice,
    required double setStopLossPrice,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/stocks/$stockId/thresholds'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'source': source,
        'set_buy_price': setBuyPrice,
        'set_profit_booking_price': setProfitBookingPrice,
        'set_stop_loss_price': setStopLossPrice,
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_errorMessage(response, 'Failed to save price thresholds'));
  }

  static Future<List<Map<String, dynamic>>> getStockHistory(String symbol) async {
    final response = await http.get(
      Uri.parse('$baseUrl/stocks/history?symbol=$symbol'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return _decodeList(response.body).cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load stock history');
  }

  static Future<List<Map<String, dynamic>>> getStockTransactions(String symbol) async {
    final response = await http.get(
      Uri.parse('$baseUrl/transactions?symbol=$symbol'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return _decodeList(response.body).cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load stock transactions');
  }

  static Future<List<StockTrend>> getStockTrends() async {
    final response = await http.get(
      Uri.parse('$baseUrl/stocks/trends'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = _decodeList(response.body);
      return data.map((json) => StockTrend.fromJson(json)).toList();
    }
    throw Exception('Failed to load stock trends');
  }

  static Future<List<Stock>> refreshStockPrices() async {
    final response = await http.post(
      Uri.parse('$baseUrl/stocks/refresh-prices'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = _decodeList(response.body);
      return data.map((json) => Stock.fromJson(json)).toList();
    }
    throw Exception('Failed to refresh stock prices');
  }

  // Mutual Fund APIs
  static Future<List<MutualFund>> getMutualFunds() async {
    final response = await http.get(
      Uri.parse('$baseUrl/mutualfunds'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = _decodeList(response.body);
      return data.map((json) => MutualFund.fromJson(json)).toList();
    }
    throw Exception('Failed to load mutual funds');
  }

  static Future<MutualFund> createMutualFund(MutualFund mf) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mutualfunds'),
      headers: _headers(jsonBody: true),
      body: json.encode(mf.toJson()),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 201) {
      return MutualFund.fromJson(json.decode(response.body));
    }
    throw Exception(_errorMessage(response, 'Failed to create mutual fund'));
  }

  /// Replace mutual fund holdings for a broker/bulk source.
  /// Items: scheme_name (required for match), optional isin (HDFC fallback),
  /// quantity, nav (buy/avg cost), optional current_nav (broker last NAV).
  static Future<
      ({
        int count,
        int created,
        int updated,
        int deleted,
        List<Map<String, dynamic>> unmatched,
      })> replaceMutualFundsBySource({
    required String source,
    required List<
            ({
              String schemeName,
              String isin,
              double quantity,
              double nav,
              double currentNav,
            })>
        items,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mutualfunds/bulk'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'source': source,
        'items': items
            .map((item) => {
                  'scheme_name': item.schemeName,
                  if (item.isin.isNotEmpty) 'isin': item.isin,
                  'quantity': item.quantity,
                  'nav': item.nav,
                  if (item.currentNav > 0) 'current_nav': item.currentNav,
                })
            .toList(),
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 201) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final unmatchedRaw = data['unmatched'];
      final unmatched = <Map<String, dynamic>>[];
      if (unmatchedRaw is List) {
        for (final e in unmatchedRaw) {
          if (e is Map<String, dynamic>) {
            unmatched.add(e);
          } else if (e is Map) {
            unmatched.add(Map<String, dynamic>.from(e));
          }
        }
      }
      return (
        count: (data['count'] as num?)?.toInt() ?? 0,
        created: (data['created'] as num?)?.toInt() ?? 0,
        updated: (data['updated'] as num?)?.toInt() ?? 0,
        deleted: (data['deleted'] as num?)?.toInt() ?? 0,
        unmatched: unmatched,
      );
    }
    throw Exception(
      _errorMessage(response, 'Failed to replace mutual funds by source'),
    );
  }

  static Future<MutualFund> updateMutualFund(int id, MutualFund mf) async {
    final response = await http.put(
      Uri.parse('$baseUrl/mutualfunds/$id'),
      headers: _headers(jsonBody: true),
      body: json.encode(mf.toJson()),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return MutualFund.fromJson(json.decode(response.body));
    }
    throw Exception(_errorMessage(response, 'Failed to update mutual fund'));
  }

  static Future<void> deleteMutualFund(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/mutualfunds/$id'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete mutual fund');
    }
  }

  // Portfolio APIs
  static Future<Map<String, dynamic>> getPortfolioSummary() async {
    final response = await http.get(
      Uri.parse('$baseUrl/portfolio/summary'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load portfolio summary');
  }

  // User config APIs
  static Future<List<String>> getHiddenStockColumns() async {
    final response = await http.get(
      Uri.parse('$baseUrl/config/stock-columns'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final raw = data['hidden_columns'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return [];
    }
    throw Exception('Failed to load stock column config');
  }

  static Future<List<String>> saveHiddenStockColumns(List<String> hiddenColumns) async {
    final response = await http.put(
      Uri.parse('$baseUrl/config/stock-columns'),
      headers: _headers(jsonBody: true),
      body: json.encode({'hidden_columns': hiddenColumns}),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final raw = data['hidden_columns'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return [];
    }
    throw Exception('Failed to save stock column config');
  }

  static Future<Map<String, dynamic>> getPreferences() async {
    final response = await http.get(
      Uri.parse('$baseUrl/config/preferences'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load preferences');
  }

  static Future<Map<String, dynamic>> savePreferences({
    bool? useAsStockWatchList,
    double? recommendationFluctuationPct,
    bool clearRecommendationFluctuation = false,
    Map<String, dynamic>? recommendationRules,
    bool clearRecommendationRules = false,
  }) async {
    final body = <String, dynamic>{};
    if (useAsStockWatchList != null) {
      body['use_as_stock_watch_list'] = useAsStockWatchList;
    }
    if (clearRecommendationRules || clearRecommendationFluctuation) {
      body['clear_recommendation_rules'] = true;
      body['clear_recommendation_fluctuation'] = true;
    } else if (recommendationRules != null) {
      body['recommendation_rules'] = recommendationRules;
    } else if (recommendationFluctuationPct != null) {
      body['recommendation_fluctuation_pct'] = recommendationFluctuationPct;
    }
    final response = await http.put(
      Uri.parse('$baseUrl/config/preferences'),
      headers: _headers(jsonBody: true),
      body: json.encode(body),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to save preferences');
  }

  static Future<Map<String, dynamic>> getAdminConfig() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/config'),
      headers: _headers(),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load admin config');
  }

  static Future<Map<String, dynamic>> saveAdminConfig({
    double? defaultRecommendationFluctuationPct,
    Map<String, dynamic>? recommendationRules,
  }) async {
    final body = <String, dynamic>{};
    if (recommendationRules != null) {
      body['recommendation_rules'] = recommendationRules;
    }
    if (defaultRecommendationFluctuationPct != null) {
      body['default_recommendation_fluctuation_pct'] =
          defaultRecommendationFluctuationPct;
    }
    final response = await http.put(
      Uri.parse('$baseUrl/admin/config'),
      headers: _headers(jsonBody: true),
      body: json.encode(body),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to save admin config');
  }
}
