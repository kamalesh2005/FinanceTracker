class AppUser {
  final int id;
  final String? username;
  final String? email;
  final String? mobile;
  final String role;
  final bool enabled;
  final DateTime? lastLoginAt;
  final int loginCount;
  final double? recommendationFluctuationPct;
  final bool recommendationRulesIsOverride;
  final int recommendationRulesCount;
  final Map<String, dynamic>? recommendationRules;

  AppUser({
    required this.id,
    this.username,
    this.email,
    this.mobile,
    required this.role,
    required this.enabled,
    this.lastLoginAt,
    this.loginCount = 0,
    this.recommendationFluctuationPct,
    this.recommendationRulesIsOverride = false,
    this.recommendationRulesCount = 0,
    this.recommendationRules,
  });

  bool get isAdmin => role == 'admin';

  String get displayName {
    if (username != null && username!.isNotEmpty) return username!;
    if (email != null && email!.isNotEmpty) return email!;
    if (mobile != null && mobile!.isNotEmpty) return mobile!;
    return 'User #$id';
  }

  /// Username → email → mobile (no numeric id fallback).
  String get menuIdentity {
    if (username != null && username!.isNotEmpty) return username!;
    if (email != null && email!.isNotEmpty) return email!;
    if (mobile != null && mobile!.isNotEmpty) return mobile!;
    return 'User #$id';
  }

  /// First letter of username → email → first digit/char of mobile → '?'.
  String get avatarInitial {
    final u = username?.trim();
    if (u != null && u.isNotEmpty) return u[0].toUpperCase();
    final e = email?.trim();
    if (e != null && e.isNotEmpty) return e[0].toUpperCase();
    final m = mobile?.trim();
    if (m != null && m.isNotEmpty) return m[0].toUpperCase();
    return '?';
  }

  AppUser copyWith({
    int? id,
    String? username,
    String? email,
    String? mobile,
    String? role,
    bool? enabled,
    DateTime? lastLoginAt,
    int? loginCount,
    double? recommendationFluctuationPct,
    bool? recommendationRulesIsOverride,
    int? recommendationRulesCount,
    Map<String, dynamic>? recommendationRules,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      mobile: mobile ?? this.mobile,
      role: role ?? this.role,
      enabled: enabled ?? this.enabled,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      loginCount: loginCount ?? this.loginCount,
      recommendationFluctuationPct:
          recommendationFluctuationPct ?? this.recommendationFluctuationPct,
      recommendationRulesIsOverride:
          recommendationRulesIsOverride ?? this.recommendationRulesIsOverride,
      recommendationRulesCount:
          recommendationRulesCount ?? this.recommendationRulesCount,
      recommendationRules: recommendationRules ?? this.recommendationRules,
    );
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    DateTime? lastLogin;
    final raw = json['last_login_at'];
    if (raw is String && raw.isNotEmpty) {
      lastLogin = DateTime.tryParse(raw)?.toLocal();
    }

    Map<String, dynamic>? rules;
    final rawRules = json['recommendation_rules'];
    if (rawRules is Map<String, dynamic>) {
      rules = rawRules;
    } else if (rawRules is Map) {
      rules = Map<String, dynamic>.from(rawRules);
    }

    return AppUser(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String?,
      email: json['email'] as String?,
      mobile: json['mobile'] as String?,
      role: json['role'] as String? ?? 'user',
      enabled: json['enabled'] as bool? ?? true,
      lastLoginAt: lastLogin,
      loginCount: (json['login_count'] as num?)?.toInt() ?? 0,
      recommendationFluctuationPct:
          (json['recommendation_fluctuation_pct'] as num?)?.toDouble(),
      recommendationRulesIsOverride:
          json['recommendation_rules_is_override'] == true,
      recommendationRulesCount:
          (json['recommendation_rules_count'] as num?)?.toInt() ?? 0,
      recommendationRules: rules,
    );
  }
}
