class AppUser {
  final int id;
  final String? username;
  final String? email;
  final String? mobile;
  final String role;
  final bool enabled;

  AppUser({
    required this.id,
    this.username,
    this.email,
    this.mobile,
    required this.role,
    required this.enabled,
  });

  bool get isAdmin => role == 'admin';

  String get displayName {
    if (username != null && username!.isNotEmpty) return username!;
    if (email != null && email!.isNotEmpty) return email!;
    if (mobile != null && mobile!.isNotEmpty) return mobile!;
    return 'User #$id';
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String?,
      email: json['email'] as String?,
      mobile: json['mobile'] as String?,
      role: json['role'] as String? ?? 'user',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
