import 'dart:convert';

/// Reads the `exp` claim from a JWT without verifying the signature.
class JwtUtils {
  static DateTime? expiryFromToken(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload = json.decode(utf8.decode(base64Url.decode(normalized)));
      if (payload is! Map) return null;
      final exp = payload['exp'];
      if (exp is int) {
        return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true).toLocal();
      }
      if (exp is num) {
        return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true)
            .toLocal();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// True when the token is missing, unparsable, or expires within [within].
  static bool shouldRefresh(String? token, {Duration within = const Duration(minutes: 5)}) {
    final exp = expiryFromToken(token);
    if (exp == null) return true;
    return DateTime.now().add(within).isAfter(exp);
  }
}
