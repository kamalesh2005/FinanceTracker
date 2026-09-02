import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/jwt_utils.dart';

void main() {
  test('expiryFromToken reads exp claim', () {
    final exp = DateTime.utc(2026, 8, 28, 6, 22, 36);
    final payload = base64Url.encode(utf8.encode(json.encode({
      'exp': exp.millisecondsSinceEpoch ~/ 1000,
    })));
    final token = 'hdr.$payload.sig';
    final parsed = JwtUtils.expiryFromToken(token);
    expect(parsed, isNotNull);
    expect(parsed!.toUtc(), exp);
  });

  test('shouldRefresh is true near expiry', () {
    final exp = DateTime.now().add(const Duration(minutes: 3));
    final payload = base64Url.encode(utf8.encode(json.encode({
      'exp': exp.millisecondsSinceEpoch ~/ 1000,
    })));
    final token = 'hdr.$payload.sig';
    expect(JwtUtils.shouldRefresh(token), isTrue);
  });
}
