class MutualFund {
  final int id;
  final String schemeCode;
  final String schemeName;
  final String fundHouse;
  final double quantity;
  final double nav;
  final double currentNav;
  final DateTime purchaseDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  MutualFund({
    required this.id,
    required this.schemeCode,
    required this.schemeName,
    required this.fundHouse,
    required this.quantity,
    required this.nav,
    required this.currentNav,
    required this.purchaseDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MutualFund.fromJson(Map<String, dynamic> json) {
    return MutualFund(
      id: json['id'],
      schemeCode: json['scheme_code'],
      schemeName: json['scheme_name'] ?? '',
      fundHouse: json['fund_house'] ?? '',
      quantity: json['quantity'].toDouble(),
      nav: json['nav'].toDouble(),
      currentNav: json['current_nav']?.toDouble() ?? 0.0,
      purchaseDate: DateTime.parse(json['purchase_date']),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scheme_code': schemeCode,
      'scheme_name': schemeName,
      'fund_house': fundHouse,
      'quantity': quantity,
      'nav': nav,
      'current_nav': currentNav,
      'purchase_date': purchaseDate.toUtc().toIso8601String(),
    };
  }
}
