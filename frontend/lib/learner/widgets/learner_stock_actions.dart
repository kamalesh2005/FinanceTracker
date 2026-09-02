import 'package:flutter/material.dart';
import '../../models/stock.dart';
import '../../utils/currency_format.dart';
import '../learner_api.dart';
import '../learner_provider.dart';
import '../../utils/screen_tracker.dart';
import '../screens/learner_thresholds_screen.dart';
import '../screens/learner_trade_screen.dart';

class LearnerStockActions {
  static const maxNotesChars = 200;

  static Widget compactBar({
    required BuildContext context,
    required Stock stock,
    required int challengeId,
    required bool tradingOpen,
    required LearnerProvider provider,
  }) {
    const iconConstraints = BoxConstraints(minWidth: 24, minHeight: 24);
    final iconStyle = IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    ButtonStyle letterStyle(Color color) => TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: tradingOpen
              ? () => _openTrade(context, challengeId, stock.symbol, 'buy')
              : null,
          style: letterStyle(Colors.green.shade700),
          child: const Text('B', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: tradingOpen && stock.quantity > 0
              ? () => _openTrade(context, challengeId, stock.symbol, 'sell')
              : null,
          style: letterStyle(Colors.orange.shade800),
          child: const Text('S', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: tradingOpen && stock.currentPrice > 0
              ? () => showHoldDialog(context, stock, challengeId, provider)
              : null,
          style: letterStyle(Colors.indigo.shade700),
          child: const Text('H', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: () =>
              showThresholdsDialog(context, stock, challengeId, provider),
          style: letterStyle(Colors.teal.shade800),
          child: const Text('T', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        IconButton(
          icon: const Icon(Icons.visibility_outlined, size: 18),
          onPressed: () {
            Navigator.push(
              context,
              appPageRoute(
                LearnerThresholdsScreen(
                  challengeId: challengeId,
                  stockId: stock.id,
                ),
              ),
            );
          },
          tooltip: 'View thresholds',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: iconConstraints,
          style: iconStyle,
        ),
      ],
    );
  }

  static Widget cardBar({
    required BuildContext context,
    required Stock stock,
    required int challengeId,
    required bool tradingOpen,
    required LearnerProvider provider,
  }) {
    ButtonStyle letterStyle(Color color) => TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          minimumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        );
    final iconStyle = IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: tradingOpen
              ? () => _openTrade(context, challengeId, stock.symbol, 'buy')
              : null,
          style: letterStyle(Colors.green.shade700),
          child: const Text('B'),
        ),
        TextButton(
          onPressed: tradingOpen && stock.quantity > 0
              ? () => _openTrade(context, challengeId, stock.symbol, 'sell')
              : null,
          style: letterStyle(Colors.orange.shade800),
          child: const Text('S'),
        ),
        TextButton(
          onPressed: tradingOpen && stock.currentPrice > 0
              ? () => showHoldDialog(context, stock, challengeId, provider)
              : null,
          style: letterStyle(Colors.indigo.shade700),
          child: const Text('H'),
        ),
        TextButton(
          onPressed: () =>
              showThresholdsDialog(context, stock, challengeId, provider),
          style: letterStyle(Colors.teal.shade800),
          child: const Text('T'),
        ),
        IconButton(
          icon: const Icon(Icons.visibility_outlined, size: 18),
          onPressed: () {
            Navigator.push(
              context,
              appPageRoute(
                LearnerThresholdsScreen(
                  challengeId: challengeId,
                  stockId: stock.id,
                ),
              ),
            );
          },
          tooltip: 'View thresholds',
          style: iconStyle,
        ),
      ],
    );
  }

  static Future<void> _openTrade(
    BuildContext context,
    int challengeId,
    String symbol,
    String side,
  ) async {
    await Navigator.push(
      context,
      appPageRoute(
        LearnerTradeScreen(
          challengeId: challengeId,
          initialSymbol: symbol,
          initialSide: side,
        ),
      ),
    );
  }

  static Future<void> showThresholdsDialog(
    BuildContext context,
    Stock stock,
    int challengeId,
    LearnerProvider provider,
  ) async {
    final buyController = TextEditingController(
      text: stock.setBuyPrice > 0 ? stock.setBuyPrice.toStringAsFixed(2) : '',
    );
    final profitController = TextEditingController(
      text: stock.setProfitBookingPrice > 0
          ? stock.setProfitBookingPrice.toStringAsFixed(2)
          : '',
    );
    final stopController = TextEditingController(
      text: stock.setStopLossPrice > 0
          ? stock.setStopLossPrice.toStringAsFixed(2)
          : '',
    );

    double? parseOptional(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return 0;
      return double.tryParse(t);
    }

    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Set thresholds — ${stock.symbol}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current price: ${formatInr(stock.currentPrice)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'These values will be cleared on Buy/Sell/Hold action on this stock',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: buyController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Buy (Reduce Avg By Price, Below)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: profitController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Book Profit (Sell Above)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stopController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Sell (Stop Loss Below)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final buy = parseOptional(buyController.text);
                final profit = parseOptional(profitController.text);
                final stop = parseOptional(stopController.text);
                if (buy == null || profit == null || stop == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Enter valid numbers or leave blank'),
                    ),
                  );
                  return;
                }
                if (buy < 0 || profit < 0 || stop < 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Prices cannot be negative')),
                  );
                  return;
                }
                Navigator.pop(ctx, {
                  'buy': buy,
                  'profit': profit,
                  'stop': stop,
                });
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      buyController.dispose();
      profitController.dispose();
      stopController.dispose();
    });

    if (result == null || !context.mounted) return;

    try {
      await LearnerApi.setThresholds(
        challengeId,
        stock.id,
        setBuyPrice: result['buy']!,
        setProfitBookingPrice: result['profit']!,
        setStopLossPrice: result['stop']!,
      );
      if (!context.mounted) return;
      await provider.openChallenge(challengeId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thresholds saved')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  static Future<void> showHoldDialog(
    BuildContext context,
    Stock stock,
    int challengeId,
    LearnerProvider provider,
  ) async {
    final price = stock.currentPrice;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hold ${stock.symbol}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mark this stock as Hold and use the current price as the baseline for % fluctuation in signal logic?',
            ),
            const SizedBox(height: 12),
            Text(
              'Current price: ${formatInr(price)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
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
    if (confirmed != true || !context.mounted) return;

    try {
      await LearnerApi.hold(challengeId, stock.id);
      if (!context.mounted) return;
      await provider.openChallenge(challengeId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hold recorded')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  static Widget notesCell({
    required BuildContext context,
    required Stock stock,
    required int challengeId,
    required LearnerProvider provider,
  }) {
    final note = stock.notes.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: note.isEmpty
              ? Text(
                  '-',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                )
              : Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, height: 1.2),
                ),
        ),
        IconButton(
          icon: const Icon(Icons.edit_note, size: 18),
          tooltip: note.isEmpty ? 'Add note' : 'Edit note',
          onPressed: () =>
              showNotesDialog(context, stock, challengeId, provider),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        if (note.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Delete note',
            onPressed: () => deleteNote(context, stock, challengeId, provider),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }

  static Future<void> showNotesDialog(
    BuildContext context,
    Stock stock,
    int challengeId,
    LearnerProvider provider,
  ) async {
    final controller = TextEditingController(text: stock.notes);
    try {
      final saved = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(
              stock.notes.trim().isEmpty
                  ? 'Add note — ${stock.symbol}'
                  : 'Edit note — ${stock.symbol}',
            ),
            content: SizedBox(
              width: 420,
              child: TextField(
                controller: controller,
                maxLength: maxNotesChars,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Up to 200 characters',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      if (saved == null || !context.mounted) return;
      await LearnerApi.setNotes(challengeId, stock.id, saved.trim());
      if (!context.mounted) return;
      await provider.openChallenge(challengeId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      controller.dispose();
    }
  }

  static Future<void> deleteNote(
    BuildContext context,
    Stock stock,
    int challengeId,
    LearnerProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Delete note — ${stock.symbol}'),
          content: const Text('Remove the note for this stock?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await LearnerApi.setNotes(challengeId, stock.id, '');
      if (!context.mounted) return;
      await provider.openChallenge(challengeId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}
