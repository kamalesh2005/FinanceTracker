import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/recommendation_engine.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import '../widgets/recommendation_rules_editor.dart';

class AdminAppSettingsScreen extends StatefulWidget {
  const AdminAppSettingsScreen({super.key});

  @override
  State<AdminAppSettingsScreen> createState() => _AdminAppSettingsScreenState();
}

class _AdminAppSettingsScreenState extends State<AdminAppSettingsScreen> {
  final _signalRulesKey = GlobalKey<RecommendationRulesEditorState>();
  final _trendRulesKey = GlobalKey<RecommendationRulesEditorState>();
  RecommendationRuleset? _signalRules;
  RecommendationRuleset? _trendRules;
  bool _loading = true;
  bool _savingSignal = false;
  bool _savingTrend = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getAdminConfig();
      final signalRaw = data['recommendation_rules'];
      final trendRaw = data['trend_rules'];
      setState(() {
        _signalRules = signalRaw is Map<String, dynamic>
            ? RecommendationRuleset.fromJson(signalRaw)
            : RecommendationRuleset.defaults();
        _trendRules = trendRaw is Map<String, dynamic>
            ? RecommendationRuleset.fromJson(trendRaw)
            : _defaultTrendRuleset();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      setState(() {
        _signalRules = RecommendationRuleset.defaults();
        _trendRules = _defaultTrendRuleset();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Client-side fallback matching backend trendrules.DefaultRuleset labels.
  RecommendationRuleset _defaultTrendRuleset() {
    return RecommendationRuleset(
      namedValues: [
        NamedValue(name: 'bearish_delta_threshold', value: 10),
        NamedValue(name: 'price_ma_tolerance_pct', value: 2.5),
        NamedValue(name: 'ma_ma_tolerance_pct', value: 1.0),
      ],
      rules: [
        RecommendationRule(
          order: 1,
          recommendation: 'bullish',
          condition:
              'ma7 > 0 AND ma20 > 0 AND curr_price > ma7 * (1 + price_ma_tolerance_pct / 100) AND ma7 > ma20 * (1 + ma_ma_tolerance_pct / 100) AND adjusted_st_delta > 0',
          onMatch: 'exit',
        ),
        RecommendationRule(
          order: 2,
          recommendation: 'moderately bullish',
          condition:
              'ma7 > 0 AND ma20 > 0 AND ((curr_price > ma7 * (1 + price_ma_tolerance_pct / 100) AND ma7 > ma20 * (1 + ma_ma_tolerance_pct / 100)) OR (ma7 > ma20 * (1 + ma_ma_tolerance_pct / 100) AND curr_price <= ma7 * (1 + price_ma_tolerance_pct / 100) AND adjusted_st_delta > 0))',
          onMatch: 'exit',
        ),
        RecommendationRule(
          order: 3,
          recommendation: 'bearish_lt',
          condition:
              'ma7 > 0 AND ma20 > 0 AND ma7 <= ma20 * (1 + ma_ma_tolerance_pct / 100) AND st_bearish_strength == 2 AND lt_bearish_strength == 2',
          onMatch: 'exit',
        ),
        RecommendationRule(
          order: 4,
          recommendation: 'moderately bearish_lt',
          condition:
              'ma7 > 0 AND ma20 > 0 AND ma7 <= ma20 * (1 + ma_ma_tolerance_pct / 100) AND st_bearish_strength > 0 AND lt_bearish_strength > 0',
          onMatch: 'exit',
        ),
        RecommendationRule(
          order: 5,
          recommendation: 'bearish_st',
          condition:
              'ma7 > 0 AND ma20 > 0 AND ma7 <= ma20 * (1 + ma_ma_tolerance_pct / 100) AND st_bearish_strength == 2',
          onMatch: 'exit',
        ),
        RecommendationRule(
          order: 6,
          recommendation: 'moderately bearish_st',
          condition:
              'ma7 > 0 AND ma20 > 0 AND ma7 <= ma20 * (1 + ma_ma_tolerance_pct / 100) AND st_bearish_strength > 0',
          onMatch: 'exit',
        ),
        RecommendationRule(
          order: 7,
          recommendation: 'neutral',
          condition: 'TRUE',
          onMatch: 'exit',
        ),
      ],
    );
  }

  Future<void> _saveSignal() async {
    final errors = <String>[];
    final rs = _signalRulesKey.currentState?.buildRuleset(errors: errors);
    if (rs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errors.isEmpty ? 'Invalid signal rules' : errors.first),
        ),
      );
      return;
    }
    setState(() => _savingSignal = true);
    try {
      await ApiService.saveAdminConfig(recommendationRules: rs.toJson());
      if (!mounted) return;
      setState(() => _signalRules = rs);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signal rules saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _savingSignal = false);
    }
  }

  Future<void> _saveTrend() async {
    final errors = <String>[];
    final rs = _trendRulesKey.currentState?.buildRuleset(errors: errors);
    if (rs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errors.isEmpty ? 'Invalid trend rules' : errors.first),
        ),
      );
      return;
    }
    setState(() => _savingTrend = true);
    try {
      final data = await ApiService.saveAdminConfig(trendRules: rs.toJson());
      if (!mounted) return;
      setState(() => _trendRules = rs);
      final n = data['trends_reclassified'];
      final recErr = data['trends_reclassified_error'];
      final String message;
      if (recErr is String && recErr.isNotEmpty) {
        message = 'Trend rules saved. Trend recalculation failed: $recErr';
      } else if (n is num) {
        message = 'Trend rules saved. Recalculated ${n.toInt()} stocks.';
      } else {
        message = 'Trend rules saved';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _savingTrend = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('App Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: _loading || _signalRules == null || _trendRules == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Signal Rules',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Defaults for all users who have not set their own signal '
                  'rules. Seeded to match the previous built-in logic.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                RecommendationRulesEditor(
                  key: _signalRulesKey,
                  initial: _signalRules!,
                  rulesHeading: 'Signal rules',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _savingSignal ? null : _saveSignal,
                    child: const Text('Save signal rules'),
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Trend Rules',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Global classification rules for all users. Trend names are '
                  'fixed; only conditions, order, enable, and named values '
                  'can be changed. Applied on the next trend refresh.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                RecommendationRulesEditor(
                  key: _trendRulesKey,
                  initial: _trendRules!,
                  lockRecommendationText: true,
                  fixedRules: true,
                  hideOnMatch: true,
                  labelColumnTitle: 'Trend',
                  rulesHeading: 'Trend rules',
                  rulesHint:
                      'Evaluated top to bottom. First matching rule assigns the trend.',
                  fieldHelpText: RecommendationRulesEditor.trendFieldHelpText,
                  builtinFields: RecommendationRulesEditor.trendBuiltinFields,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _savingTrend ? null : _saveTrend,
                    child: const Text('Save trend rules'),
                  ),
                ),
              ],
            ),
    );
  }
}
