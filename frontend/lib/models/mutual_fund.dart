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
  });

  /// Catalog name when linked; otherwise broker upload name.
  String get displayName {
    final catalog = schemeName.trim();
    if (catalog.isNotEmpty) return catalog;
    return sourceSchemeName.trim();
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
