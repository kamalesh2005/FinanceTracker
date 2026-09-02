import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stock.dart';
import '../providers/auth_provider.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_format.dart';

class StockThresholdReview {
  static String formatDate(DateTime? date) {
    if (date == null) return '-';
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String action = 'Clear',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static Future<bool> clearFields({
    required BuildContext context,
    required Stock stock,
    required List<String> fields,
    bool showSnackBar = true,
  }) async {
    final isBsh = fields.any(
      (f) =>
          f == 'last_buy' || f == 'last_sale' || f == 'last_hold' || f == 'all',
    );
    final all = fields.contains('all');
    final title = all
        ? 'Clear ${stock.symbol}'
        : isBsh
            ? 'Clear Buy/Sell/Hold'
            : 'Clear value';
    final message = all
        ? 'Clear all Buy/Sell/Hold prices and thresholds for ${stock.symbol}'
            '${stock.source.isNotEmpty ? ' (${stock.source})' : ''}?'
        : isBsh
            ? 'Clearing a Buy, Sell, or Hold price ignores all three last-action '
                'prices for signals until you take a new Buy/Sell/Hold. '
                'Last Actioned on the Stocks screen is unchanged.'
            : 'Remove this threshold for ${stock.symbol}?';
    if (!await confirm(context: context, title: title, message: message)) {
      return false;
    }

    final ok = await context.read<FinanceProvider>().clearStockReviewValues(
          stockId: stock.id,
          source: stock.source,
          fields: fields,
        );
    if (!context.mounted) return ok;
    if (showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Cleared' : 'Failed to clear')),
      );
    }
    return ok;
  }

  static Widget valueCell({
    required String priceLabel,
    String? dateLabel,
    VoidCallback? onClear,
    bool busy = false,
  }) {
    if (priceLabel == '-') {
      return const Text('-');
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              priceLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (dateLabel != null)
              Text(
                dateLabel,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
          ],
        ),
        if (onClear != null)
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Clear',
            visualDensity: VisualDensity.compact,
            onPressed: busy ? null : onClear,
          ),
      ],
    );
  }

  static Widget bshCell({
    required bool active,
    required double price,
    required DateTime? date,
    VoidCallback? onClear,
    bool busy = false,
  }) {
    if (!active) return const Text('-');
    return valueCell(
      priceLabel: formatInr(price),
      dateLabel: formatDate(date),
      busy: busy,
      onClear: onClear,
    );
  }

  static Widget thresholdCell({
    required double price,
    VoidCallback? onClear,
    bool busy = false,
  }) {
    if (price <= 0) return const Text('-');
    return valueCell(
      priceLabel: formatInr(price),
      busy: busy,
      onClear: onClear,
    );
  }

  static Future<void> showForStock(BuildContext context, Stock stock) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _StockThresholdReviewDialog(initial: stock),
    );
  }
}

class _StockThresholdReviewDialog extends StatelessWidget {
  final Stock initial;

  const _StockThresholdReviewDialog({required this.initial});

  Stock _resolved(FinanceProvider provider) {
    for (final s in provider.stocks) {
      if (s.id == initial.id && s.source == initial.source) return s;
    }
    return initial;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<FinanceProvider, AuthProvider>(
      builder: (context, provider, auth, _) {
        final stock = _resolved(provider);
        final days =
            auth.effectiveRecommendationRules.lastTradeRuleValidityDays;
        final busy = provider.isLoading;
        final sourceLabel =
            stock.source.trim().isEmpty ? '-' : stock.source.trim();

        Widget labeled(String label, Widget child) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          );
        }

        return AlertDialog(
          title: Text('Thresholds — ${stock.symbol}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labeled('Account', Text(sourceLabel)),
                  labeled(
                    'LTP',
                    Text(
                      stock.currentPrice > 0
                          ? formatInr(stock.currentPrice)
                          : '-',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Divider(height: 20),
                  labeled(
                    'Buy',
                    StockThresholdReview.bshCell(
                      active: stock.lastBuyActiveForReview(days),
                      price: stock.lastBuyPrice,
                      date: stock.lastBuyDate,
                      busy: busy,
                      onClear: () => StockThresholdReview.clearFields(
                        context: context,
                        stock: stock,
                        fields: const ['last_buy'],
                      ),
                    ),
                  ),
                  labeled(
                    'Sell',
                    StockThresholdReview.bshCell(
                      active: stock.lastSaleActiveForReview(days),
                      price: stock.lastSalePrice,
                      date: stock.lastSaleDate,
                      busy: busy,
                      onClear: () => StockThresholdReview.clearFields(
                        context: context,
                        stock: stock,
                        fields: const ['last_sale'],
                      ),
                    ),
                  ),
                  labeled(
                    'Hold',
                    StockThresholdReview.bshCell(
                      active: stock.lastHoldActiveForReview(days),
                      price: stock.lastHoldPrice,
                      date: stock.lastHoldDate,
                      busy: busy,
                      onClear: () => StockThresholdReview.clearFields(
                        context: context,
                        stock: stock,
                        fields: const ['last_hold'],
                      ),
                    ),
                  ),
                  labeled(
                    'Buy Thresh.',
                    StockThresholdReview.thresholdCell(
                      price: stock.setBuyPrice,
                      busy: busy,
                      onClear: () => StockThresholdReview.clearFields(
                        context: context,
                        stock: stock,
                        fields: const ['set_buy_price'],
                      ),
                    ),
                  ),
                  labeled(
                    'Book Profit',
                    StockThresholdReview.thresholdCell(
                      price: stock.setProfitBookingPrice,
                      busy: busy,
                      onClear: () => StockThresholdReview.clearFields(
                        context: context,
                        stock: stock,
                        fields: const ['set_profit_booking_price'],
                      ),
                    ),
                  ),
                  labeled(
                    'Stop Loss',
                    StockThresholdReview.thresholdCell(
                      price: stock.setStopLossPrice,
                      busy: busy,
                      onClear: () => StockThresholdReview.clearFields(
                        context: context,
                        stock: stock,
                        fields: const ['set_stop_loss_price'],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy || !stock.hasReviewableValues(days)
                  ? null
                  : () => StockThresholdReview.clearFields(
                        context: context,
                        stock: stock,
                        fields: const ['all'],
                      ),
              child: const Text('Clear all'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
