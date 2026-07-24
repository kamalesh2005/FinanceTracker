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
      buyPrice: json['average_buy_price']?.toDouble() ?? json['buy_price']?.toDouble() ?? 0.0,
      currentPrice: json['current_price']?.toDouble() ?? 0.0,
      sixthHighestPrice: json['sixth_highest_price']?.toDouble() ?? 0.0,
      sixthLowestPrice: json['sixth_lowest_price']?.toDouble() ?? 0.0,
      lastFetchedDate: json['last_fetched_date'] != null ? DateTime.parse(json['last_fetched_date']) : null,
      lastPriceFetchedDate: json['last_price_fetched_date'] != null ? DateTime.parse(json['last_price_fetched_date']) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.now(),
      isin: json['isin'],
      lastBuyPrice: json['last_buy_price']?.toDouble() ?? 0.0,
      lastBuyDate: json['last_buy_date'] != null ? DateTime.parse(json['last_buy_date']) : null,
      lastSalePrice: json['last_sale_price']?.toDouble() ?? 0.0,
      lastSaleDate: json['last_sale_date'] != null ? DateTime.parse(json['last_sale_date']) : null,
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

  /// Last trade side for highlight / recommendation: sale if sale date is later, else buy.
  bool get hasLastBuy => lastBuyDate != null && lastBuyPrice > 0;
  bool get hasLastSale => lastSaleDate != null && lastSalePrice > 0;

  bool get lastTradeIsSale {
    if (hasLastSale && hasLastBuy) {
      return lastSaleDate!.isAfter(lastBuyDate!);
    }
    return hasLastSale;
  }

  double? get lastTradePrice {
    if (lastTradeIsSale && hasLastSale) return lastSalePrice;
    if (hasLastBuy) return lastBuyPrice;
    return null;
  }
}
