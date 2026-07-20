class Stock {
  final int id;
  final String symbol;
  final String name;
  final String sector;
  final String marketCap;
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

  Stock({
    required this.id,
    required this.symbol,
    required this.name,
    this.sector = '',
    this.marketCap = '',
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
  });

  factory Stock.fromJson(Map<String, dynamic> json) {
    return Stock(
      id: json['id'],
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      sector: json['sector'] ?? '',
      marketCap: json['market_cap'] ?? '',
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
}
