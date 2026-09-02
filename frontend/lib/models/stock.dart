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
  final String lastBuyTrend;
  final double lastSalePrice;
  final DateTime? lastSaleDate;
  final String lastSaleTrend;
  final double lastHoldPrice;
  final DateTime? lastHoldDate;
  final String lastHoldTrend;
  final double setBuyPrice;
  final double setProfitBookingPrice;
  final double setStopLossPrice;
  final DateTime? bshClearDate;
  final String trendlyneUrl;
  final DateTime? consensusDate;
  final double consensusLtp;
  final double consensusTarget;
  final double consensusUpside;
  final String consensusType;
  final DateTime? lastConsensusFetchedDate;
  final DateTime? lastNewsFetchedDate;
  final DateTime? lastCatalogYahooRefreshAt;
  final String newsHeadline;
  final String newsUrl;
  final String series;
  final String listingCategory;
  final String pullData;

  /// Annualized XIRR from matched lots; null when it cannot be computed.
  final double? xirr;

  /// FY YoY / YTD % returns from catalog FY-end LTPs (not persisted).
  final double? return2021;
  final double? return2022;
  final double? return2023;
  final double? return2024;
  final double? return2025;
  final double? returnYtd;

  /// Per-holding free-text note (max 200 characters).
  final String notes;

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
    this.lastBuyTrend = '',
    this.lastSalePrice = 0.0,
    this.lastSaleDate,
    this.lastSaleTrend = '',
    this.lastHoldPrice = 0.0,
    this.lastHoldDate,
    this.lastHoldTrend = '',
    this.setBuyPrice = 0.0,
    this.setProfitBookingPrice = 0.0,
    this.setStopLossPrice = 0.0,
    this.bshClearDate,
    this.trendlyneUrl = '',
    this.consensusDate,
    this.consensusLtp = 0.0,
    this.consensusTarget = 0.0,
    this.consensusUpside = 0.0,
    this.consensusType = '',
    this.lastConsensusFetchedDate,
    this.lastNewsFetchedDate,
    this.lastCatalogYahooRefreshAt,
    this.newsHeadline = '',
    this.newsUrl = '',
    this.series = '',
    this.listingCategory = '',
    this.pullData = 'N',
    this.xirr,
    this.return2021,
    this.return2022,
    this.return2023,
    this.return2024,
    this.return2025,
    this.returnYtd,
    this.notes = '',
  });

  double? returnForYear(int year) {
    switch (year) {
      case 2021:
        return return2021;
      case 2022:
        return return2022;
      case 2023:
        return return2023;
      case 2024:
        return return2024;
      case 2025:
        return return2025;
      default:
        return null;
    }
  }

  static double? _optDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

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
      lastBuyTrend: json['last_buy_trend']?.toString() ?? '',
      lastSalePrice: _asDouble(json['last_sale_price']),
      lastSaleDate: _asDate(json['last_sale_date']),
      lastSaleTrend: json['last_sale_trend']?.toString() ?? '',
      lastHoldPrice: _asDouble(json['last_hold_price']),
      lastHoldDate: _asDate(json['last_hold_date']),
      lastHoldTrend: json['last_hold_trend']?.toString() ?? '',
      setBuyPrice: _asDouble(json['set_buy_price']),
      setProfitBookingPrice: _asDouble(json['set_profit_booking_price']),
      setStopLossPrice: _asDouble(json['set_stop_loss_price']),
      bshClearDate: _asDate(json['bsh_clear_date']),
      trendlyneUrl: json['trendlyne_url']?.toString() ?? '',
      consensusDate: _asDate(json['consensus_date']),
      consensusLtp: _asDouble(json['consensus_ltp']),
      consensusTarget: _asDouble(json['consensus_target']),
      consensusUpside: _asDouble(json['consensus_upside']),
      consensusType: json['consensus_type']?.toString() ?? '',
      lastConsensusFetchedDate: _asDate(json['last_consensus_fetched_date']),
      lastNewsFetchedDate: _asDate(json['last_news_fetched_date']),
      lastCatalogYahooRefreshAt: _asDate(json['last_catalog_yahoo_refresh_at']),
      newsHeadline: json['news_headline']?.toString() ?? '',
      newsUrl: json['news_url']?.toString() ?? '',
      series: json['series']?.toString() ?? '',
      listingCategory: json['listing_category']?.toString() ?? '',
      pullData: json['pull_data']?.toString() ?? 'N',
      xirr: json['xirr'] == null ? null : _asDouble(json['xirr']),
      return2021: _optDouble(json['return_2021']),
      return2022: _optDouble(json['return_2022']),
      return2023: _optDouble(json['return_2023']),
      return2024: _optDouble(json['return_2024']),
      return2025: _optDouble(json['return_2025']),
      returnYtd: _optDouble(json['return_ytd']),
      notes: json['notes']?.toString() ?? '',
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

  bool isBshDateActive(DateTime? date, {required double validityDays}) {
    if (date == null) return false;
    if (bshClearDate != null && !date.isAfter(bshClearDate!)) return false;
    final cutoff = DateTime.now().subtract(
      Duration(days: validityDays.round()),
    );
    return !date.isBefore(cutoff);
  }

  bool lastBuyActiveForReview(double validityDays) =>
      hasLastBuy && isBshDateActive(lastBuyDate, validityDays: validityDays);

  bool lastSaleActiveForReview(double validityDays) =>
      hasLastSale && isBshDateActive(lastSaleDate, validityDays: validityDays);

  bool lastHoldActiveForReview(double validityDays) =>
      hasLastHold && isBshDateActive(lastHoldDate, validityDays: validityDays);

  bool hasReviewableValues(double validityDays) {
    return lastBuyActiveForReview(validityDays) ||
        lastSaleActiveForReview(validityDays) ||
        lastHoldActiveForReview(validityDays) ||
        setBuyPrice > 0 ||
        setProfitBookingPrice > 0 ||
        setStopLossPrice > 0;
  }

  bool get lastTradeClearedForRules {
    final lastDate = lastActionDate;
    if (bshClearDate == null || lastDate == null) {
      return bshClearDate != null && lastDate == null;
    }
    return !lastDate.isAfter(bshClearDate!);
  }

  bool get hasConsensus =>
      consensusTarget > 0 ||
      consensusType.trim().isNotEmpty ||
      consensusDate != null;

  bool get hasNewsHeadline => newsHeadline.trim().isNotEmpty;

  bool get hasNewsContent => hasConsensus || hasNewsHeadline;

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

  String get lastActionTrend {
    switch (lastActionType) {
      case 'buy':
        return lastBuyTrend;
      case 'sell':
        return lastSaleTrend;
      case 'hold':
        return lastHoldTrend;
      default:
        return '';
    }
  }

  /// Baseline price for recommendation % fluctuation.
  double? get lastTradePrice => lastActionPrice;
}
