import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../models/mutual_fund.dart';
import '../models/symbol_mapping.dart';
import '../models/user.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8080/api/v1';
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
    try {
      final body = json.decode(response.body);
      if (body is Map && body['error'] != null) {
        return body['error'].toString();
      }
    } catch (_) {}
    return fallback;
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

  static Future<Map<String, dynamic>> register({
    String? email,
    String? mobile,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        if (email != null && email.isNotEmpty) 'email': email,
        if (mobile != null && mobile.isNotEmpty) 'mobile': mobile,
        'password': password,
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
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (sector != null) body['sector'] = sector;

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

  static Future<void> deleteStock(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/stocks/$id'),
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
    throw Exception('Failed to create mutual fund');
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
    throw Exception('Failed to update mutual fund');
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
  }) async {
    final body = <String, dynamic>{};
    if (useAsStockWatchList != null) {
      body['use_as_stock_watch_list'] = useAsStockWatchList;
    }
    if (clearRecommendationFluctuation) {
      body['clear_recommendation_fluctuation'] = true;
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
    required double defaultRecommendationFluctuationPct,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/config'),
      headers: _headers(jsonBody: true),
      body: json.encode({
        'default_recommendation_fluctuation_pct':
            defaultRecommendationFluctuationPct,
      }),
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to save admin config');
  }
}
