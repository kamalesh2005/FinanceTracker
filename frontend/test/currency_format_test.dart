import 'package:finance_tracker/utils/currency_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatInr uses the rupee symbol, not Rs', () {
    final formatted = formatInr(304);
    expect(formatted, contains('₹'));
    expect(formatted, isNot(contains('Rs')));
    expect(formatted, contains('304'));
  });

  test('formatQty drops decimals', () {
    expect(formatQty(10), '10');
    expect(formatQty(10.0), '10');
    expect(formatQty(10.4), '10');
    expect(formatQty(10.6), '11');
  });
}
