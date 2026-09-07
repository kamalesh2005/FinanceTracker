import 'package:flutter/foundation.dart';
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../models/mutual_fund.dart';
import '../models/global_index.dart';
import '../services/api_service.dart';

class FinanceProvider with ChangeNotifier {
  List<Stock> _stocks = [];
  List<MutualFund> _mutualFunds = [];
  List<StockTrend> _stockTrends = [];
  GlobalIndex? _nifty50;
  Map<String, dynamic> _portfolioSummary = {};
  bool _isLoading = false;
  bool _isRefreshingPrices = false;
  String? _error;

  List<Stock> get stocks => _stocks;
  List<MutualFund> get mutualFunds => _mutualFunds;
  List<StockTrend> get stockTrends => _stockTrends;
  GlobalIndex? get nifty50 => _nifty50;
  Map<String, dynamic> get portfolioSummary => _portfolioSummary;
  bool get isLoading => _isLoading;
  bool get isRefreshingPrices => _isRefreshingPrices;
  String? get error => _error;

  Future<void>? _yahooWarm;
  bool _yahooWarmed = false;
  int _yahooWarmGeneration = 0;

  /// Clears all cached portfolio data (call on logout / user switch).
  void clear() {
    _yahooWarmGeneration++;
    _stocks = [];
    _mutualFunds = [];
    _stockTrends = [];
    _nifty50 = null;
    _portfolioSummary = {};
    _isLoading = false;
    _isRefreshingPrices = false;
    _error = null;
    _yahooWarm = null;
    _yahooWarmed = false;
    notifyListeners();
  }

  /// Fire-and-forget Yahoo price/trend refresh after login. Dedupes in-flight calls.
  Future<void> warmYahooStockData() {
    if (_yahooWarm != null) return _yahooWarm!;
    if (_yahooWarmed) return Future.value();

    final future = () async {
      await refreshStockPrices();
      // refreshStockPrices sets _yahooWarmed on success.
    }();
    _yahooWarm = future;
    future.whenComplete(() {
      if (identical(_yahooWarm, future)) {
        _yahooWarm = null;
      }
    });
    return future;
  }

  /// Await in-flight warm, skip if already done this session, otherwise warm now.
  Future<void> ensureYahooWarmed() async {
    if (_yahooWarmed) return;
    if (_yahooWarm != null) {
      await _yahooWarm;
      if (_yahooWarmed) return;
    }
    await warmYahooStockData();
  }

