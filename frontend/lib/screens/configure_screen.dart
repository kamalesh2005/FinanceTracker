import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/finance_provider.dart';
import '../services/recommendation_engine.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import '../widgets/recommendation_rules_editor.dart';

class ConfigureScreen extends StatefulWidget {
  const ConfigureScreen({super.key});

  @override
  State<ConfigureScreen> createState() => _ConfigureScreenState();
}

class _ConfigureScreenState extends State<ConfigureScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _useAsStockWatchList = false;
  bool _showZeroQuantityStocks = false;
  bool _stockReviewEmailEnabled = true;
  final _rulesKey = GlobalKey<RecommendationRulesEditorState>();
  RecommendationRuleset? _rulesInitial;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    await auth.loadPreferences();
    if (!mounted) return;
    setState(() {
      _useAsStockWatchList = auth.useAsStockWatchList;
      _showZeroQuantityStocks = auth.showZeroQuantityStocks;
      _stockReviewEmailEnabled = auth.stockReviewEmailEnabled;
      _rulesInitial = auth.effectiveRecommendationRules;
      _loading = false;
    });
  }

  Future<void> _onWatchListChanged(bool? value) async {
    if (value == null || _saving) return;
    if (value && !_useAsStockWatchList) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable Stock Watch List?'),
          content: const Text(
            'This will set quantity of all your stocks to 1. '
            'Portfolio value will not be calculated and Dashboard will show '
            'Number of Stocks instead. This cannot restore previous quantities.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final finance = context.read<FinanceProvider>();
    setState(() => _saving = true);
    try {
      await auth.savePreferences(useAsStockWatchList: value);
      if (!mounted) return;
      setState(() => _useAsStockWatchList = value);
      await finance.loadPortfolioSummary();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Watch list mode enabled. Quantities set to 1.'
                : 'Watch list mode disabled.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onShowZeroQuantityChanged(bool? value) async {
    if (value == null || _saving) return;
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      await auth.savePreferences(showZeroQuantityStocks: value);
      if (!mounted) return;
      setState(() => _showZeroQuantityStocks = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Stocks with zero quantity are now visible.'
                : 'Stocks with zero quantity are now hidden.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onStockReviewEmailChanged(bool? value) async {
    if (value == null || _saving) return;
    final auth = context.read<AuthProvider>();
    if (!auth.stockReviewEmailAvailable) return;
    setState(() => _saving = true);
    try {
      await auth.savePreferences(stockReviewEmailEnabled: value);
      if (!mounted) return;
      setState(() => _stockReviewEmailEnabled = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Weekday review emails enabled.'
                : 'Weekday review emails disabled.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveRules() async {
    final errors = <String>[];
    final rs = _rulesKey.currentState?.buildRuleset(errors: errors);
    if (rs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errors.isEmpty ? 'Invalid rules' : errors.first),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().savePreferences(
            recommendationRules: rs,
          );
      if (!mounted) return;
      setState(() => _rulesInitial = rs);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signal rules saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetRules() async {
    setState(() => _saving = true);
    try {
      final auth = context.read<AuthProvider>();
      await auth.savePreferences(clearRecommendationRules: true);
      if (!mounted) return;
      setState(() {
        _rulesInitial = auth.effectiveRecommendationRules;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset to admin default rules')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Configure'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: _loading || _rulesInitial == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Preferences',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _useAsStockWatchList,
                  onChanged: _saving ? null : _onWatchListChanged,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Use the application as Stock Watch List'),
                  subtitle: const Text(
                    'This will save Qty for all stocks as 1. Portfolio value '
                    'will not be calculated and Dashboard will show Number of '
                    'Stocks instead.',
                  ),
                ),
                CheckboxListTile(
                  value: _showZeroQuantityStocks,
                  onChanged: _saving ? null : _onShowZeroQuantityChanged,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Show stocks with zero quantity'),
                  subtitle: const Text(
                    'Include fully sold holdings on the Stocks screen. Off by '
                    'default.',
                  ),
                ),
                CheckboxListTile(
                  value: _stockReviewEmailEnabled,
                  onChanged: _saving ||
                          !context.watch<AuthProvider>().stockReviewEmailAvailable
                      ? null
                      : _onStockReviewEmailChanged,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Email stocks to review'),
                  subtitle: Text(
                    context.watch<AuthProvider>().stockReviewEmailAvailable
                        ? 'Receive a weekday email at 12:30 PM IST with holdings '
                            'that have Buy, Sell, or Book Profit signals.'
                        : 'Add an email in Profile to enable review emails.',
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Signal Rules',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Define when each signal applies. Formulas use field '
                  'names like curr_price and avg_buy_price.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                RecommendationRulesEditor(
                  key: _rulesKey,
                  initial: _rulesInitial!,
                  lockRecommendationText:
                      !context.watch<AuthProvider>().isAdmin,
                  allowAddRule: context.watch<AuthProvider>().isAdmin,
                  rulesHeading: 'Signal rules',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _saving ? null : _saveRules,
                      child: const Text('Save rules'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _saving ? null : _resetRules,
                      child: const Text('Reset rules to admin defaults'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
