import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stock.dart';
import '../providers/finance_provider.dart';
import '../utils/screen_tracker.dart';
import '../screens/edit_stock_screen.dart';
import '../utils/currency_format.dart';
import 'stock_threshold_review.dart';

class StockActions {
  static const manualAddSource = 'Manual Add';
  static const maxNotesChars = 200;

  static bool isManualAdd(Stock stock) =>
      stock.source.isEmpty || stock.source == manualAddSource;

  static String sourceLabel(Stock stock) =>
      stock.source.trim().isEmpty ? manualAddSource : stock.source.trim();

  static Widget compactBar({
    required BuildContext context,
    required Stock stock,
    required FinanceProvider provider,
    VoidCallback? onDeleted,
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
          onPressed: () =>
              showBuySellDialog(context, stock, provider, isBuy: true),
          style: letterStyle(Colors.green.shade700),
          child: const Text('B', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: stock.quantity > 0
              ? () => showBuySellDialog(context, stock, provider, isBuy: false)
              : null,
          style: letterStyle(Colors.orange.shade800),
          child: const Text('S', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: stock.currentPrice > 0
              ? () => showHoldDialog(context, stock, provider)
              : null,
          style: letterStyle(Colors.indigo.shade700),
          child: const Text('H', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: () => showThresholdsDialog(context, stock, provider),
          style: letterStyle(Colors.teal.shade800),
          child: const Text('T', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        IconButton(
          icon: const Icon(Icons.visibility_outlined, size: 18),
          onPressed: () => StockThresholdReview.showForStock(context, stock),
          tooltip: 'View thresholds',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: iconConstraints,
          style: iconStyle,
        ),
        if (isManualAdd(stock))
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => openEditStock(context, stock),
            tooltip: 'Edit',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: iconConstraints,
            style: iconStyle,
          ),
        IconButton(
          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
          onPressed: () =>
              showDeleteDialog(context, stock, provider, onDeleted: onDeleted),
          tooltip: 'Delete',
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
    required FinanceProvider provider,
    VoidCallback? onDeleted,
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
          onPressed: () =>
              showBuySellDialog(context, stock, provider, isBuy: true),
          style: letterStyle(Colors.green.shade700),
          child: const Text('B'),
        ),
        TextButton(
          onPressed: stock.quantity > 0
              ? () => showBuySellDialog(context, stock, provider, isBuy: false)
              : null,
          style: letterStyle(Colors.orange.shade800),
          child: const Text('S'),
        ),
        TextButton(
          onPressed: stock.currentPrice > 0
              ? () => showHoldDialog(context, stock, provider)
              : null,
          style: letterStyle(Colors.indigo.shade700),
          child: const Text('H'),
        ),
        TextButton(
          onPressed: () => showThresholdsDialog(context, stock, provider),
          style: letterStyle(Colors.teal.shade800),
          child: const Text('T'),
        ),
        IconButton(
          icon: const Icon(Icons.visibility_outlined, size: 18),
          onPressed: () => StockThresholdReview.showForStock(context, stock),
          tooltip: 'View thresholds',
          style: iconStyle,
        ),
        if (isManualAdd(stock))
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => openEditStock(context, stock),
            style: iconStyle,
          ),
        IconButton(
          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
          onPressed: () =>
              showDeleteDialog(context, stock, provider, onDeleted: onDeleted),
          style: iconStyle,
        ),
      ],
    );
  }

  static Future<void> openEditStock(BuildContext context, Stock stock) async {
    await Navigator.push(
      context,
      appPageRoute(EditStockScreen(stock: stock)),
    );
    if (!context.mounted) return;
    await context.read<FinanceProvider>().loadStocks();
  }

  static Future<void> showThresholdsDialog(
    BuildContext context,
    Stock stock,
    FinanceProvider provider,
  ) async {
    final src = sourceLabel(stock);
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
          title: Text('Set thresholds — ${stock.displaySymbol}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Account: $src',
                    style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 8),
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
                        content: Text('Enter valid numbers or leave blank')),
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

    final ok = await provider.setStockThresholds(
      stockId: stock.id,
      source: src,
      setBuyPrice: result['buy']!,
      setProfitBookingPrice: result['profit']!,
      setStopLossPrice: result['stop']!,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Thresholds saved'
              : (provider.error ?? 'Failed to save thresholds'),
        ),
      ),
    );
  }

  static Future<void> showHoldDialog(
    BuildContext context,
    Stock stock,
    FinanceProvider provider,
  ) async {
    final price = stock.currentPrice;
    final src = sourceLabel(stock);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hold ${stock.displaySymbol}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account: $src',
                style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
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

    final ok = await provider.holdStock(
      stockId: stock.id,
      price: price,
      source: src,
      heldAt: DateTime.now(),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Hold recorded' : (provider.error ?? 'Hold failed')),
      ),
    );
  }

  static Future<void> showBuySellDialog(
    BuildContext context,
    Stock stock,
    FinanceProvider provider, {
    required bool isBuy,
  }) async {
    final formKey = GlobalKey<FormState>();
    final qtyController = TextEditingController();
    final priceController = TextEditingController(
      text: stock.currentPrice > 0
          ? stock.currentPrice.toStringAsFixed(2)
          : (stock.buyPrice > 0 ? stock.buyPrice.toStringAsFixed(2) : ''),
    );
    DateTime txDate = DateTime.now();
    final src = sourceLabel(stock);
    final maxSellQty = stock.quantity;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title:
                  Text(isBuy ? 'Buy ${stock.displaySymbol}' : 'Sell ${stock.displaySymbol}'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Account: $src',
                          style: TextStyle(color: Colors.grey.shade700)),
                      if (!isBuy) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Available: ${maxSellQty.toStringAsFixed(maxSellQty == maxSellQty.roundToDouble() ? 0 : 2)}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final q = double.tryParse(value?.trim() ?? '');
                          if (q == null || q <= 0) {
                            return 'Enter a quantity greater than 0';
                          }
                          if (!isBuy && q > maxSellQty + 1e-9) {
                            return 'Cannot exceed available quantity ($maxSellQty)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final p = double.tryParse(value?.trim() ?? '');
                          if (p == null || p <= 0) {
                            return 'Enter a price greater than 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Transaction date'),
                        subtitle: Text(
                          '${txDate.year.toString().padLeft(4, '0')}-'
                          '${txDate.month.toString().padLeft(2, '0')}-'
                          '${txDate.day.toString().padLeft(2, '0')}',
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: txDate,
                            firstDate: DateTime(1990),
                            lastDate:
                                DateTime.now().add(const Duration(days: 1)),
                          );
                          if (picked != null) {
                            setDialogState(() => txDate = picked);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    Navigator.pop(ctx, {
                      'quantity': double.parse(qtyController.text.trim()),
                      'price': double.parse(priceController.text.trim()),
                      'date': txDate,
                    });
                  },
                  child: Text(isBuy ? 'Buy' : 'Sell'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      qtyController.dispose();
      priceController.dispose();
    });

    if (result == null || !context.mounted) return;

    final qty = result['quantity'] as double;
    final price = result['price'] as double;
    final date = result['date'] as DateTime;

    final ok = isBuy
        ? await provider.buyStockTransaction(
            symbol: stock.symbol,
            quantity: qty,
            price: price,
            transactionDate: date,
            source: src,
            name: stock.name,
          )
        : await provider.sellStockTransaction(
            symbol: stock.symbol,
            quantity: qty,
            price: price,
            transactionDate: date,
            source: src,
          );

    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isBuy ? 'Buy recorded' : 'Sell recorded'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Transaction failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  static void showDeleteDialog(
    BuildContext context,
    Stock stock,
    FinanceProvider provider, {
    VoidCallback? onDeleted,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Stock'),
        content: Text(
          'Remove ${stock.displaySymbol} from your holdings'
          '${stock.source.isNotEmpty ? ' (${stock.source})' : ''}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final ok = await provider.deleteStock(stock.id,
                  source: sourceLabel(stock));
              if (!context.mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(provider.error ?? 'Failed to delete stock'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              onDeleted?.call();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  static Widget notesCell({
    required BuildContext context,
    required Stock stock,
    required FinanceProvider provider,
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
          onPressed: () => showNotesDialog(context, stock, provider),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        if (note.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Delete note',
            onPressed: () => deleteNote(context, stock, provider),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }

  static Future<void> showNotesDialog(
    BuildContext context,
    Stock stock,
    FinanceProvider provider,
  ) async {
    final controller = TextEditingController(text: stock.notes);
    try {
      final saved = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(
              stock.notes.trim().isEmpty
                  ? 'Add note — ${stock.displaySymbol}'
                  : 'Edit note — ${stock.displaySymbol}',
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
      final ok = await provider.setStockNotes(
        stockId: stock.id,
        source: stock.source,
        notes: saved.trim(),
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.error ?? 'Failed to save note')),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  static Future<void> deleteNote(
    BuildContext context,
    Stock stock,
    FinanceProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Delete note — ${stock.displaySymbol}'),
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
    final ok = await provider.setStockNotes(
      stockId: stock.id,
      source: stock.source,
      notes: '',
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.error ?? 'Failed to delete note')),
      );
    }
  }
}
