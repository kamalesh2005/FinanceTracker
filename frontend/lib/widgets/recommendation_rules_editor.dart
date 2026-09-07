import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/recommendation_engine.dart';

/// Tabular editor for named values + recommendation/trend rules (no raw JSON).
class RecommendationRulesEditor extends StatefulWidget {
  final RecommendationRuleset initial;
  final ValueChanged<RecommendationRuleset>? onChanged;

  /// When true, recommendation label fields are read-only (non-admin Configure / trends).
  final bool lockRecommendationText;

  /// When true, rules cannot be added or removed (trend labels are fixed).
  final bool fixedRules;

  /// When false, hide the Add rule button (non-admin Configure).
  final bool allowAddRule;

  /// When true, hide On Match column and force exit on save.
  final bool hideOnMatch;

  /// Column header for the recommendation/trend label.
  final String labelColumnTitle;

  /// Section heading above the rules table.
  final String rulesHeading;

  /// Help text under the rules heading.
  final String rulesHint;

  /// ExpansionTile body for field names.
  final String fieldHelpText;

  /// Builtin identifiers allowed in conditions (defaults to signal fields).
  final Set<String>? builtinFields;

  const RecommendationRulesEditor({
    super.key,
    required this.initial,
    this.onChanged,
    this.lockRecommendationText = false,
    this.fixedRules = false,
    this.allowAddRule = true,
    this.hideOnMatch = false,
    this.labelColumnTitle = 'Signal',
    this.rulesHeading = 'Signal rules',
    this.rulesHint =
        'Evaluated top to bottom. Exit stops; Continue may combine labels with OR.',
    this.fieldHelpText =
        'curr_price — current market price\n'
        'avg_buy_price — average buy price\n'
        'last_trade_price — latest buy/sell/hold price\n'
        'last_trade_is_buy / last_trade_is_sale / last_trade_is_hold — booleans\n'
        'abs_pct_from_last_trade — |curr − last| / last × 100\n'
        'last_trade_rule_validity_days — ignore last Buy/Sell/Hold older than this many days (default 30)\n'
        'set_buy_price / set_profit_booking_price / set_stop_loss_price — thresholds (ignored when unset / 0)\n'
        'highest_price — highest price\n'
        'lowest_price — lowest price\n'
        'trend — e.g. "bullish", "bearish_st", "bearish_lt"\n'
        'adjusted_st_delta — stock ST delta minus Sensex ST delta\n'
        'adjusted_mt_delta — stock MT delta minus Sensex MT delta\n'
        'review_adj_delta_pct — named value for Review conflict threshold (default 2)\n\n'
        'Use AND / OR, parentheses, and comparisons like:\n'
        'curr_price < avg_buy_price * 0.9',
    this.builtinFields,
  });

  /// Builtin fields for trend classification conditions.
  static const trendBuiltinFields = {
    'curr_price',
    'ma7',
    'ma20',
    'ma50',
    'adjusted_st_delta',
    'adjusted_mt_delta',
    'st_bearish_strength',
    'lt_bearish_strength',
  };

  static const trendFieldHelpText =
      'curr_price — current market price\n'
      'ma7 / ma20 / ma50 — simple moving averages\n'
      'adjusted_st_delta — stock ST delta minus Sensex ST delta\n'
      'adjusted_mt_delta — stock MT delta minus Sensex MT delta\n'
      'st_bearish_strength — 0/1/2 from price vs ma7/ma20 and adjusted_st_delta\n'
      'lt_bearish_strength — 0/1/2 from price vs ma20/ma50 and adjusted_mt_delta\n'
      'bearish_delta_threshold — named value used for strength (default 10)\n'
      'price_ma_tolerance_pct — noise band for price vs MA (default 2.5); clearly above means a > b*(1+tol/100)\n'
      'ma_ma_tolerance_pct — noise band for MA vs MA (default 1.0); clearly below means a < b*(1-tol/100)\n\n'
      'Use AND / OR, parentheses, and comparisons. First matching Exit wins.';

  @override
  State<RecommendationRulesEditor> createState() =>
      RecommendationRulesEditorState();
}

class RecommendationRulesEditorState extends State<RecommendationRulesEditor> {
  late List<_NvRow> _named;
  late List<_RuleRow> _rules;

