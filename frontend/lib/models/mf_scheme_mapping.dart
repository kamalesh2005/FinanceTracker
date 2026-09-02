class MFSchemeMapping {
  final int id;
  final String sourceSchemeName;
  final String mappedIsin;
  final String sourceFormat;
  final String ignore;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  MFSchemeMapping({
    required this.id,
    required this.sourceSchemeName,
    this.mappedIsin = '',
    this.sourceFormat = '',
    this.ignore = 'N',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isMapped => mappedIsin.trim().isNotEmpty;

  factory MFSchemeMapping.fromJson(Map<String, dynamic> json) {
    final rawIgnore = (json['ignore'] ?? '').toString().trim().toUpperCase();
    return MFSchemeMapping(
      id: json['id'] ?? 0,
      sourceSchemeName: json['source_scheme_name']?.toString() ?? '',
      mappedIsin: json['mapped_isin']?.toString() ?? '',
      sourceFormat: json['source_format']?.toString() ?? '',
      ignore: rawIgnore == 'Y' ? 'Y' : 'N',
      notes: json['notes']?.toString() ?? '',
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
      'source_scheme_name': sourceSchemeName.trim(),
      'mapped_isin': mappedIsin.trim().toUpperCase(),
      'source_format': sourceFormat.trim(),
      'ignore': ignore == 'Y' ? 'Y' : 'N',
      'notes': notes.trim(),
    };
  }
}
