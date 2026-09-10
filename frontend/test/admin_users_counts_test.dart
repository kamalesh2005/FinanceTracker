import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/user.dart';

void main() {
  test('AppUser.fromJson reads DhanShanti stock and FlexStreet challenge counts', () {
    final user = AppUser.fromJson({
      'id': 7,
      'role': 'user',
      'enabled': true,
      'stock_count': 12,
      'inv_challenge_count': 3,
    });
    expect(user.stockCount, 12);
    expect(user.invChallengeCount, 3);
  });

  test('AppUser.fromJson defaults missing counts to zero', () {
    final user = AppUser.fromJson({
      'id': 1,
      'role': 'admin',
      'enabled': true,
    });
    expect(user.stockCount, 0);
    expect(user.invChallengeCount, 0);
  });
}