  @override
  void initState() {
    super.initState();
    _load(widget.initial);
  }

  @override
  void didUpdateWidget(covariant RecommendationRulesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _load(widget.initial);
    }
  }

  void _load(RecommendationRuleset rs) {
    _named = rs.namedValues
        .map((e) => _NvRow(
              name: TextEditingController(text: e.name),
              value: TextEditingController(text: _fmt(e.value)),
            ))
        .toList();
    final sorted = [...rs.rules]..sort((a, b) => a.order.compareTo(b.order));
    _rules = sorted
        .map((e) => _RuleRow(
              recommendation: TextEditingController(text: e.recommendation),
              condition: TextEditingController(text: _uiCondition(e.condition)),
              onMatch: e.onMatch,
              enabled: e.enabled,
            ))
        .toList();
  }

  String _fmt(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  /// Show friendlier field names in the editor; evaluation still accepts both.
  static final _unsetGuardLead = RegExp(
    r'\b(set_buy_price|set_stop_loss_price|set_profit_booking_price)\s*>\s*0(?:\.0+)?\s+AND\s+',
    caseSensitive: false,
  );
  static final _unsetGuardTrail = RegExp(
    r'\s+AND\s+(set_buy_price|set_stop_loss_price|set_profit_booking_price)\s*>\s*0(?:\.0+)?\b',
    caseSensitive: false,
  );

  static String _uiCondition(String cond) {
    var next = cond
        .replaceAll('sixth_highest_price', 'highest_price')
        .replaceAll('sixth_lowest_price', 'lowest_price');
    next = next.replaceAll(_unsetGuardLead, '');
    next = next.replaceAll(_unsetGuardTrail, '');
    return next.trim();
  }

  RecommendationRuleset? buildRuleset({List<String>? errors}) {
    final nvs = <NamedValue>[];
    final names = <String>{};
    final builtins =
        widget.builtinFields ?? RecommendationEngine.builtinFields;
    for (var i = 0; i < _named.length; i++) {
      final name = _named[i].name.text.trim();
      final val = double.tryParse(_named[i].value.text.trim());
      if (name.isEmpty) {
        errors?.add('Named value #${i + 1}: name required');
        continue;
      }
      if (builtins.contains(name)) {
        errors?.add('Named value "$name" conflicts with a built-in field');
        return null;
      }
      if (!names.add(name)) {
        errors?.add('Duplicate named value "$name"');
        return null;
      }
      if (val == null) {
        errors?.add('Named value "$name": invalid number');
        return null;
      }
      nvs.add(NamedValue(name: name, value: val));
    }

    final rules = <RecommendationRule>[];
    for (var i = 0; i < _rules.length; i++) {
      final rec = _rules[i].recommendation.text.trim();
      final cond = _rules[i].condition.text.trim();
      if (rec.isEmpty) {
        errors?.add('Rule #${i + 1}: ${widget.labelColumnTitle.toLowerCase()} required');
        return null;
      }
      final err = RecommendationEngine.validateCondition(
        cond,
        nvs,
        builtinFields: builtins,
      );
      if (err != null) {
        errors?.add('Rule "$rec": $err');
        return null;
      }
      rules.add(RecommendationRule(
        order: i + 1,
        recommendation: rec,
        condition: cond,
        onMatch: widget.hideOnMatch ? 'exit' : _rules[i].onMatch,
        enabled: _rules[i].enabled,
      ));
    }
    if (rules.isEmpty) {
      errors?.add('At least one rule is required');
      return null;
    }
    return RecommendationRuleset(namedValues: nvs, rules: rules);
  }

  void _notify() {
    final rs = buildRuleset();
    if (rs != null) widget.onChanged?.call(rs);
    setState(() {});
  }

  @override
  void dispose() {
    for (final n in _named) {
      n.name.dispose();
      n.value.dispose();
    }
    for (final r in _rules) {
      r.recommendation.dispose();
      r.condition.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Named values', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Reusable numbers you can use in conditions (e.g. fluctuation_pct).',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        ...List.generate(_named.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _named[i].name,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _notify(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _named[i].value,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _notify(),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () {
                    setState(() {
                      _named[i].name.dispose();
                      _named[i].value.dispose();
                      _named.removeAt(i);
                    });
                    _notify();
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _named.add(_NvRow(
                  name: TextEditingController(),
                  value: TextEditingController(text: '0'),
                ));
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Add named value'),
          ),
        ),
        const SizedBox(height: 20),
        Text(widget.rulesHeading, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          widget.rulesHint,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        _buildRulesTable(),
        if (!widget.fixedRules && widget.allowAddRule)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _rules.add(_RuleRow(
                    recommendation: TextEditingController(),
                    condition: TextEditingController(),
                    onMatch: 'continue',
                    enabled: true,
                  ));
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Add rule'),
            ),
          ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('Field names help'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            Text(
              widget.fieldHelpText,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ],
        ),
      ],
    );
  }

  static const double _colOrder = 48;
  static const double _colRecommendation = 160;
  static const double _colCondition = 320;
  static const double _colOnMatch = 120;
  static const double _colActions = 200;

  double get _tableMinWidth {
    var w = _colOrder + _colRecommendation + _colCondition + _colActions;
    if (!widget.hideOnMatch) w += _colOnMatch;
    return w;
  }

  Widget _buildRulesTable() {
    final borderColor = Colors.grey.shade300;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > _tableMinWidth
            ? constraints.maxWidth
            : _tableMinWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRulesHeaderRow(borderColor),
                if (_rules.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: borderColor),
                        left: BorderSide(color: borderColor),
                        right: BorderSide(color: borderColor),
                      ),
                    ),
                    child: Text(
                      'No rules yet. Add a rule to get started.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                else
                  ...List.generate(
                    _rules.length,
                    (i) => _buildRuleTableRow(i, borderColor),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRulesHeaderRow(Color borderColor) {
    final style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 13,
      color: Colors.grey.shade800,
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: _colOrder, child: Text('Order', style: style)),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(widget.labelColumnTitle, style: style),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('Condition', style: style),
            ),
          ),
          if (!widget.hideOnMatch)
            SizedBox(
              width: _colOnMatch,
              child: Text('On Match', style: style),
            ),
          SizedBox(
            width: _colActions,
            child: Text('Actions', style: style),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleTableRow(int i, Color borderColor) {
    final r = _rules[i];
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _colOrder,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${i + 1}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: r.recommendation,
                readOnly: widget.lockRecommendationText,
                decoration: InputDecoration(
                  hintText: widget.fixedRules ? null : 'e.g. BUY',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  filled: widget.lockRecommendationText,
                  fillColor: widget.lockRecommendationText
                      ? Colors.grey.shade100
                      : null,
                ),
                onChanged:
                    widget.lockRecommendationText ? null : (_) => _notify(),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: r.condition,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'curr_price < ma7 AND ma7 > ma20',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _notify(),
              ),
            ),
          ),
          if (!widget.hideOnMatch)
            SizedBox(
              width: _colOnMatch,
              child: DropdownButtonFormField<String>(
                value: r.onMatch,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: 'exit', child: Text('Exit')),
                  DropdownMenuItem(value: 'continue', child: Text('Continue')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => r.onMatch = v);
                  _notify();
                },
              ),
            ),
          SizedBox(
            width: _colActions,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: r.enabled ? 'Enabled' : 'Disabled',
                  child: Switch(
                    value: r.enabled,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) {
                      setState(() => r.enabled = v);
                      _notify();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: i == 0
                      ? null
                      : () {
                          setState(() {
                            final t = _rules.removeAt(i);
                            _rules.insert(i - 1, t);
                          });
                          _notify();
                        },
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: 'Move down',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: i >= _rules.length - 1
                      ? null
                      : () {
                          setState(() {
                            final t = _rules.removeAt(i);
                            _rules.insert(i + 1, t);
                          });
                          _notify();
                        },
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
                if (!widget.fixedRules)
                  IconButton(
                    tooltip: 'Remove',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      setState(() {
                        r.recommendation.dispose();
                        r.condition.dispose();
                        _rules.removeAt(i);
                      });
                      _notify();
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NvRow {
  final TextEditingController name;
  final TextEditingController value;
  _NvRow({required this.name, required this.value});
}

class _RuleRow {
  final TextEditingController recommendation;
  final TextEditingController condition;
  String onMatch;
  bool enabled;
  _RuleRow({
    required this.recommendation,
    required this.condition,
    required this.onMatch,
    required this.enabled,
  });
}
