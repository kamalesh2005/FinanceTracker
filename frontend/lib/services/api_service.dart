import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../models/mutual_fund.dart';
import '../models/symbol_mapping.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8080/api/v1';

  // Stock APIs
  static Future<List<Stock>> getStocks() async {
    final response = await http.get(Uri.parse('$baseUrl/stocks'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => Stock.fromJson(json)).toList();
    }
    throw Exception('Failed to load stocks');
  }

  static Future<Stock> createStock(Stock stock) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stocks'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(stock.toJson()),
    );
    if (response.statusCode == 201) {
      return Stock.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to create stock');
  }

  static Future<List<Stock>> createStocksBulk(List<Stock> stocks) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stocks/bulk'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(stocks.map((s) => s.toJson()).toList()),
    );
    if (response.statusCode == 201) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => Stock.fromJson(json)).toList();
    }
    throw Exception('Failed to create stocks');
  }

  static Future<Stock> updateStock(int id, Stock stock) async {
    final response = await http.put(
      Uri.parse('$baseUrl/stocks/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(stock.toJson()),
    );
    if (response.statusCode == 200) {
      return Stock.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to update stock');
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
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return Stock.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to update stock admin fields');
  }

  static Future<void> deleteStock(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/stocks/$id'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete stock');
    }
  }

  // Symbol mapping APIs
  static Future<List<SymbolMapping>> getSymbolMappings({String? query}) async {
    final uri = query != null && query.isNotEmpty
        ? Uri.parse('$baseUrl/symbol-mappings?q=${Uri.encodeQueryComponent(query)}')
        : Uri.parse('$baseUrl/symbol-mappings');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => SymbolMapping.fromJson(json)).toList();
    }
    throw Exception('Failed to load symbol mappings');
  }

  static Future<SymbolMapping> createSymbolMapping(SymbolMapping mapping) async {
    final response = await http.post(
      Uri.parse('$baseUrl/symbol-mappings'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(mapping.toJson()),
    );
    if (response.statusCode == 201) {
      return SymbolMapping.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to create symbol mapping');
  }

  static Future<SymbolMapping> updateSymbolMapping(int id, SymbolMapping mapping) async {
    final response = await http.put(
      Uri.parse('$baseUrl/symbol-mappings/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(mapping.toJson()),
    );
    if (response.statusCode == 200) {
      return SymbolMapping.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to update symbol mapping');
  }

  static Future<void> deleteSymbolMapping(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/symbol-mappings/$id'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete symbol mapping');
    }
  }

  static Future<List<UnmappedStock>> getUnmappedStocks() async {
    final response = await http.get(Uri.parse('$baseUrl/admin/unmapped-stocks'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
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
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'symbol': symbol,
        'quantity': quantity,
        'price': price,
        'transaction_date': transactionDate.toUtc().toIso8601String(),
        'source': source,
        if (name.isNotEmpty) 'name': name,
      }),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body);
    }
    throw Exception('Failed to create buy transaction');
  }


  static Future<int> replaceBuyTransactionsBySource({
    required String source,
    required List<Stock> stocks,
    required DateTime transactionDate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/transactions/buy/replace-by-source'),
      headers: {'Content-Type': 'application/json'},
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
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/transactions/sell'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'symbol': symbol,
        'quantity': quantity,
        'price': price,
        'transaction_date': transactionDate.toUtc().toIso8601String(),
      }),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body);
    }
    throw Exception('Failed to create sell transaction');
  }

  static Future<List<Map<String, dynamic>>> getStockHistory(String symbol) async {
    final response = await http.get(Uri.parse('$baseUrl/stocks/history?symbol=$symbol'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load stock history');
  }

  static Future<List<Map<String, dynamic>>> getStockTransactions(String symbol) async {
    final response = await http.get(Uri.parse('$baseUrl/transactions?symbol=$symbol'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load stock transactions');
  }

  static Future<List<StockTrend>> getStockTrends() async {
    final response = await http.get(Uri.parse('$baseUrl/stocks/trends'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => StockTrend.fromJson(json)).toList();
    }
    throw Exception('Failed to load stock trends');
  }

  static Future<List<Stock>> refreshStockPrices() async {
    final response = await http.post(Uri.parse('$baseUrl/stocks/refresh-prices'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => Stock.fromJson(json)).toList();
    }
    throw Exception('Failed to refresh stock prices');
  }

  // Mutual Fund APIs
  static Future<List<MutualFund>> getMutualFunds() async {
    final response = await http.get(Uri.parse('$baseUrl/mutualfunds'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => MutualFund.fromJson(json)).toList();
    }
    throw Exception('Failed to load mutual funds');
  }

  static Future<MutualFund> createMutualFund(MutualFund mf) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mutualfunds'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(mf.toJson()),
    );
    if (response.statusCode == 201) {
      return MutualFund.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to create mutual fund');
  }

  static Future<MutualFund> updateMutualFund(int id, MutualFund mf) async {
    final response = await http.put(
      Uri.parse('$baseUrl/mutualfunds/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(mf.toJson()),
    );
    if (response.statusCode == 200) {
      return MutualFund.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to update mutual fund');
  }

  static Future<void> deleteMutualFund(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/mutualfunds/$id'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete mutual fund');
    }
  }

  // Portfolio APIs
  static Future<Map<String, dynamic>> getPortfolioSummary() async {
    final response = await http.get(Uri.parse('$baseUrl/portfolio/summary'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load portfolio summary');
  }
}
