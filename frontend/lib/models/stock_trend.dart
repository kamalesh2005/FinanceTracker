class StockTrend {
  final int stockId;
  final String symbol;
  final double currentPrice;
  final double ma7;
  final double ma20;
  final double stockDelta;
  final double marketDelta;
  final double adjustedDelta;
  final String trend;

  StockTrend({
    required this.stockId,
    required this.symbol,
    required this.currentPrice,
    required this.ma7,
    required this.ma20,
    required this.stockDelta,
    required this.marketDelta,
    required this.adjustedDelta,
    required this.trend,
  });

  factory StockTrend.fromJson(Map<String, dynamic> json) {
    return StockTrend(
      stockId: json['stock_id'],
      symbol: json['symbol'] ?? '',
      currentPrice: (json['current_price'] ?? 0.0).toDouble(),
      ma7: (json['ma7'] ?? 0.0).toDouble(),
      ma20: (json['ma20'] ?? 0.0).toDouble(),
      stockDelta: (json['stock_delta'] ?? 0.0).toDouble(),
      marketDelta: (json['market_delta'] ?? 0.0).toDouble(),
      adjustedDelta: (json['adjusted_delta'] ?? 0.0).toDouble(),
      trend: json['trend'] ?? 'unknown',
    );
  }
}
