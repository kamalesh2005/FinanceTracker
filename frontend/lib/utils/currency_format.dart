import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String formatInr(num value) => _inr.format(value);

/// Whole-unit quantity with no decimal places.
String formatQty(num value) => value.round().toString();

/// Formats an amount that is already in thousands (K = ₹1,000).
String formatInrK(num value) => '${formatInr(value)} K';
