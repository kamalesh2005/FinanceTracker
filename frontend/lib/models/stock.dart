class Stock {
  final int id;
  final String symbol;
  final String name;
  final String sector;
  final String marketCap;
  /// Holding source (e.g. Manual Add, ICICIDirect). One list row per source+stock.
  final String source;
  final double quantity;
  final double buyPrice;
  final double currentPrice;
  final double sixthHighestPrice;
  final double sixthLowestPrice;
  final DateTime? lastFetchedDate;
  final DateTime? lastPriceFetchedDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// Persisted for broker imports and used for Yahoo symbol fallback mapping.
  final String? isin;
  final double lastBuyPrice;
  final DateTime? lastBuyDate;
  final double lastSalePrice;
  final DateTime? lastSaleDate;
  final double lastHoldPrice;
  final DateTime? lastHoldDate;
  final double setBuyPrice;
  final double setProfitBookingPrice;
  final double setStopLossPrice;
  final String trendlyneUrl;
  final DateTime? consensusDate;
  final double consensusLtp;
  final double consensusTarget;
  final double consensusUpside;
  final String consensusType;
  final DateTime? lastConsensusFetchedDate;

  Stock({
    required this.id,
    required this.symbol,
    required this.name,
    this.sector = '',
    this.marketCap = '',
    this.source = '',
    required this.quantity,
    required this.buyPrice,
    required this.currentPrice,
    this.sixthHighestPrice = 0.0,
    this.sixthLowestPrice = 0.0,
    this.lastFetchedDate,
    this.lastPriceFetchedDate,
    required this.createdAt,
    required this.updatedAt,
    this.isin,
    this.lastBuyPrice = 0.0,
    this.lastBuyDate,
    this.lastSalePrice = 0.0,
    this.lastSaleDate,
    this.lastHoldPrice = 0.0,
    this.lastHoldDate,
    this.setBuyPrice = 0.0,
    this.setProfitBookingPrice = 0.0,
    this.setStopLossPrice = 0.0,
    this.trendlyneUrl = '',
    this.consensusDate,
    this.consensusLtp = 0.0,
    this.consensusTarget = 0.0,
    this.consensusUpside = 0.0,
    this.consensusType = '',
    this.lastConsensusFetchedDate,
  });

  factory Stock.fromJson(Map<String, dynamic> json) {
    return Stock(
      id: json['id'],
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      sector: json['sector'] ?? '',
      marketCap: json['market_cap'] ?? '',
      source: json['source'] ?? '',
      quantity: json['quantity']?.toDouble() ?? 0.0,
      buyPrice: json['average_buy_price']?.toDouble() ??
          json['buy_price']?.toDouble() ??
          0.0,
      currentPrice: json['current_price']?.toDouble() ?? 0.0,
      sixthHighestPrice: json['sixth_highest_price']?.toDouble() ?? 0.0,
      sixthLowestPrice: json['sixth_lowest_price']?.toDouble() ?? 0.0,
      lastFetchedDate: json['last_fetched_date'] != null
          ? DateTime.parse(json['last_fetched_date'])
          : null,
      lastPriceFetchedDate: json['last_price_fetched_date'] != null
          ? DateTime.parse(json['last_price_fetched_date'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
      isin: json['isin'],
      lastBuyPrice: json['last_buy_price']?.toDouble() ?? 0.0,
      lastBuyDate: json['last_buy_date'] != null
          ? DateTime.parse(json['last_buy_date'])
          : null,
      lastSalePrice: json['last_sale_price']?.toDouble() ?? 0.0,
      lastSaleDate: json['last_sale_date'] != null
          ? DateTime.parse(json['last_sale_date'])
          : null,
      lastHoldPrice: json['last_hold_price']?.toDouble() ?? 0.0,
      lastHoldDate: json['last_hold_date'] != null
          ? DateTime.parse(json['last_hold_date'])
          : null,
      setBuyPrice: json['set_buy_price']?.toDouble() ?? 0.0,
      setProfitBookingPrice:
          json['set_profit_booking_price']?.toDouble() ?? 0.0,
      setStopLossPrice: json['set_stop_loss_price']?.toDouble() ?? 0.0,
      trendlyneUrl: json['trendlyne_url']?.toString() ?? '',
      consensusDate: json['consensus_date'] != null
          ? DateTime.parse(json['consensus_date'])
          : null,
      consensusLtp: json['consensus_ltp']?.toDouble() ?? 0.0,
      consensusTarget: json['consensus_target']?.toDouble() ?? 0.0,
      consensusUpside: json['consensus_upside']?.toDouble() ?? 0.0,
      consensusType: json['consensus_type']?.toString() ?? '',
      lastConsensusFetchedDate: json['last_consensus_fetched_date'] != null
          ? DateTime.parse(json['last_consensus_fetched_date'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'name': name,
      'quantity': quantity,
      'buy_price': buyPrice,
      'current_price': currentPrice,
    };
  }

  bool get hasLastBuy => lastBuyDate != null && lastBuyPrice > 0;
  bool get hasLastSale => lastSaleDate != null && lastSalePrice > 0;
  bool get hasLastHold => lastHoldDate != null && lastHoldPrice > 0;

  bool get hasConsensus =>
      consensusTarget > 0 ||
      consensusType.trim().isNotEmpty ||
      consensusDate != null;

  /// Latest of Buy / Sell / Hold by date. Ties: Hold > Sell > Buy.
  String? get lastActionType {
    DateTime? bestDate;
    String? bestType;
    int bestPriority = -1;

    void consider(String type, DateTime? date, bool valid, int priority) {
      if (!valid || date == null) return;
      if (bestDate == null ||
          date.isAfter(bestDate!) ||
          (date.isAtSameMomentAs(bestDate!) && priority > bestPriority)) {
        bestDate = date;
        bestType = type;
        bestPriority = priority;
      }
    }

    consider('buy', lastBuyDate, hasLastBuy, 1);
    consider('sell', lastSaleDate, hasLastSale, 2);
    consider('hold', lastHoldDate, hasLastHold, 3);
    return bestType;
  }

  bool get lastTradeIsBuy => lastActionType == 'buy';
  bool get lastTradeIsSale => lastActionType == 'sell';
  bool get lastTradeIsHold => lastActionType == 'hold';

  double? get lastActionPrice {
    switch (lastActionType) {
      case 'buy':
        return lastBuyPrice;
      case 'sell':
        return lastSalePrice;
      case 'hold':
        return lastHoldPrice;
      default:
        return null;
    }
  }

  DateTime? get lastActionDate {
    switch (lastActionType) {
      case 'buy':
        return lastBuyDate;
      case 'sell':
        return lastSaleDate;
      case 'hold':
        return lastHoldDate;
      default:
        return null;
    }
  }

  String? get lastActionLabel {
    switch (lastActionType) {
      case 'buy':
        return 'Buy';
      case 'sell':
        return 'Sell';
      case 'hold':
        return 'Hold';
      default:
        return null;
    }
  }

  /// Baseline price for recommendation % fluctuation.
  double? get lastTradePrice => lastActionPrice;
}
