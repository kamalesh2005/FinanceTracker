class MutualFund {
  final int id;
  final String isin;
  final String schemeCode;
  final String schemeName;
  final String sourceSchemeName;
  final String fundHouse;
  final String source;
  final double quantity;
  final double nav;
  final double currentNav;
  final DateTime purchaseDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double? return2021;
  final double? return2022;
  final double? return2023;
  final double? return2024;
  final double? return2025;
  final double? returnYtd;

  MutualFund({
    required this.id,
    this.isin = '',
    required this.schemeCode,
    required this.schemeName,
    this.sourceSchemeName = '',
    required this.fundHouse,
    this.source = '',
    required this.quantity,
    required this.nav,
    required this.currentNav,
    required this.purchaseDate,
    required this.createdAt,
    required this.updatedAt,
    this.return2021,
    this.return2022,
    this.return2023,
    this.return2024,
    this.return2025,
    this.returnYtd,
  });

  /// Catalog name when linked; otherwise broker upload name.
  String get displayName {
    final catalog = schemeName.trim();
    if (catalog.isNotEmpty) return catalog;
    return sourceSchemeName.trim();
  }

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

  factory MutualFund.fromJson(Map<String, dynamic> json) {
    return MutualFund(
      id: json['id'],
      isin: json['isin']?.toString() ?? '',
      schemeCode: json['scheme_code'] ?? '',
      schemeName: json['scheme_name'] ?? '',
      sourceSchemeName: json['source_scheme_name']?.toString() ?? '',
      fundHouse: json['fund_house'] ?? '',
      source: json['source'] ?? '',
      quantity: (json['quantity'] as num).toDouble(),
      nav: (json['nav'] as num).toDouble(),
      currentNav: (json['current_nav'] as num?)?.toDouble() ?? 0.0,
      purchaseDate: DateTime.parse(json['purchase_date']),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      return2021: _optDouble(json['return_2021']),
      return2022: _optDouble(json['return_2022']),
      return2023: _optDouble(json['return_2023']),
      return2024: _optDouble(json['return_2024']),
      return2025: _optDouble(json['return_2025']),
      returnYtd: _optDouble(json['return_ytd']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isin': isin.trim(),
      'scheme_code': schemeCode,
      'scheme_name': schemeName,
      'source_scheme_name': sourceSchemeName.trim(),
      'fund_house': fundHouse,
      'source': source.trim().isEmpty ? 'Manual Add' : source.trim(),
      'quantity': quantity,
      'nav': nav,
      'current_nav': currentNav,
      'purchase_date': purchaseDate.toUtc().toIso8601String(),
    };
  }
}
