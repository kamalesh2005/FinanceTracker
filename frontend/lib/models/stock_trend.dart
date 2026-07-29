class StockTrend {
  final int stockId;
  final String symbol;
  final double currentPrice;
  final double ma7;
  final double ma20;
  final double ma50;
  final double stockSTDelta;
  final double marketSTDelta;
  final double adjustedSTDelta;
  final double stockMTDelta;
  final double marketMTDelta;
  final double adjustedMTDelta;
  final String trend;

  StockTrend({
    required this.stockId,
    required this.symbol,
    required this.currentPrice,
    required this.ma7,
    required this.ma20,
    required this.ma50,
    required this.stockSTDelta,
    required this.marketSTDelta,
    required this.adjustedSTDelta,
    required this.stockMTDelta,
    required this.marketMTDelta,
    required this.adjustedMTDelta,
    required this.trend,
  });

  factory StockTrend.fromJson(Map<String, dynamic> json) {
    return StockTrend(
      stockId: json['stock_id'],
      symbol: json['symbol'] ?? '',
      currentPrice: (json['current_price'] ?? 0.0).toDouble(),
      ma7: (json['ma7'] ?? 0.0).toDouble(),
      ma20: (json['ma20'] ?? 0.0).toDouble(),
      ma50: (json['ma50'] ?? 0.0).toDouble(),
      stockSTDelta: (json['stock_st_delta'] ?? 0.0).toDouble(),
      marketSTDelta: (json['market_st_delta'] ?? 0.0).toDouble(),
      adjustedSTDelta: (json['adjusted_st_delta'] ?? 0.0).toDouble(),
      stockMTDelta: (json['stock_mt_delta'] ?? 0.0).toDouble(),
      marketMTDelta: (json['market_mt_delta'] ?? 0.0).toDouble(),
      adjustedMTDelta: (json['adjusted_mt_delta'] ?? 0.0).toDouble(),
      trend: json['trend'] ?? 'unknown',
    );
  }
}
