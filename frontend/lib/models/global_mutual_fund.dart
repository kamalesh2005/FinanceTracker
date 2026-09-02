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
  final double navFy2020;
  final double navFy2021;
  final double navFy2022;
  final double navFy2023;
  final double navFy2024;
  final double navFy2025;

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
    this.navFy2020 = 0,
    this.navFy2021 = 0,
    this.navFy2022 = 0,
    this.navFy2023 = 0,
    this.navFy2024 = 0,
    this.navFy2025 = 0,
  });

  factory GlobalMutualFund.fromJson(Map<String, dynamic> json) {
    DateTime? lastNav;
    final raw = json['last_nav_date'];
    if (raw is String && raw.isNotEmpty) {
      lastNav = DateTime.tryParse(raw);
    }
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return GlobalMutualFund(
      id: (json['id'] as num?)?.toInt() ?? 0,
      isin: json['isin']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      schemeName: json['scheme_name']?.toString() ?? '',
      series: json['series']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      haircut: d(json['haircut']),
      acceptableQuantity: d(json['acceptable_quantity']),
      applicableHaircut: json['applicable_haircut']?.toString() ?? '',
      currentNav: d(json['current_nav']),
      lastNavDate: lastNav,
      navFy2020: d(json['nav_fy_2020']),
      navFy2021: d(json['nav_fy_2021']),
      navFy2022: d(json['nav_fy_2022']),
      navFy2023: d(json['nav_fy_2023']),
      navFy2024: d(json['nav_fy_2024']),
      navFy2025: d(json['nav_fy_2025']),
    );
  }
}
