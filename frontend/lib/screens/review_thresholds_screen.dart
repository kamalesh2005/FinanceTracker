import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stock.dart';
import '../providers/auth_provider.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import '../widgets/stock_threshold_review.dart';

class ReviewThresholdsScreen extends StatefulWidget {
  const ReviewThresholdsScreen({super.key});

  @override
  State<ReviewThresholdsScreen> createState() => _ReviewThresholdsScreenState();
}

class _ReviewThresholdsScreenState extends State<ReviewThresholdsScreen> {
  bool _busy = false;
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AuthProvider>().loadPreferences();
      if (!mounted) return;
      await context.read<FinanceProvider>().loadStocks();
    });
  }

  double get _validityDays {
    return context
        .read<AuthProvider>()
        .effectiveRecommendationRules
        .lastTradeRuleValidityDays;
  }

  List<Stock> _rows(List<Stock> stocks) {
    final days = _validityDays;
    return stocks.where((s) => s.hasReviewableValues(days)).toList();
  }

  Future<void> _clearFields(Stock stock, List<String> fields) async {
    setState(() => _busy = true);
    await StockThresholdReview.clearFields(
      context: context,
      stock: stock,
      fields: fields,
    );
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _clearAllStocks() async {
    if (!await StockThresholdReview.confirm(
      context: context,
      title: 'Clear Thresholds for All',
      message: 'Clear Buy/Sell/Hold last-action prices (for signals) and all '
          'thresholds for every stock? Last Actioned on the Stocks screen '
          'is unchanged.',
    )) {
      return;
    }
    setState(() => _busy = true);
    final ok =
        await context.read<FinanceProvider>().clearAllStockReviewValues();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Cleared thresholds for all stocks'
              : 'Failed to clear thresholds for all stocks',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Review Thresholds'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            TextButton(
              onPressed: _busy ? null : _clearAllStocks,
              child: const Text('Clear Thresholds for All'),
            ),
          ],
        ),
      ),
      body: Consumer<FinanceProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.stocks.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.error != null && provider.stocks.isEmpty) {
            return Center(child: Text('Error: ${provider.error}'));
          }
          final rows = _rows(provider.stocks);
          if (rows.isEmpty) {
            return const Center(
              child:
                  Text('No valid Buy/Sell/Hold prices or thresholds to review'),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              return Scrollbar(
                controller: _hScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: DataTable(
                          headingRowHeight: 40,
                          dataRowMinHeight: 56,
                          dataRowMaxHeight: 72,
                          columns: const [
                            DataColumn(label: Text('Symbol')),
                            DataColumn(label: Text('Account')),
                            DataColumn(label: Text('LTP')),
                            DataColumn(label: Text('Buy')),
                            DataColumn(label: Text('Sell')),
                            DataColumn(label: Text('Hold')),
                            DataColumn(label: Text('Buy Thresh.')),
                            DataColumn(label: Text('Book Profit')),
                            DataColumn(label: Text('Stop Loss')),
                            DataColumn(label: Text('')),
                          ],
                          rows: rows.map(_buildDataRow).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  DataRow _buildDataRow(Stock stock) {
    final days = _validityDays;
    return DataRow(
      cells: [
        DataCell(Text(
          stock.symbol,
          style: const TextStyle(fontWeight: FontWeight.bold),
        )),
        DataCell(Text(stock.source.isNotEmpty ? stock.source : '-')),
        DataCell(Text(
          stock.currentPrice > 0 ? formatInr(stock.currentPrice) : '-',
        )),
        DataCell(StockThresholdReview.bshCell(
          active: stock.lastBuyActiveForReview(days),
          price: stock.lastBuyPrice,
          date: stock.lastBuyDate,
          busy: _busy,
          onClear: () => _clearFields(stock, const ['last_buy']),
        )),
        DataCell(StockThresholdReview.bshCell(
          active: stock.lastSaleActiveForReview(days),
          price: stock.lastSalePrice,
          date: stock.lastSaleDate,
          busy: _busy,
          onClear: () => _clearFields(stock, const ['last_sale']),
        )),
        DataCell(StockThresholdReview.bshCell(
          active: stock.lastHoldActiveForReview(days),
          price: stock.lastHoldPrice,
          date: stock.lastHoldDate,
          busy: _busy,
          onClear: () => _clearFields(stock, const ['last_hold']),
        )),
        DataCell(StockThresholdReview.thresholdCell(
          price: stock.setBuyPrice,
          busy: _busy,
          onClear: () => _clearFields(stock, const ['set_buy_price']),
        )),
        DataCell(StockThresholdReview.thresholdCell(
          price: stock.setProfitBookingPrice,
          busy: _busy,
          onClear: () =>
              _clearFields(stock, const ['set_profit_booking_price']),
        )),
        DataCell(StockThresholdReview.thresholdCell(
          price: stock.setStopLossPrice,
          busy: _busy,
          onClear: () => _clearFields(stock, const ['set_stop_loss_price']),
        )),
        DataCell(
          TextButton(
            onPressed: _busy ? null : () => _clearFields(stock, const ['all']),
            child: const Text('Clear all'),
          ),
        ),
      ],
    );
  }
}
