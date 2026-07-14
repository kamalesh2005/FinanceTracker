import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/finance_provider.dart';
import '../models/stock.dart';
import '../models/stock_trend.dart';
import 'add_stock_screen.dart';
import 'stock_chart_screen.dart';

class StocksScreen extends StatefulWidget {
  const StocksScreen({super.key});

  @override
  State<StocksScreen> createState() => _StocksScreenState();
}

class _StocksScreenState extends State<StocksScreen> {
  bool _isTableView = true;
  final Set<String> _selectedColumns = {
    'Symbol',
    'Qty',
    'Buy Price',
    'Current',
    'P/L',
    'P/L %',
    'Sector',
    'Recommendation',
    'Price Range',
    '6th High',
    '6th Low',
    'Trend',
    'Actions',
  };
  
  static const List<String> _allColumns = [
    'Symbol',
    'Qty',
    'Buy Price',
    'Current',
    'P/L',
    'P/L %',
    'Sector',
    'Recommendation',
    'Price Range',
    '6th High',
    '6th Low',
    'Trend',
    'Actions',
  ];

  @override
  void initState() {
    super.initState();
    _loadColumnPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<FinanceProvider>();
      await provider.loadStocks();
      provider.refreshStockPrices();
      provider.loadStockTrends();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stocks'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isTableView)
            IconButton(
              icon: const Icon(Icons.view_column),
              onPressed: _showColumnSelectionDialog,
              tooltip: 'Select columns',
            ),
          IconButton(
            icon: Icon(_isTableView ? Icons.view_module : Icons.table_rows),
            onPressed: () {
              setState(() {
                _isTableView = !_isTableView;
              });
            },
            tooltip: _isTableView ? 'Card view' : 'Table view',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddStockScreen()),
          ).then((_) => context.read<FinanceProvider>().loadStocks());
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Stock'),
      ),
      body: Consumer<FinanceProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(child: Text('Error: ${provider.error}'));
          }

          if (provider.stocks.isEmpty) {
            return const Center(child: Text('No stocks added yet'));
          }

          return RefreshIndicator(
            onRefresh: () => provider.refreshStockPrices(),
            child: _isTableView
                ? _buildStockTable(provider)
                : ListView.builder(
                    itemCount: provider.stocks.length,
                    itemBuilder: (context, index) {
                      final stock = provider.stocks[index];
                      return _buildStockCard(context, stock, provider);
                    },
                  ),
          );
        },
      ),
    );
  }

  String _getRecommendation(Stock stock, StockTrend? trend) {
    if (trend != null && trend.trend == 'bullish') {
      final priceThreshold = stock.buyPrice * 1.1;
      if (stock.currentPrice > priceThreshold) {
        return 'BUY';
      }
    }
    return 'NO ACTION REQD';
  }

  Widget _buildStockCard(BuildContext context, Stock stock, FinanceProvider provider) {
    final invested = stock.buyPrice * stock.quantity;
    final current = stock.currentPrice * stock.quantity;
    final profitLoss = current - invested;
    final profitLossPercentage = invested > 0 ? (profitLoss / invested) * 100 : 0.0;

    StockTrend? trend;
    try {
      trend = provider.stockTrends.firstWhere((t) => t.stockId == stock.id);
    } catch (_) {
      trend = null;
    }

    final recommendation = _getRecommendation(stock, trend);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StockChartScreen(
                            symbol: stock.symbol,
                            name: stock.name.isNotEmpty ? stock.name : null,
                          ),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stock.symbol,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        if (stock.name.isNotEmpty)
                          Text(
                            stock.name,
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    if (recommendation == 'BUY')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.5)),
                        ),
                        child: const Text(
                          'BUY',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withOpacity(0.5)),
                        ),
                        child: const Text(
                          'NO ACTION REQD',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (trend != null) _buildTrendBadge(trend.trend),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: null, // Disabled - transaction-based system doesn't support direct stock editing
                      color: Colors.grey,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                      onPressed: () {
                        _showDeleteDialog(context, stock.id, provider);
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoColumn('Quantity', stock.quantity.toStringAsFixed(2)),
                _buildInfoColumn('Buy Price', '₹${stock.buyPrice.toStringAsFixed(2)}'),
                _buildInfoColumn('Current', '₹${stock.currentPrice.toStringAsFixed(2)}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoColumn('Invested', '₹${invested.toStringAsFixed(2)}'),
                _buildInfoColumn(
                  'P/L',
                  '₹${profitLoss.toStringAsFixed(2)}',
                  profitLoss >= 0 ? Colors.green : Colors.red,
                ),
                _buildInfoColumn(
                  'P/L %',
                  '${profitLossPercentage.toStringAsFixed(2)}%',
                  profitLoss >= 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
            if (stock.sixthHighestPrice > 0 && stock.sixthLowestPrice > 0) ...[
              const Divider(height: 20),
              _buildPriceRangeBar(stock),
            ],
            if (stock.sector.isNotEmpty) ...[
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoColumn('Sector', stock.sector, Colors.blue),
                ],
              ),
            ],
            if (trend != null && (trend.ma20 > 0 || trend.ma50 > 0)) ...[
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (trend.ma20 > 0)
                    _buildInfoColumn('20-DMA', '₹${trend.ma20.toStringAsFixed(2)}'),
                  if (trend.ma50 > 0)
                    _buildInfoColumn('50-DMA', '₹${trend.ma50.toStringAsFixed(2)}'),
                  if (trend.ma20 > 0 && trend.ma50 > 0)
                    _buildInfoColumn(
                      '20 vs 50',
                      trend.ma20 > trend.ma50 ? '▲ Above' : '▼ Below',
                      trend.ma20 > trend.ma50 ? Colors.green : Colors.red,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoColumn(
                    'Stock Δ',
                    '${trend.stockDelta.toStringAsFixed(2)}%',
                    trend.stockDelta >= 0 ? Colors.green : Colors.red,
                  ),
                  _buildInfoColumn(
                    'Sensex Δ',
                    '${trend.marketDelta.toStringAsFixed(2)}%',
                    trend.marketDelta >= 0 ? Colors.green : Colors.red,
                  ),
                  _buildInfoColumn(
                    'Adj. Δ',
                    '${trend.adjustedDelta.toStringAsFixed(2)}%',
                    trend.adjustedDelta >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStockTable(FinanceProvider provider) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: _buildTableColumns(),
          rows: provider.stocks.map((stock) {
            final invested = stock.buyPrice * stock.quantity;
            final current = stock.currentPrice * stock.quantity;
            final profitLoss = current - invested;
            final profitLossPercentage = invested > 0 ? (profitLoss / invested) * 100 : 0.0;

            StockTrend? trend;
            try {
              trend = provider.stockTrends.firstWhere((t) => t.stockId == stock.id);
            } catch (_) {
              trend = null;
            }

            final recommendation = _getRecommendation(stock, trend);

            return DataRow(
              cells: _buildDataCells(stock, invested, current, profitLoss, profitLossPercentage, trend, recommendation, provider),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTrendBadge(String trend) {
    Color color;
    IconData icon;
    String label;

    switch (trend) {
      case 'bullish':
        color = Colors.green;
        icon = Icons.trending_up;
        label = 'Bullish';
        break;
      case 'moderately bullish':
        color = Colors.lightGreen;
        icon = Icons.trending_up;
        label = 'Mod. Bullish';
        break;
      case 'bearish':
        color = Colors.red;
        icon = Icons.trending_down;
        label = 'Bearish';
        break;
      case 'moderately bearish':
        color = Colors.orange;
        icon = Icons.trending_down;
        label = 'Mod. Bearish';
        break;
      default:
        color = Colors.grey;
        icon = Icons.trending_flat;
        label = 'Neutral';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, [Color? valueColor]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRangeBar(Stock stock) {
    final sixthLow = stock.sixthLowestPrice;
    final sixthHigh = stock.sixthHighestPrice;
    final currentPrice = stock.currentPrice;
    
    final range = sixthHigh - sixthLow;
    var currentPricePosition = range > 0 ? (currentPrice - sixthLow) / range : 0.5;
    // Clamp position to stay within the bar
    currentPricePosition = currentPricePosition.clamp(0.0, 1.0);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Price Range (6th Low to 6th High)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade400, Colors.orange.shade400],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Positioned(
                  left: currentPricePosition * constraints.maxWidth - 6,
                  child: Column(
                    children: [
                      CustomPaint(
                        size: const Size(12, 16),
                        painter: _TrianglePainter(Colors.blue),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '₹${currentPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildInfoColumn('6th Low', '₹${sixthLow.toStringAsFixed(2)}', Colors.purple),
            _buildInfoColumn('6th High', '₹${sixthHigh.toStringAsFixed(2)}', Colors.orange),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactPriceRangeBar(Stock stock) {
    final sixthLow = stock.sixthLowestPrice;
    final sixthHigh = stock.sixthHighestPrice;
    final currentPrice = stock.currentPrice;
    
    final range = sixthHigh - sixthLow;
    var currentPricePosition = range > 0 ? (currentPrice - sixthLow) / range : 0.5;
    // Clamp position to stay within the bar
    currentPricePosition = currentPricePosition.clamp(0.0, 1.0);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.purple.shade400, Colors.orange.shade400],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Positioned(
              left: currentPricePosition * constraints.maxWidth - 4,
              child: CustomPaint(
                size: const Size(8, 10),
                painter: _TrianglePainter(Colors.blue),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, int id, FinanceProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Stock'),
        content: const Text('Are you sure you want to delete this stock?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await provider.deleteStock(id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadColumnPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedColumns = prefs.getStringList('stock_table_columns');
    if (savedColumns != null) {
      setState(() {
        _selectedColumns.clear();
        _selectedColumns.addAll(savedColumns);
      });
    }
  }

  Future<void> _saveColumnPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('stock_table_columns', _selectedColumns.toList());
  }

  void _showColumnSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Columns'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _allColumns.length,
            itemBuilder: (context, index) {
              final column = _allColumns[index];
              return CheckboxListTile(
                title: Text(column),
                value: _selectedColumns.contains(column),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedColumns.add(column);
                    } else {
                      _selectedColumns.remove(column);
                    }
                  });
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _saveColumnPreferences();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  List<DataColumn> _buildTableColumns() {
    return _allColumns
        .where((column) => _selectedColumns.contains(column))
        .map((column) => DataColumn(label: Text(column)))
        .toList();
  }

  List<DataCell> _buildDataCells(
    Stock stock,
    double invested,
    double current,
    double profitLoss,
    double profitLossPercentage,
    StockTrend? trend,
    String recommendation,
    FinanceProvider provider,
  ) {
    final cells = <DataCell>[];

    if (_selectedColumns.contains('Symbol')) {
      cells.add(DataCell(
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StockChartScreen(
                  symbol: stock.symbol,
                  name: stock.name.isNotEmpty ? stock.name : null,
                ),
              ),
            );
          },
          child: Text(
            stock.symbol,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ));
    }

    if (_selectedColumns.contains('Qty')) {
      cells.add(DataCell(Text(stock.quantity.toStringAsFixed(2))));
    }

    if (_selectedColumns.contains('Buy Price')) {
      cells.add(DataCell(Text('₹${stock.buyPrice.toStringAsFixed(2)}')));
    }

    if (_selectedColumns.contains('Current')) {
      cells.add(DataCell(Text('₹${stock.currentPrice.toStringAsFixed(2)}')));
    }

    if (_selectedColumns.contains('P/L')) {
      cells.add(DataCell(Text(
        '₹${profitLoss.toStringAsFixed(2)}',
        style: TextStyle(color: profitLoss >= 0 ? Colors.green : Colors.red),
      )));
    }

    if (_selectedColumns.contains('P/L %')) {
      cells.add(DataCell(Text(
        '${profitLossPercentage.toStringAsFixed(2)}%',
        style: TextStyle(color: profitLoss >= 0 ? Colors.green : Colors.red),
      )));
    }

    if (_selectedColumns.contains('Sector')) {
      cells.add(DataCell(Text(
        stock.sector.isNotEmpty ? stock.sector : '-',
        style: const TextStyle(color: Colors.blue),
      )));
    }

    if (_selectedColumns.contains('Recommendation')) {
      cells.add(DataCell(
        recommendation == 'BUY'
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.5)),
                ),
                child: const Text(
                  'BUY',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.5)),
                ),
                child: const Text(
                  'NO ACTION REQD',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
      ));
    }

    if (_selectedColumns.contains('Price Range')) {
      cells.add(DataCell(
        stock.sixthHighestPrice > 0 && stock.sixthLowestPrice > 0
            ? SizedBox(
                width: 120,
                height: 30,
                child: _buildCompactPriceRangeBar(stock),
              )
            : const Text('-'),
      ));
    }

    if (_selectedColumns.contains('6th High')) {
      cells.add(DataCell(Text(
        stock.sixthHighestPrice > 0 ? '₹${stock.sixthHighestPrice.toStringAsFixed(2)}' : '-',
        style: const TextStyle(color: Colors.orange),
      )));
    }

    if (_selectedColumns.contains('6th Low')) {
      cells.add(DataCell(Text(
        stock.sixthLowestPrice > 0 ? '₹${stock.sixthLowestPrice.toStringAsFixed(2)}' : '-',
        style: const TextStyle(color: Colors.purple),
      )));
    }

    if (_selectedColumns.contains('Trend')) {
      cells.add(DataCell(trend != null ? _buildTrendBadge(trend.trend) : const Text('-')));
    }

    if (_selectedColumns.contains('Actions')) {
      cells.add(DataCell(Row(
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: null, // Disabled - transaction-based system doesn't support direct stock editing
            color: Colors.grey,
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
            onPressed: () => _showDeleteDialog(context, stock.id, provider),
          ),
        ],
      )));
    }

    return cells;
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    
    // Draw an upward-pointing triangle
    path.moveTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
