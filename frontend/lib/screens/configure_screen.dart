import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/finance_provider.dart';
import '../widgets/auth_app_bar_actions.dart';

class ConfigureScreen extends StatefulWidget {
  const ConfigureScreen({super.key});

  @override
  State<ConfigureScreen> createState() => _ConfigureScreenState();
}

class _ConfigureScreenState extends State<ConfigureScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _useAsStockWatchList = false;
  late TextEditingController _fluctuationController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fluctuationController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _fluctuationController.dispose();
    super.dispose();
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
      _fluctuationController.text =
          auth.effectiveRecommendationFluctuationPct.toStringAsFixed(
        auth.effectiveRecommendationFluctuationPct % 1 == 0 ? 0 : 2,
      );
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
      await auth.savePreferences(
        useAsStockWatchList: value,
      );
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

  Future<void> _saveFluctuation() async {
    final raw = _fluctuationController.text.trim();
    final pct = double.tryParse(raw);
    if (pct == null || pct <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a fluctuation % greater than 0')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().savePreferences(
            recommendationFluctuationPct: pct,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recommendation rule saved')),
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

  Future<void> _useAdminDefault() async {
    setState(() => _saving = true);
    try {
      final auth = context.read<AuthProvider>();
      await auth.savePreferences(clearRecommendationFluctuation: true);
      if (!mounted) return;
      setState(() {
        _fluctuationController.text =
            auth.effectiveRecommendationFluctuationPct.toStringAsFixed(
          auth.effectiveRecommendationFluctuationPct % 1 == 0 ? 0 : 2,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Using admin default (${auth.defaultRecommendationFluctuationPct}%)',
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: _loading
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
                const SizedBox(height: 28),
                const Text(
                  'Recommendation Rules',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '% change from last buy/sell price that should trigger new recommendation',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Since stock has been reviewed and buy/sell decision made, '
                  'new recommendation will be after stock moves beyond this range',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _fluctuationController,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: '%',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _saving ? null : _saveFluctuation,
                      child: const Text('Save'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saving ? null : _useAdminDefault,
                  child: Text(
                    'Use admin default (${auth.defaultRecommendationFluctuationPct}%)',
                  ),
                ),
              ],
            ),
    );
  }
}
