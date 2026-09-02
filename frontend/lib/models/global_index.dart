class GlobalIndex {
  final int id;
  final String symbol;
  final String name;
  final String yahooSymbol;
  final double currentValue;
  final DateTime? lastValueDate;
  final double fy2020;
  final double fy2021;
  final double fy2022;
  final double fy2023;
  final double fy2024;
  final double fy2025;
  final double? return2021;
  final double? return2022;
  final double? return2023;
  final double? return2024;
  final double? return2025;
  final double? returnYtd;

  GlobalIndex({
    required this.id,
    required this.symbol,
    required this.name,
    this.yahooSymbol = '',
    this.currentValue = 0,
    this.lastValueDate,
    this.fy2020 = 0,
    this.fy2021 = 0,
    this.fy2022 = 0,
    this.fy2023 = 0,
    this.fy2024 = 0,
    this.fy2025 = 0,
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

  static double? _optDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory GlobalIndex.fromJson(Map<String, dynamic> json) {
    DateTime? last;
    final raw = json['last_value_date'];
    if (raw is String && raw.isNotEmpty) {
      last = DateTime.tryParse(raw);
    }
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return GlobalIndex(
      id: (json['id'] as num?)?.toInt() ?? 0,
      symbol: json['symbol']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      yahooSymbol: json['yahoo_symbol']?.toString() ?? '',
      currentValue: d(json['current_value']),
      lastValueDate: last,
      fy2020: d(json['fy_2020']),
      fy2021: d(json['fy_2021']),
      fy2022: d(json['fy_2022']),
      fy2023: d(json['fy_2023']),
      fy2024: d(json['fy_2024']),
      fy2025: d(json['fy_2025']),
      return2021: _optDouble(json['return_2021']),
      return2022: _optDouble(json['return_2022']),
      return2023: _optDouble(json['return_2023']),
      return2024: _optDouble(json['return_2024']),
      return2025: _optDouble(json['return_2025']),
      returnYtd: _optDouble(json['return_ytd']),
    );
  }
}
