class GlobalMutualFund {
  final int id;
  final String isin;
  final String symbol;
  final String schemeName;
  final String series;
  final String type;
  final double haircut;
  final double acceptableQuantity;
  final String applicableHaircut;
  final double currentNav;
  final DateTime? lastNavDate;

  GlobalMutualFund({
    required this.id,
    required this.isin,
    required this.symbol,
    required this.schemeName,
    this.series = '',
    this.type = '',
    this.haircut = 0,
    this.acceptableQuantity = 0,
    this.applicableHaircut = '',
    this.currentNav = 0,
    this.lastNavDate,
  });

  factory GlobalMutualFund.fromJson(Map<String, dynamic> json) {
    DateTime? lastNav;
    final raw = json['last_nav_date'];
    if (raw is String && raw.isNotEmpty) {
      lastNav = DateTime.tryParse(raw);
    }
    return GlobalMutualFund(
      id: (json['id'] as num?)?.toInt() ?? 0,
      isin: json['isin']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      schemeName: json['scheme_name']?.toString() ?? '',
      series: json['series']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      haircut: (json['haircut'] as num?)?.toDouble() ?? 0,
      acceptableQuantity: (json['acceptable_quantity'] as num?)?.toDouble() ?? 0,
      applicableHaircut: json['applicable_haircut']?.toString() ?? '',
      currentNav: (json['current_nav'] as num?)?.toDouble() ?? 0,
      lastNavDate: lastNav,
    );
  }
}
