import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/stock.dart';
import '../../services/api_service.dart';
import '../../utils/currency_format.dart';
import '../learner_api.dart';
import '../learner_provider.dart';
import '../learner_theme.dart';
import '../widgets/learner_one_year_chart.dart';
import '../widgets/learner_stock_holding_panel.dart';

class LearnerHoldingDetailScreen extends StatefulWidget {
  final int challengeId;
  final String symbol;
  final int stockId;

  const LearnerHoldingDetailScreen({
    super.key,
    required this.challengeId,
    required this.symbol,
    required this.stockId,
  });

  @override
  State<LearnerHoldingDetailScreen> createState() =>
      _LearnerHoldingDetailScreenState();
}

class _LearnerHoldingDetailScreenState extends State<LearnerHoldingDetailScreen> {
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    List<Map<String, dynamic>> history = [];
    List<Map<String, dynamic>> transactions = [];
    String? error;

    try {
      history = await ApiService.getStockHistory(widget.symbol);
    } catch (e) {
      error = e.toString();
    }
    try {
      transactions =
          await LearnerApi.transactions(widget.challengeId, symbol: widget.symbol);
    } catch (e) {
      error ??= e.toString();
    }

    if (!mounted) return;
    setState(() {
      _history = history;
      _transactions = transactions;
      _error = history.isEmpty ? error : null;
      _loading = false;
    });
  }

  Stock? _holding(LearnerProvider provider) {
    for (final s in provider.holdings) {
      if (s.id == widget.stockId) return s;
    }
    return null;
  }

  Widget _buildChartSection(Stock? holding, {required bool compact}) {
    return LearnerOneYearChart(
      history: _history,
      holding: holding,
      trend: holding != null
          ? context.read<LearnerProvider>().trendFor(holding.id)
          : null,
      error: _error,
      onRetry: _loadData,
      compact: compact,
    );
  }

  Widget _buildTransactionsTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Transactions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No transactions found')),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Qty'), numeric: true),
                DataColumn(label: Text('Price'), numeric: true),
                DataColumn(label: Text('Fee'), numeric: true),
              ],
              rows: _transactions.map((tx) {
                final type = (tx['type']?.toString() ?? '').toLowerCase();
                final isBuy = type == 'buy';
                final dateStr = tx['transaction_date']?.toString();
                final date =
                    dateStr != null ? DateTime.tryParse(dateStr)?.toLocal() : null;
                final qty = (tx['original_quantity'] as num?)?.toDouble() ??
                    (tx['quantity'] as num?)?.toDouble() ??
                    0;
                final price = (tx['price'] as num?)?.toDouble() ?? 0;
                final fee = (tx['fee'] as num?)?.toDouble() ?? 0;
                return DataRow(
                  cells: [
                    DataCell(Text(
                      date != null
                          ? DateFormat('dd MMM yyyy').format(date)
                          : '-',
                    )),
                    DataCell(
                      Text(
                        isBuy ? 'Buy' : 'Sell',
                        style: TextStyle(
                          color: isBuy ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataCell(Text(
                      qty == qty.roundToDouble()
                          ? qty.toStringAsFixed(0)
                          : qty.toStringAsFixed(2),
                    )),
                    DataCell(Text(formatInr(price))),
                    DataCell(Text(fee > 0 ? formatInr(fee) : '-')),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tradingOpen =
        context.watch<LearnerProvider>().detail?.tradingOpen ?? false;

    return wrapLearnerPage(
      Scaffold(
        appBar: AppBar(
          title: learnerBrandTitle(context, widget.symbol),
          actions: learnerAppBarActions(context),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 700;
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(compact ? 8.0 : 16.0),
                      child: Consumer<LearnerProvider>(
                        builder: (context, provider, _) {
                          final holding = _holding(provider);
                          final trend = provider.trendFor(widget.stockId);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (holding != null)
                                LearnerStockHoldingPanel(
                                  stock: holding,
                                  challengeId: widget.challengeId,
                                  tradingOpen: tradingOpen,
                                  trend: trend,
                                  afterSignal: _buildChartSection(
                                    holding,
                                    compact: compact,
                                  ),
                                )
                              else ...[
                                Text(
                                  widget.symbol,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _buildChartSection(null, compact: compact),
                              ],
                              const SizedBox(height: 24),
                              _buildTransactionsTable(),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
