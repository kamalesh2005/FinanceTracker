import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/currency_format.dart';
import '../widgets/auth_app_bar_actions.dart';

class StockChartScreen extends StatefulWidget {
  final String symbol;
  final String? name;

  const StockChartScreen({
    super.key,
    required this.symbol,
    this.name,
  });

  @override
  State<StockChartScreen> createState() => _StockChartScreenState();
}

class _StockChartScreenState extends State<StockChartScreen> {
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        ApiService.getStockHistory(widget.symbol),
        ApiService.getStockTransactions(widget.symbol),
      ]);
      setState(() {
        _history = results[0];
        _transactions = results[1];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.symbol),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.name != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            widget.name!,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (_history.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(child: Text('No historical data available')),
                        )
                      else
                        _buildChart(),
                      const SizedBox(height: 24),
                      _buildTransactionsTable(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildChart() {
    final prices = _history.map((e) => (e['price'] as num).toDouble()).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;

    return Column(
      children: [
        Container(
          height: 400,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
              ),
            ],
          ),
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: priceRange / 5,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey.withOpacity(0.2),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: (_history.length / 6).ceil().toDouble(),
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < _history.length) {
                        final dateStr = _history[index]['date'] as String;
                        final date = DateTime.parse(dateStr);
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            DateFormat('MMM d').format(date),
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 60,
                    interval: priceRange / 5,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        formatInr(value),
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: List.generate(
                    _history.length,
                    (index) => FlSpot(
                      index.toDouble(),
                      (_history[index]['price'] as num).toDouble(),
                    ),
                  ),
                  isCurved: true,
                  color: Theme.of(context).colorScheme.primary,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  ),
                ),
              ],
              minX: 0,
              maxX: (_history.length - 1).toDouble(),
              minY: minPrice - (priceRange * 0.1),
              maxY: maxPrice + (priceRange * 0.1),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Current: ${formatInr(prices.last)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Range: ${formatInr(minPrice)} - ${formatInr(maxPrice)}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ],
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
                DataColumn(label: Text('Remaining'), numeric: true),
                DataColumn(label: Text('Source')),
              ],
              rows: _transactions.map((tx) {
                final type = (tx['type'] as String? ?? '').toLowerCase();
                final isBuy = type == 'buy';
                final dateStr = tx['transaction_date'] as String?;
                final date = dateStr != null ? DateTime.parse(dateStr).toLocal() : null;
                final remaining = (tx['quantity'] as num?)?.toDouble() ?? 0;
                final originalQty = (tx['original_quantity'] as num?)?.toDouble() ?? remaining;
                final price = (tx['price'] as num?)?.toDouble() ?? 0;
                final source = tx['source'] as String? ?? '';
                final qtyDisplay = isBuy ? originalQty : remaining;

                return DataRow(
                  cells: [
                    DataCell(Text(
                      date != null ? DateFormat('dd MMM yyyy').format(date) : '-',
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
                    DataCell(Text(qtyDisplay.toStringAsFixed(
                      qtyDisplay == qtyDisplay.roundToDouble() ? 0 : 2,
                    ))),
                    DataCell(Text(formatInr(price))),
                    DataCell(Text(
                      isBuy
                          ? remaining.toStringAsFixed(
                              remaining == remaining.roundToDouble() ? 0 : 2,
                            )
                          : '-',
                    )),
                    DataCell(Text(source.isNotEmpty ? source : '-')),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
