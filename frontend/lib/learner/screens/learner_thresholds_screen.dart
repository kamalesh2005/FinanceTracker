import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/stock.dart';
import '../../providers/auth_provider.dart';
import '../../utils/currency_format.dart';
import '../learner_api.dart';
import '../learner_provider.dart';
import '../learner_theme.dart';

class LearnerThresholdsScreen extends StatefulWidget {
  final int challengeId;
  final int? stockId;

  const LearnerThresholdsScreen({
    super.key,
    required this.challengeId,
    this.stockId,
  });

  @override
  State<LearnerThresholdsScreen> createState() => _LearnerThresholdsScreenState();
}

class _LearnerThresholdsScreenState extends State<LearnerThresholdsScreen> {
  Future<void> _edit(Stock s) async {
    final buy = TextEditingController(
      text: s.setBuyPrice > 0 ? s.setBuyPrice.toString() : '',
    );
    final profit = TextEditingController(
      text: s.setProfitBookingPrice > 0 ? s.setProfitBookingPrice.toString() : '',
    );
    final stop = TextEditingController(
      text: s.setStopLossPrice > 0 ? s.setStopLossPrice.toString() : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Thresholds · ${s.symbol}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: buy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Buy below'),
            ),
            TextField(
              controller: profit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Book profit above'),
            ),
            TextField(
              controller: stop,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Stop loss below'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    await LearnerApi.setThresholds(
      widget.challengeId,
      s.id,
      setBuyPrice: double.tryParse(buy.text.trim()) ?? 0,
      setProfitBookingPrice: double.tryParse(profit.text.trim()) ?? 0,
      setStopLossPrice: double.tryParse(stop.text.trim()) ?? 0,
    );
    if (!mounted) return;
    await context.read<LearnerProvider>().openChallenge(widget.challengeId);
  }

  Future<void> _clear(Stock s, List<String> fields) async {
    await LearnerApi.clearReviewValues(widget.challengeId, s.id, fields);
    if (!mounted) return;
    await context.read<LearnerProvider>().openChallenge(widget.challengeId);
  }

  @override
  Widget build(BuildContext context) {
    final validity = context.watch<AuthProvider>().effectiveRecommendationRules.lastTradeRuleValidityDays;
    final holdings = context.watch<LearnerProvider>().holdings.where((s) {
      if (widget.stockId != null) return s.id == widget.stockId;
      return s.hasReviewableValues(validity);
    }).toList();

    return wrapLearnerPage(Scaffold(
      appBar: AppBar(
        title: learnerBrandTitle(context, 'Challenge thresholds'),
        actions: learnerAppBarActions(
          context,
          extra: [
            IconButton(
              tooltip: 'Clear all',
              icon: const Icon(Icons.clear_all),
              onPressed: () async {
                await LearnerApi.clearAllReviewValues(widget.challengeId, ['all']);
                if (!context.mounted) return;
                await context.read<LearnerProvider>().openChallenge(widget.challengeId);
              },
            ),
          ],
        ),
      ),
      body: holdings.isEmpty
          ? const Center(child: Text('No reviewable thresholds.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: holdings.length,
              itemBuilder: (context, i) {
                final s = holdings[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.symbol, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('LTP ${formatInr(s.currentPrice)}'),
                        if (s.setBuyPrice > 0) Text('Buy below ${formatInr(s.setBuyPrice)}'),
                        if (s.setProfitBookingPrice > 0)
                          Text('Book profit ${formatInr(s.setProfitBookingPrice)}'),
                        if (s.setStopLossPrice > 0)
                          Text('Stop loss ${formatInr(s.setStopLossPrice)}'),
                        if (s.hasLastBuy)
                          Text('Last buy ${formatInr(s.lastBuyPrice)}'),
                        if (s.hasLastSale)
                          Text('Last sell ${formatInr(s.lastSalePrice)}'),
                        if (s.hasLastHold)
                          Text('Last hold ${formatInr(s.lastHoldPrice)}'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              style: learnerOutlinedActionStyle(context),
                              onPressed: () => _edit(s),
                              child: const Text('Edit'),
                            ),
                            OutlinedButton(
                              style: learnerOutlinedActionStyle(context),
                              onPressed: () => _clear(s, ['all']),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    ));
  }
}
