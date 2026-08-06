class Stock {
  final int id;
  final String symbol;
  final String name;
  final String sector;
  final String industry;
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
  final String series;
  final String listingCategory;
  final String pullData;

  Stock({
    required this.id,
    required this.symbol,
    required this.name,
    this.sector = '',
    this.industry = '',
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
    this.series = '',
    this.listingCategory = '',
    this.pullData = 'N',
  });

  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _asDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  factory Stock.fromJson(Map<String, dynamic> json) {
    return Stock(
      id: _asInt(json['id']),
      symbol: json['symbol']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sector: json['sector']?.toString() ?? '',
      industry: json['industry']?.toString() ?? '',
      marketCap: json['market_cap']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      quantity: _asDouble(json['quantity']),
      buyPrice: _asDouble(
        json['average_buy_price'] ?? json['buy_price'],
      ),
      currentPrice: _asDouble(json['current_price']),
      sixthHighestPrice: _asDouble(json['sixth_highest_price']),
      sixthLowestPrice: _asDouble(json['sixth_lowest_price']),
      lastFetchedDate: _asDate(json['last_fetched_date']),
      lastPriceFetchedDate: _asDate(json['last_price_fetched_date']),
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _asDate(json['updated_at']) ?? DateTime.now(),
      isin: json['isin']?.toString(),
      lastBuyPrice: _asDouble(json['last_buy_price']),
      lastBuyDate: _asDate(json['last_buy_date']),
      lastSalePrice: _asDouble(json['last_sale_price']),
      lastSaleDate: _asDate(json['last_sale_date']),
      lastHoldPrice: _asDouble(json['last_hold_price']),
      lastHoldDate: _asDate(json['last_hold_date']),
      setBuyPrice: _asDouble(json['set_buy_price']),
      setProfitBookingPrice: _asDouble(json['set_profit_booking_price']),
      setStopLossPrice: _asDouble(json['set_stop_loss_price']),
      trendlyneUrl: json['trendlyne_url']?.toString() ?? '',
      consensusDate: _asDate(json['consensus_date']),
      consensusLtp: _asDouble(json['consensus_ltp']),
      consensusTarget: _asDouble(json['consensus_target']),
      consensusUpside: _asDouble(json['consensus_upside']),
      consensusType: json['consensus_type']?.toString() ?? '',
      lastConsensusFetchedDate: _asDate(json['last_consensus_fetched_date']),
      series: json['series']?.toString() ?? '',
      listingCategory: json['listing_category']?.toString() ?? '',
      pullData: json['pull_data']?.toString() ?? 'N',
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
