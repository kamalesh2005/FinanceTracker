import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

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
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final history = await ApiService.getStockHistory(widget.symbol);
      setState(() {
        _history = history;
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
                        onPressed: _loadHistory,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _history.isEmpty
                  ? const Center(child: Text('No historical data available'))
                  : _buildChart(),
    );
  }

  Widget _buildChart() {
    if (_history.isEmpty) return const SizedBox();

    final prices = _history.map((e) => (e['price'] as num).toDouble()).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (widget.name != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                widget.name!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
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
                          '₹${value.toStringAsFixed(0)}',
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
                'Current: ₹${prices.last.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                'Range: ₹${minPrice.toStringAsFixed(2)} - ₹${maxPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
