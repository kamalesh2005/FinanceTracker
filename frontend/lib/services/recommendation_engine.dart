import '../models/stock.dart';
import '../models/stock_trend.dart';

class NamedValue {
  final String name;
  final double value;

  NamedValue({required this.name, required this.value});

  factory NamedValue.fromJson(Map<String, dynamic> json) {
    return NamedValue(
      name: (json['name'] ?? '').toString(),
      value: (json['value'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'value': value};

  NamedValue copyWith({String? name, double? value}) => NamedValue(
        name: name ?? this.name,
        value: value ?? this.value,
      );
}

class RecommendationRule {
  final int order;
  final String recommendation;
  final String condition;
  final String onMatch; // exit | continue
  final bool enabled;

  RecommendationRule({
    required this.order,
    required this.recommendation,
    required this.condition,
    this.onMatch = 'continue',
    this.enabled = true,
  });

  factory RecommendationRule.fromJson(Map<String, dynamic> json) {
    return RecommendationRule(
      order: (json['order'] as num?)?.toInt() ?? 0,
      recommendation: (json['recommendation'] ?? '').toString(),
      condition: (json['condition'] ?? '').toString(),
      onMatch:
          ((json['on_match'] ?? 'continue').toString().toLowerCase() == 'exit')
              ? 'exit'
              : 'continue',
      enabled: json['enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'order': order,
        'recommendation': recommendation,
        'condition': condition,
        'on_match': onMatch,
        'enabled': enabled,
      };

  RecommendationRule copyWith({
    int? order,
    String? recommendation,
    String? condition,
    String? onMatch,
    bool? enabled,
  }) =>
      RecommendationRule(
        order: order ?? this.order,
        recommendation: recommendation ?? this.recommendation,
        condition: condition ?? this.condition,
        onMatch: onMatch ?? this.onMatch,
        enabled: enabled ?? this.enabled,
      );
}

class RecommendationRuleset {
  final List<NamedValue> namedValues;
  final List<RecommendationRule> rules;

  RecommendationRuleset({
    List<NamedValue>? namedValues,
    List<RecommendationRule>? rules,
  })  : namedValues = namedValues ?? [],
        rules = rules ?? [];

  factory RecommendationRuleset.fromJson(Map<String, dynamic>? json) {
    if (json == null) return RecommendationRuleset.defaults();
    final nvs = <NamedValue>[];
    final rawNv = json['named_values'];
    if (rawNv is List) {
      for (final e in rawNv) {
        if (e is Map<String, dynamic>) nvs.add(NamedValue.fromJson(e));
      }
    }
    final rules = <RecommendationRule>[];
    final rawRules = json['rules'];
    if (rawRules is List) {
      for (final e in rawRules) {
        if (e is Map<String, dynamic>) {
          rules.add(RecommendationRule.fromJson(e));
        }
      }
    }
    rules.sort((a, b) => a.order.compareTo(b.order));
    if (rules.isEmpty) return RecommendationRuleset.defaults();
    return RecommendationRuleset(namedValues: nvs, rules: rules);
  }

  Map<String, dynamic> toJson() => {
        'named_values': namedValues.map((e) => e.toJson()).toList(),
        'rules': rules.map((e) => e.toJson()).toList(),
      };

  double get fluctuationPct {
    for (final nv in namedValues) {
      if (nv.name == 'fluctuation_pct' && nv.value > 0) return nv.value;
    }
    return 5;
  }

  static RecommendationRuleset defaults({double fluctuationPct = 5}) {
    return RecommendationRuleset(
      namedValues: [NamedValue(name: 'fluctuation_pct', value: fluctuationPct)],
      rules: [
        RecommendationRule(
          order: 1,
          recommendation: 'AT BUY PRICE',
          condition:
              'abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_buy',
          onMatch: 'exit',
        ),
        RecommendationRule(
          order: 2,
          recommendation: 'AT SELL PRICE',
          condition:
              'abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_sale',
          onMatch: 'exit',
        ),
        RecommendationRule(
          order: 3,
          recommendation: 'AT HOLD PRICE',
          condition:
              'abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_hold',
          onMatch: 'exit',
        ),
        RecommendationRule(
          order: 4,
          recommendation: 'BUY',
          condition:
              '(set_buy_price > 0 AND curr_price < set_buy_price) OR (trend == "bullish" AND curr_price > avg_buy_price * 1.1)',
          onMatch: 'continue',
        ),
        RecommendationRule(
          order: 5,
          recommendation: 'Book Profit',
          condition:
              '(set_profit_booking_price > 0 AND curr_price > set_profit_booking_price) OR (sixth_highest_price > 0 AND curr_price >= sixth_highest_price * 0.95 AND curr_price > avg_buy_price)',
          onMatch: 'continue',
        ),
        RecommendationRule(
          order: 6,
          recommendation: 'SELL',
          condition:
              '(set_stop_loss_price > 0 AND curr_price < set_stop_loss_price) OR (trend == "moderately bearish_st" AND curr_price < avg_buy_price * 0.9) OR (trend == "bearish_st" OR trend == "bearish_lt" OR trend == "moderately bearish_lt")',
          onMatch: 'continue',
        ),
      ],
    );
  }
}

class RecommendationEngine {
  static const builtinFields = {
    'curr_price',
    'avg_buy_price',
    'last_trade_price',
    'last_trade_is_buy',
    'last_trade_is_sale',
    'last_trade_is_hold',
    'abs_pct_from_last_trade',
    'sixth_highest_price',
    'trend',
    'set_buy_price',
    'set_profit_booking_price',
    'set_stop_loss_price',
  };

  static String evaluate(
    Stock stock,
    StockTrend? trend,
    RecommendationRuleset ruleset,
  ) {
    final ctx = _buildContext(stock, trend, ruleset);
    final parts = <String>[];
    final ordered = [...ruleset.rules]
      ..sort((a, b) => a.order.compareTo(b.order));
    for (final rule in ordered) {
      if (!rule.enabled) continue;
      final cond = rule.condition.trim();
      if (cond.isEmpty) continue;
      bool matched;
      try {
        matched = _evalBool(cond, ctx);
      } catch (_) {
        matched = false;
      }
      if (!matched) continue;
      if (rule.onMatch == 'exit') {
        return rule.recommendation;
      }
      parts.add(rule.recommendation);
    }
    if (parts.isEmpty) return 'NO ACTION REQD';
    return parts.join(' & ');
  }

  static Map<String, dynamic> _buildContext(
    Stock stock,
    StockTrend? trend,
    RecommendationRuleset ruleset,
  ) {
    final lastTxn = stock.lastTradePrice;
    final curr = stock.currentPrice;
    final avg = stock.buyPrice;
    double absPct = 0;
    if (lastTxn != null && lastTxn > 0 && curr > 0) {
      absPct = ((curr - lastTxn).abs() / lastTxn) * 100.0;
    }
    final ctx = <String, dynamic>{
      'curr_price': curr,
      'avg_buy_price': avg,
      'last_trade_price': lastTxn ?? 0.0,
      'last_trade_is_buy': stock.lastTradeIsBuy,
      'last_trade_is_sale': stock.lastTradeIsSale,
      'last_trade_is_hold': stock.lastTradeIsHold,
      'abs_pct_from_last_trade': absPct,
      'sixth_highest_price': stock.sixthHighestPrice,
      'trend': trend?.trend ?? '',
      'set_buy_price': stock.setBuyPrice,
      'set_profit_booking_price': stock.setProfitBookingPrice,
      'set_stop_loss_price': stock.setStopLossPrice,
    };
    for (final nv in ruleset.namedValues) {
      ctx[nv.name] = nv.value;
    }
    return ctx;
  }

  /// Validates expression identifiers; returns error message or null.
  static String? validateCondition(
    String expr,
    List<NamedValue> namedValues,
  ) {
    final trimmed = expr.trim();
    if (trimmed.isEmpty) return null;
    if ('('.allMatches(trimmed).length != ')'.allMatches(trimmed).length) {
      return 'Unbalanced parentheses';
    }
    if ('"'.allMatches(trimmed).length.isOdd) {
      return 'Unbalanced string quotes';
    }
    final named = {for (final n in namedValues) n.name};
    final stripped = trimmed.replaceAll(RegExp(r'"[^"]*"'), '""');
    for (final m in RegExp(r'[A-Za-z_][A-Za-z0-9_]*').allMatches(stripped)) {
      final id = m.group(0)!;
      final up = id.toUpperCase();
      if (up == 'AND' || up == 'OR' || up == 'TRUE' || up == 'FALSE') continue;
      if (builtinFields.contains(id) || named.contains(id)) continue;
      return 'Unknown identifier "$id"';
    }
    try {
      _evalBool(trimmed, {
        for (final f in builtinFields)
          f: f == 'trend' ? '' : (f.startsWith('last_trade_is') ? false : 0.0),
        for (final n in namedValues) n.name: n.value,
      });
    } catch (e) {
      return e.toString();
    }
    return null;
  }

  static bool _evalBool(String expr, Map<String, dynamic> ctx) {
    final p = _Parser(expr, ctx);
    final v = p.parseOr();
    p.expectEnd();
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty;
    return false;
  }
}

class _Parser {
  final String src;
  final Map<String, dynamic> ctx;
  int i = 0;

  _Parser(this.src, this.ctx);

  void expectEnd() {
    _skip();
    if (i < src.length) {
      throw FormatException('Unexpected input near "${src.substring(i)}"');
    }
  }

  dynamic parseOr() {
    var left = parseAnd();
    while (true) {
      _skip();
      if (_matchWord('OR')) {
        final right = parseAnd();
        left = _asBool(left) || _asBool(right);
      } else {
        break;
      }
    }
    return left;
  }

  dynamic parseAnd() {
    var left = parseComparison();
    while (true) {
      _skip();
      if (_matchWord('AND')) {
        final right = parseComparison();
        left = _asBool(left) && _asBool(right);
      } else {
        break;
      }
    }
    return left;
  }

  dynamic parseComparison() {
    var left = parseAdd();
    _skip();
    if (_match('==')) {
      return _equals(left, parseAdd());
    }
    if (_match('!=')) {
      return !_equals(left, parseAdd());
    }
    if (_match('<=')) {
      return _num(left) <= _num(parseAdd());
    }
    if (_match('>=')) {
      return _num(left) >= _num(parseAdd());
    }
    if (_match('<')) {
      return _num(left) < _num(parseAdd());
    }
    if (_match('>')) {
      return _num(left) > _num(parseAdd());
    }
    return left;
  }

  dynamic parseAdd() {
    var left = parseMul();
    while (true) {
      _skip();
      if (_match('+')) {
        left = _num(left) + _num(parseMul());
      } else if (_match('-')) {
        left = _num(left) - _num(parseMul());
      } else {
        break;
      }
    }
    return left;
  }

  dynamic parseMul() {
    var left = parseUnary();
    while (true) {
      _skip();
      if (_match('*')) {
        left = _num(left) * _num(parseUnary());
      } else if (_match('/')) {
        final r = _num(parseUnary());
        left = r == 0 ? 0.0 : _num(left) / r;
      } else {
        break;
      }
    }
    return left;
  }

  dynamic parseUnary() {
    _skip();
    if (_match('-')) {
      return -_num(parseUnary());
    }
    if (_match('+')) {
      return _num(parseUnary());
    }
    return parsePrimary();
  }

  dynamic parsePrimary() {
    _skip();
    if (_match('(')) {
      final v = parseOr();
      _skip();
      if (!_match(')')) throw const FormatException('Expected )');
      return v;
    }
    if (i < src.length && src[i] == '"') {
      i++;
      final start = i;
      while (i < src.length && src[i] != '"') {
        i++;
      }
      if (i >= src.length) throw const FormatException('Unterminated string');
      final s = src.substring(start, i);
      i++;
      return s;
    }
    if (i < src.length &&
        (src.codeUnitAt(i) >= 48 && src.codeUnitAt(i) <= 57 || src[i] == '.')) {
      final start = i;
      while (i < src.length &&
          (src.codeUnitAt(i) >= 48 && src.codeUnitAt(i) <= 57 ||
              src[i] == '.')) {
        i++;
      }
      return double.parse(src.substring(start, i));
    }
    final id = _readIdent();
    if (id == null) {
      throw FormatException('Expected value near "${src.substring(i)}"');
    }
    final up = id.toUpperCase();
    if (up == 'TRUE') return true;
    if (up == 'FALSE') return false;
    if (!ctx.containsKey(id)) {
      throw FormatException('Unknown identifier "$id"');
    }
    return ctx[id];
  }

  String? _readIdent() {
    _skip();
    if (i >= src.length) return null;
    final c = src.codeUnitAt(i);
    if (!(c >= 65 && c <= 90 || c >= 97 && c <= 122 || c == 95)) return null;
    final start = i;
    i++;
    while (i < src.length) {
      final d = src.codeUnitAt(i);
      if (d >= 65 && d <= 90 ||
          d >= 97 && d <= 122 ||
          d >= 48 && d <= 57 ||
          d == 95) {
        i++;
      } else {
        break;
      }
    }
    return src.substring(start, i);
  }

  bool _matchWord(String word) {
    final save = i;
    final id = _readIdent();
    if (id != null && id.toUpperCase() == word) return true;
    i = save;
    return false;
  }

  bool _match(String s) {
    _skip();
    if (src.startsWith(s, i)) {
      i += s.length;
      return true;
    }
    return false;
  }

  void _skip() {
    while (i < src.length &&
        (src[i] == ' ' || src[i] == '\t' || src[i] == '\n' || src[i] == '\r')) {
      i++;
    }
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty;
    return false;
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1 : 0;
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static bool _equals(dynamic a, dynamic b) {
    if (a is num && b is num) return (a - b).abs() < 1e-12;
    return a.toString() == b.toString();
  }
}
