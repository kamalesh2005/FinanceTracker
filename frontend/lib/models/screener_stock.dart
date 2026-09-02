import 'stock.dart';

class ScreenerStock {
  static const List<String> defaultLabels = ['Hide', 'Track', 'Ignore'];
  static const String unlabeledSentinel = '__unlabeled__';
  static const String unlabeledDisplay = '(No label)';

  static Set<String> defaultSelectedLabels() => {
        'Track',
        unlabeledSentinel,
      };

  static bool isDefaultExcludedLabel(String label) =>
      label == 'Hide' || label == 'Ignore';

  final int id;
  final String symbol;
  final String name;
  final String industry;
  final String marketCap;
  final String trend;
  final double adjustedSTDelta;
  final double adjustedMTDelta;
  final double currentPrice;
  final double ma7;
  final double ma20;
  final double ma50;
  final double consensusTarget;
  final double consensusUpside;
  final String consensusType;
  final String newsHeadline;
  final String newsUrl;
  final bool inWatchlist;
  final List<String> labels;
  final double? return2021;
  final double? return2022;
  final double? return2023;
  final double? return2024;
  final double? return2025;
  final double? returnYtd;

  const ScreenerStock({
    required this.id,
    required this.symbol,
    required this.name,
    this.industry = '',
    this.marketCap = '',
    this.trend = '',
    this.adjustedSTDelta = 0,
    this.adjustedMTDelta = 0,
    this.currentPrice = 0,
    this.ma7 = 0,
    this.ma20 = 0,
    this.ma50 = 0,
    this.consensusTarget = 0,
    this.consensusUpside = 0,
    this.consensusType = '',
    this.newsHeadline = '',
    this.newsUrl = '',
    this.inWatchlist = false,
    this.labels = const [],
    this.return2021,
    this.return2022,
    this.return2023,
    this.return2024,
    this.return2025,
    this.returnYtd,
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

  static double? _optDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory ScreenerStock.fromJson(Map<String, dynamic> json) {
    return ScreenerStock(
      id: _asInt(json['id']),
      symbol: json['symbol']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      industry: json['industry']?.toString() ?? '',
      marketCap: json['market_cap']?.toString() ?? '',
      trend: json['trend']?.toString() ?? '',
      adjustedSTDelta: _asDouble(json['adjusted_st_delta']),
      adjustedMTDelta: _asDouble(json['adjusted_mt_delta']),
      currentPrice: _asDouble(json['current_price']),
      ma7: _asDouble(json['ma7']),
      ma20: _asDouble(json['ma20']),
      ma50: _asDouble(json['ma50']),
      consensusTarget: _asDouble(json['consensus_target']),
      consensusUpside: _asDouble(json['consensus_upside']),
      consensusType: json['consensus_type']?.toString() ?? '',
      newsHeadline: json['news_headline']?.toString() ?? '',
      newsUrl: json['news_url']?.toString() ?? '',
      inWatchlist: json['in_watchlist'] == true,
      labels: _asStringList(json['labels']),
      return2021: _optDouble(json['return_2021']),
      return2022: _optDouble(json['return_2022']),
      return2023: _optDouble(json['return_2023']),
      return2024: _optDouble(json['return_2024']),
      return2025: _optDouble(json['return_2025']),
      returnYtd: _optDouble(json['return_ytd']),
    );
  }

  static List<String> _asStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  ScreenerStock copyWith({bool? inWatchlist, List<String>? labels}) {
    return ScreenerStock(
      id: id,
      symbol: symbol,
      name: name,
      industry: industry,
      marketCap: marketCap,
      trend: trend,
      adjustedSTDelta: adjustedSTDelta,
      adjustedMTDelta: adjustedMTDelta,
      currentPrice: currentPrice,
      ma7: ma7,
      ma20: ma20,
      ma50: ma50,
      consensusTarget: consensusTarget,
      consensusUpside: consensusUpside,
      consensusType: consensusType,
      newsHeadline: newsHeadline,
      newsUrl: newsUrl,
      inWatchlist: inWatchlist ?? this.inWatchlist,
      labels: labels ?? this.labels,
      return2021: return2021,
      return2022: return2022,
      return2023: return2023,
      return2024: return2024,
      return2025: return2025,
      returnYtd: returnYtd,
    );
  }

  String get googleFinanceUrl =>
      'https://www.google.com/finance/beta/quote/${Uri.encodeComponent(symbol)}:NSE';

  Stock toBuyStock() {
    final now = DateTime.now();
    return Stock(
      id: id,
      symbol: symbol,
      name: name,
      quantity: 0,
      buyPrice: currentPrice,
      currentPrice: currentPrice,
      createdAt: now,
      updatedAt: now,
    );
  }
}

class ScreenerPage {
  final List<ScreenerStock> items;
  final int total;
  final int page;
  final int pageSize;

  const ScreenerPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });
}

class ScreenerOptions {
  final List<String> industries;
  final List<String> consensusTypes;
  final List<String> labels;

  const ScreenerOptions({
    this.industries = const [],
    this.consensusTypes = const [],
    this.labels = const [],
  });

  factory ScreenerOptions.fromJson(Map<String, dynamic> json) {
    List<String> asStrings(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return ScreenerOptions(
      industries: asStrings(json['industries']),
      consensusTypes: asStrings(json['consensus_types']),
      labels: asStrings(json['labels']),
    );
  }
}