  Future<void> loadStocks() async {
    _isLoading = true;
    _error = null;
    _stocks = [];
    notifyListeners();

    try {
      _stocks = await ApiService.getStocks();
      try {
        final indices = await ApiService.getIndices();
        GlobalIndex? nifty;
        for (final idx in indices) {
          if (idx.symbol.toUpperCase() == 'NIFTY50') {
            nifty = idx;
            break;
          }
        }
        _nifty50 = nifty ?? (indices.isNotEmpty ? indices.first : null);
      } catch (_) {
        // Index benchmark is supplementary.
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMutualFunds() async {
    _isLoading = true;
    _error = null;
    _mutualFunds = [];
    notifyListeners();

    try {
      _mutualFunds = await ApiService.getMutualFunds();
      try {
        final indices = await ApiService.getIndices();
        GlobalIndex? nifty;
        for (final idx in indices) {
          if (idx.symbol.toUpperCase() == 'NIFTY50') {
            nifty = idx;
            break;
          }
        }
        _nifty50 = nifty ?? (indices.isNotEmpty ? indices.first : null);
      } catch (_) {
        // Index benchmark is supplementary.
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPortfolioSummary() async {
    _isLoading = true;
    _error = null;
    _portfolioSummary = {};
    notifyListeners();

    try {
      _portfolioSummary = await ApiService.getPortfolioSummary();
      try {
        final indices = await ApiService.getIndices();
        GlobalIndex? nifty;
        for (final idx in indices) {
          if (idx.symbol.toUpperCase() == 'NIFTY50') {
            nifty = idx;
            break;
          }
        }
        _nifty50 = nifty ?? (indices.isNotEmpty ? indices.first : null);
      } catch (_) {
        // Index benchmark is supplementary.
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadStockTrends() async {
    try {
      _stockTrends = await ApiService.getStockTrends();
      notifyListeners();
    } catch (_) {
      // trends are supplementary — fail silently
    }
  }

  Future<void> refreshStockPrices() async {
    final generation = _yahooWarmGeneration;
    _isRefreshingPrices = true;
    _error = null;
    notifyListeners();

    try {
      final stocks = await ApiService.refreshStockPrices();
      if (generation != _yahooWarmGeneration) return;
      _stocks = stocks;
      _yahooWarmed = true;
    } catch (_) {
      if (generation != _yahooWarmGeneration) return;
      // Yahoo refresh can time out in front of the origin; keep the holdings
      // already on screen and reload persisted prices without a blocking error.
      _yahooWarmed = true;
      try {
        final stocks = await ApiService.getStocks();
        if (generation != _yahooWarmGeneration) return;
        _stocks = stocks;
      } catch (_) {}
    } finally {
      if (generation == _yahooWarmGeneration) {
        _isRefreshingPrices = false;
        notifyListeners();
      }
    }
  }

  Future<void> addStock(Stock stock, {DateTime? transactionDate}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.createBuyTransaction(
        symbol: stock.symbol,
        quantity: stock.quantity,
        price: stock.buyPrice,
        transactionDate: transactionDate ?? DateTime.now(),
        source: 'Manual Add',
        name: stock.name,
      );
      await loadStocks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> buyStockTransaction({
    required String symbol,
    required double quantity,
    required double price,
    required DateTime transactionDate,
    required String source,
    String name = '',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final src = source.trim().isEmpty ? 'Manual Add' : source.trim();
      await ApiService.createBuyTransaction(
        symbol: symbol,
        quantity: quantity,
        price: price,
        transactionDate: transactionDate,
        source: src,
        name: name,
      );
      await loadStocks();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sellStockTransaction({
    required String symbol,
    required double quantity,
    required double price,
    required DateTime transactionDate,
    required String source,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final src = source.trim().isEmpty ? 'Manual Add' : source.trim();
      await ApiService.createSellTransaction(
        symbol: symbol,
        quantity: quantity,
        price: price,
        transactionDate: transactionDate,
        source: src,
      );
      await loadStocks();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> holdStock({
    required int stockId,
    required double price,
    required String source,
    DateTime? heldAt,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final src = source.trim().isEmpty ? 'Manual Add' : source.trim();
      await ApiService.markStockHold(
        stockId: stockId,
        price: price,
        source: src,
        heldAt: heldAt ?? DateTime.now(),
      );
      await loadStocks();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> setStockNotes({
    required int stockId,
    required String source,
    required String notes,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final src = source.trim().isEmpty ? 'Manual Add' : source.trim();
      await ApiService.setStockNotes(
        stockId: stockId,
        source: src,
        notes: notes,
      );
      await loadStocks();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> setStockThresholds({
    required int stockId,
    required String source,
    required double setBuyPrice,
    required double setProfitBookingPrice,
    required double setStopLossPrice,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final src = source.trim().isEmpty ? 'Manual Add' : source.trim();
      await ApiService.setStockThresholds(
        stockId: stockId,
        source: src,
        setBuyPrice: setBuyPrice,
        setProfitBookingPrice: setProfitBookingPrice,
        setStopLossPrice: setStopLossPrice,
      );
      await loadStocks();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> clearStockReviewValues({
    required int stockId,
    required String source,
    required List<String> fields,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final src = source.trim().isEmpty ? 'Manual Add' : source.trim();
      await ApiService.clearStockReviewValues(
        stockId: stockId,
        source: src,
        fields: fields,
      );
      await loadStocks();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> clearAllStockReviewValues() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.clearAllStockReviewValues();
      await loadStocks();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addStocksBulk(List<Stock> stocks,
      {required String source}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.replaceBuyTransactionsBySource(
        source: source,
        stocks: stocks,
      );
      await loadStocks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> rebuildLedgerFromTransactions({
    required String source,
    required List<Map<String, dynamic>> items,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.rebuildLedgerFromTransactions(
        source: source,
        items: items,
      );
      await loadStocks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<({int count, List<String> unmapped})?> mergeLedgerFromTransactions({
    required String source,
    required List<Map<String, dynamic>> items,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await ApiService.mergeLedgerFromTransactions(
        source: source,
        items: items,
      );
      await loadStocks();
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateStock(int id, Stock stock) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.updateStock(id, stock);
      await loadStocks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateStockHoldings({
    required int stockId,
    required String symbol,
    required double quantity,
    required double price,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.updateStockHoldings(
        stockId: stockId,
        symbol: symbol,
        quantity: quantity,
        price: price,
      );
      await loadStocks();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteStock(int id, {String source = 'Manual Add'}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.deleteStock(id, source: source);
      await loadStocks();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteAllHoldings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.deleteAllHoldings();
      await loadStocks();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addMutualFund(MutualFund mf) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.createMutualFund(mf);
      await loadMutualFunds();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Replace holdings for a broker/bulk source. Returns unmatched row count from server.
  Future<
      ({
        int count,
        int unmatched,
      })?> replaceMutualFundsBySource({
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
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await ApiService.replaceMutualFundsBySource(
        source: source,
        items: items,
      );
      await loadMutualFunds();
      return (count: result.count, unmatched: result.unmatched.length);
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Import NSDL e-CAS PDF (stocks + MFs). Reloads both holdings lists.
  Future<
      ({
        int stocks,
        int mutualFunds,
        List<Map<String, dynamic>> sources,
        List<Map<String, dynamic>> warnings,
      })?> importCas({
    required List<int> bytes,
    required String filename,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await ApiService.importCas(bytes, filename, password);
      await Future.wait([loadStocks(), loadMutualFunds()]);
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateMutualFund(int id, MutualFund mf) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.updateMutualFund(id, mf);
      await loadMutualFunds();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteMutualFund(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.deleteMutualFund(id);
      await loadMutualFunds();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteAllMutualFunds() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.deleteAllMutualFunds();
      await loadMutualFunds();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
