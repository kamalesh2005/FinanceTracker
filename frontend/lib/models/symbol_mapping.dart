class SymbolMapping {
  final int id;
  final String sourceSymbol;
  final String yahooSymbol;
  final String isin;
  final String sourceFormat;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  SymbolMapping({
    required this.id,
    required this.sourceSymbol,
    required this.yahooSymbol,
    this.isin = '',
    this.sourceFormat = 'Manual',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory SymbolMapping.fromJson(Map<String, dynamic> json) {
    return SymbolMapping(
      id: json['id'] ?? 0,
      sourceSymbol: json['source_symbol'] ?? '',
      yahooSymbol: json['yahoo_symbol'] ?? '',
      isin: json['isin'] ?? '',
      sourceFormat: json['source_format'] ?? 'Manual',
      notes: json['notes'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'source_symbol': sourceSymbol,
      'yahoo_symbol': yahooSymbol,
      if (isin.isNotEmpty) 'isin': isin,
      'source_format': sourceFormat,
      'notes': notes,
    };
  }
}

class UnmappedStock {
  final int id;
  final String symbol;
  final String name;
  final String sector;
  final String industry;
  final double currentPrice;
  final double sixthHighestPrice;
  final String yahooSymbol;
  final String isin;
  final bool hasMapping;
  final bool needsAttention;
  final String reason;

  UnmappedStock({
    required this.id,
    required this.symbol,
    required this.name,
    this.sector = '',
    this.industry = '',
    this.currentPrice = 0,
    this.sixthHighestPrice = 0,
    this.yahooSymbol = '',
    this.isin = '',
    this.hasMapping = false,
    this.needsAttention = true,
    this.reason = '',
  });

  factory UnmappedStock.fromJson(Map<String, dynamic> json) {
    return UnmappedStock(
      id: json['id'] ?? 0,
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      sector: json['sector'] ?? '',
      industry: json['industry'] ?? '',
      currentPrice: (json['current_price'] as num?)?.toDouble() ?? 0,
      sixthHighestPrice: (json['sixth_highest_price'] as num?)?.toDouble() ?? 0,
      yahooSymbol: json['yahoo_symbol'] ?? '',
      isin: json['isin'] ?? '',
      hasMapping: json['has_mapping'] ?? false,
      needsAttention: json['needs_attention'] ?? true,
      reason: json['reason'] ?? '',
    );
  }
}
