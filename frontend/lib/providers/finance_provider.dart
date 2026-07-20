import 'package:flutter/foundation.dart';
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../models/mutual_fund.dart';
import '../services/api_service.dart';

class FinanceProvider with ChangeNotifier {
  List<Stock> _stocks = [];
  List<MutualFund> _mutualFunds = [];
  List<StockTrend> _stockTrends = [];
  Map<String, dynamic> _portfolioSummary = {};
  bool _isLoading = false;
  bool _isRefreshingPrices = false;
  String? _error;

  List<Stock> get stocks => _stocks;
  List<MutualFund> get mutualFunds => _mutualFunds;
  List<StockTrend> get stockTrends => _stockTrends;
  Map<String, dynamic> get portfolioSummary => _portfolioSummary;
  bool get isLoading => _isLoading;
  bool get isRefreshingPrices => _isRefreshingPrices;
  String? get error => _error;

  Future<void> loadStocks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _stocks = await ApiService.getStocks();
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
    notifyListeners();

    try {
      _mutualFunds = await ApiService.getMutualFunds();
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
    notifyListeners();

    try {
      _portfolioSummary = await ApiService.getPortfolioSummary();
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
    _isRefreshingPrices = true;
    _error = null;
    notifyListeners();

    try {
      _stocks = await ApiService.refreshStockPrices();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isRefreshingPrices = false;
      notifyListeners();
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

  Future<void> addStocksBulk(List<Stock> stocks, {required String source}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.replaceBuyTransactionsBySource(
        source: source,
        stocks: stocks,
        transactionDate: DateTime.now(),
      );
      await loadStocks();
    } catch (e) {
      _error = e.toString();
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

  Future<void> deleteStock(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.deleteStock(id);
      await loadStocks();
    } catch (e) {
      _error = e.toString();
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
}
