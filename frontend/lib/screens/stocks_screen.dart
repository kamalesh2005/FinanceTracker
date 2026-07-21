import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/finance_provider.dart';
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../utils/currency_format.dart';
import 'add_stock_screen.dart';
import 'stock_chart_screen.dart';

class StocksScreen extends StatefulWidget {
  const StocksScreen({super.key});

  @override
  State<StocksScreen> createState() => _StocksScreenState();
}

class _StocksScreenState extends State<StocksScreen> {
  bool _isTableView = true;
  /// null = default multi-key sort (Sector → Market Cap → Name)
  String? _sortColumn;
  bool _sortAscending = true;

  static const double _headerHeight = 48;
  static const double _rowHeight = 78;
  static const double _symbolColumnWidth = 120;

  late final ScrollController _horizontalHeaderController;
  late final ScrollController _horizontalBodyController;
  late final ScrollController _verticalFrozenController;
  late final ScrollController _verticalBodyController;
  bool _syncingHorizontal = false;
  bool _syncingVertical = false;

  final Set<String> _selectedColumns = {
    'Symbol',
    'Qty',
    'Current Value',
    'Buy Price',
    'Current',
    'P/L',
    'P/L %',
    'Sector',
    'Market Cap',
    'Price Range',
    '6th High',
    '6th Low',
    'Trend',
    'Recommendation',
    'Actions',
  };
  
  static const List<String> _allColumns = [
    'Symbol',
    'Qty',
    'Current Value',
    'Buy Price',
    'Current',
    'P/L',
    'P/L %',
    'Sector',
    'Market Cap',
    'Price Range',
    '6th High',
    '6th Low',
    'Trend',
    'Recommendation',
    'Actions',
  ];

  @override
  void initState() {
    super.initState();
    _horizontalHeaderController = ScrollController();
    _horizontalBodyController = ScrollController();
    _verticalFrozenController = ScrollController();
    _verticalBodyController = ScrollController();
    _horizontalHeaderController.addListener(_syncHorizontalFromHeader);
    _horizontalBodyController.addListener(_syncHorizontalFromBody);
    _verticalFrozenController.addListener(_syncVerticalFromFrozen);
    _verticalBodyController.addListener(_syncVerticalFromBody);
    _loadColumnPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<FinanceProvider>();
      await provider.loadStocks();
      provider.refreshStockPrices();
      provider.loadStockTrends();
    });
  }

  @override
  void dispose() {
    _horizontalHeaderController.removeListener(_syncHorizontalFromHeader);
    _horizontalBodyController.removeListener(_syncHorizontalFromBody);
    _verticalFrozenController.removeListener(_syncVerticalFromFrozen);
    _verticalBodyController.removeListener(_syncVerticalFromBody);
    _horizontalHeaderController.dispose();
    _horizontalBodyController.dispose();
    _verticalFrozenController.dispose();
    _verticalBodyController.dispose();
    super.dispose();
  }

  void _syncHorizontalFromHeader() {
    if (_syncingHorizontal) return;
    _syncingHorizontal = true;
    if (_horizontalBodyController.hasClients) {
      _horizontalBodyController.jumpTo(_horizontalHeaderController.offset);
    }
    _syncingHorizontal = false;
  }

  void _syncHorizontalFromBody() {
    if (_syncingHorizontal) return;
    _syncingHorizontal = true;
    if (_horizontalHeaderController.hasClients) {
      _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
    }
    _syncingHorizontal = false;
  }

  void _syncVerticalFromFrozen() {
    if (_syncingVertical) return;
    _syncingVertical = true;
    if (_verticalBodyController.hasClients) {
      _verticalBodyController.jumpTo(_verticalFrozenController.offset);
    }
    _syncingVertical = false;
  }

  void _syncVerticalFromBody() {
    if (_syncingVertical) return;
    _syncingVertical = true;
    if (_verticalFrozenController.hasClients) {
      _verticalFrozenController.jumpTo(_verticalBodyController.offset);
    }
    _syncingVertical = false;
  }

  double _columnWidth(String column) {
    switch (column) {
      case 'Symbol':
        return _symbolColumnWidth;
      case 'Qty':
        return 72;
      case 'Current Value':
        return 120;
      case 'Buy Price':
      case 'Current':
      case 'P/L':
      case '6th High':
      case '6th Low':
        return 100;
      case 'P/L %':
        return 80;
      case 'Sector':
        return 140;
      case 'Market Cap':
        return 110;
      case 'Recommendation':
        return 160;
      case 'Price Range':
        return 160;
      case 'Trend':
        return 130;
      case 'Actions':
        return 100;
      default:
        return 100;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FinanceProvider>(
      builder: (context, provider, _) {
        return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Stocks'),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AddStockScreen()),
                ).then((_) => context.read<FinanceProvider>().loadStocks());
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Stock'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (provider.isRefreshingPrices)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
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
      body: Builder(
        builder: (context) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(child: Text('Error: ${provider.error}'));
          }

          if (provider.stocks.isEmpty) {
            return const Center(child: Text('No stocks added yet'));
          }

          final stocks = _sortedStocks(provider);

          return _isTableView
              ? _buildStockTable(provider, stocks)
              : RefreshIndicator(
                  onRefresh: () => provider.refreshStockPrices(),
                  child: ListView.builder(
                    itemCount: stocks.length,
                    itemBuilder: (context, index) {
                      final stock = stocks[index];
                      return _buildStockCard(context, stock, provider);
                    },
                  ),
                );
        },
      ),
        );
      },
    );
  }

  String _getRecommendation(Stock stock, StockTrend? trend) {
    final parts = <String>[];
    if (stock.sixthHighestPrice > 0 &&
        stock.currentPrice >= stock.sixthHighestPrice * 0.95) {
      parts.add('Book Profit');
    }
    if (trend != null &&
        trend.trend == 'bullish' &&
        stock.currentPrice > stock.buyPrice * 1.1) {
      parts.add('BUY');
    }
    if (trend != null &&
        (trend.trend == 'bearish' || trend.trend == 'moderately bearish') &&
        stock.currentPrice < stock.buyPrice * 0.9) {
      parts.add('SELL');
    }
    if (trend != null &&
        trend.trend == 'moderately bullish' &&
        stock.currentPrice < stock.buyPrice * 0.9) {
      parts.add('WATCH');
    }
    if (parts.isEmpty) return 'NO ACTION REQD';
    return parts.join(' & ');
  }

  Color _recommendationColor(String recommendation) {
    if (recommendation.contains('SELL')) return Colors.red;
    if (recommendation.contains('Book Profit')) return Colors.orange;
    if (recommendation.contains('BUY')) return Colors.green;
    if (recommendation.contains('WATCH')) return Colors.blue;
    return Colors.grey;
  }

  Widget _buildRecommendationBadge(String recommendation, {StockTrend? trend}) {
    final color = _recommendationColor(recommendation);
    final isDefault = recommendation == 'NO ACTION REQD';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(
            recommendation,
            style: TextStyle(
              color: color,
              fontSize: isDefault ? 10 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (!isDefault && trend != null) ...[
          const SizedBox(height: 4),
          Text(
            'M7: ${formatInr(trend.ma7)}  M20: ${formatInr(trend.ma20)}',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade700,
              height: 1.2,
            ),
          ),
          Text(
            'Adj Δ: ${trend.adjustedDelta.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 10,
              color: trend.adjustedDelta >= 0 ? Colors.green : Colors.red,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
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
                    _buildRecommendationBadge(recommendation, trend: trend),
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
                _buildInfoColumn('Buy Price', formatInr(stock.buyPrice)),
                _buildInfoColumn('Current', formatInr(stock.currentPrice)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoColumn('Invested', formatInr(invested)),
                _buildInfoColumn(
                  'P/L',
                  formatInr(profitLoss),
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
            if (stock.sector.isNotEmpty || stock.marketCap.isNotEmpty) ...[
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (stock.sector.isNotEmpty)
                    _buildInfoColumn('Sector', stock.sector, Colors.blue),
                  if (stock.marketCap.isNotEmpty)
                    _buildInfoColumn('Market Cap', stock.marketCap, Colors.indigo),
                ],
              ),
            ],
            if (trend != null && (trend.ma7 > 0 || trend.ma20 > 0)) ...[
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (trend.ma7 > 0)
                    _buildInfoColumn('7-DMA', formatInr(trend.ma7)),
                  if (trend.ma20 > 0)
                    _buildInfoColumn('20-DMA', formatInr(trend.ma20)),
                  if (trend.ma7 > 0 && trend.ma20 > 0)
                    _buildInfoColumn(
                      '7 vs 20',
                      trend.ma7 > trend.ma20 ? '▲ Above' : '▼ Below',
                      trend.ma7 > trend.ma20 ? Colors.green : Colors.red,
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

  Widget _buildStockTable(FinanceProvider provider, List<Stock> stocks) {
    final freezeSymbol = _selectedColumns.contains('Symbol');
    final scrollableColumns = _allColumns
        .where((column) => _selectedColumns.contains(column) && column != 'Symbol')
        .toList();
    final scrollableWidth = scrollableColumns.fold<double>(
      0,
      (sum, column) => sum + _columnWidth(column),
    );
    final headerColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final borderColor = Theme.of(context).dividerColor;

    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: headerColor,
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: SizedBox(
            height: _headerHeight,
            child: Row(
              children: [
                if (freezeSymbol)
                  _buildHeaderCell(
                    'Symbol',
                    width: _symbolColumnWidth,
                    frozen: true,
                    headerColor: headerColor,
                    borderColor: borderColor,
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontalHeaderController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: scrollableColumns
                          .map((column) => _buildHeaderCell(
                                column,
                                width: _columnWidth(column),
                                borderColor: borderColor,
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (freezeSymbol)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(right: BorderSide(color: borderColor)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(2, 0),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: _symbolColumnWidth,
                        height: constraints.maxHeight,
                        child: ListView.builder(
                          controller: _verticalFrozenController,
                          itemCount: stocks.length,
                          itemExtent: _rowHeight,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemBuilder: (context, index) {
                            return _buildFrozenSymbolCell(
                              stocks[index],
                              provider,
                              borderColor,
                              index.isEven,
                            );
                          },
                        ),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _horizontalBodyController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: scrollableWidth < constraints.maxWidth
                            ? constraints.maxWidth
                            : scrollableWidth,
                        height: constraints.maxHeight,
                        child: RefreshIndicator(
                          onRefresh: () => provider.refreshStockPrices(),
                          child: ListView.builder(
                            controller: _verticalBodyController,
                            itemCount: stocks.length,
                            itemExtent: _rowHeight,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final stock = stocks[index];
                              final invested = stock.buyPrice * stock.quantity;
                              final current =
                                  stock.currentPrice * stock.quantity;
                              final profitLoss = current - invested;
                              final profitLossPercentage = invested > 0
                                  ? (profitLoss / invested) * 100
                                  : 0.0;
                              final trend = _trendFor(stock, provider);
                              final recommendation =
                                  _getRecommendation(stock, trend);

                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  color: index.isEven
                                      ? Theme.of(context).colorScheme.surface
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLowest,
                                  border: Border(
                                    bottom: BorderSide(
                                      color: borderColor.withOpacity(0.5),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: scrollableColumns
                                      .map((column) => SizedBox(
                                            width: _columnWidth(column),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                              ),
                                              child: Align(
                                                alignment:
                                                    Alignment.centerLeft,
                                                child: _buildCellWidget(
                                                  column,
                                                  stock,
                                                  profitLoss,
                                                  profitLossPercentage,
                                                  trend,
                                                  recommendation,
                                                  provider,
                                                ),
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCell(
    String column, {
    required double width,
    bool frozen = false,
    Color? headerColor,
    required Color borderColor,
  }) {
    final isSorted = _sortColumn == column;
    final canSort = column != 'Actions';

    return Material(
      color: headerColor ?? Colors.transparent,
      child: InkWell(
        onTap: canSort
            ? () {
                setState(() {
                  if (_sortColumn == column) {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortColumn = column;
                    _sortAscending = true;
                  }
                });
              }
            : null,
        child: Container(
          width: width,
          height: _headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: borderColor.withOpacity(0.5)),
              bottom: frozen ? BorderSide(color: borderColor) : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  column,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSorted
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canSort)
                Icon(
                  isSorted
                      ? (_sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward)
                      : Icons.unfold_more,
                  size: 14,
                  color: isSorted
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFrozenSymbolCell(
    Stock stock,
    FinanceProvider provider,
    Color borderColor,
    bool isEven,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isEven
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: borderColor.withOpacity(0.5)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _buildCellWidget(
            'Symbol',
            stock,
            0,
            0,
            null,
            '',
            provider,
          ),
        ),
      ),
    );
  }

  Widget _buildCellWidget(
    String column,
    Stock stock,
    double profitLoss,
    double profitLossPercentage,
    StockTrend? trend,
    String recommendation,
    FinanceProvider provider,
  ) {
    switch (column) {
      case 'Symbol':
        return GestureDetector(
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
            overflow: TextOverflow.ellipsis,
          ),
        );
      case 'Qty':
        return Text(stock.quantity.toStringAsFixed(2));
      case 'Current Value':
        return Text(formatInr(stock.quantity * stock.currentPrice));
      case 'Buy Price':
        return Text(formatInr(stock.buyPrice));
      case 'Current':
        return Text(formatInr(stock.currentPrice));
      case 'P/L':
        return Text(
          formatInr(profitLoss),
          style: TextStyle(color: profitLoss >= 0 ? Colors.green : Colors.red),
        );
      case 'P/L %':
        return Text(
          '${profitLossPercentage.toStringAsFixed(2)}%',
          style: TextStyle(
            color: profitLoss >= 0 ? Colors.green : Colors.red,
          ),
        );
      case 'Sector':
        return Text(
          stock.sector.isNotEmpty ? stock.sector : '-',
          style: const TextStyle(color: Colors.blue),
          overflow: TextOverflow.ellipsis,
        );
      case 'Market Cap':
        return Text(
          stock.marketCap.isNotEmpty ? stock.marketCap : '-',
          style: const TextStyle(color: Colors.indigo),
          overflow: TextOverflow.ellipsis,
        );
      case 'Recommendation':
        return _buildRecommendationBadge(recommendation, trend: trend);
      case 'Price Range':
        return stock.sixthHighestPrice > 0 && stock.sixthLowestPrice > 0
            ? SizedBox(
                width: 144,
                height: 54,
                child: _buildCompactPriceRangeBar(stock),
              )
            : const Text('-');
      case '6th High':
        return Text(
          stock.sixthHighestPrice > 0
              ? formatInr(stock.sixthHighestPrice)
              : '-',
          style: const TextStyle(color: Colors.orange),
        );
      case '6th Low':
        return Text(
          stock.sixthLowestPrice > 0
              ? formatInr(stock.sixthLowestPrice)
              : '-',
          style: const TextStyle(color: Colors.purple),
        );
      case 'Trend':
        return trend != null ? _buildTrendBadge(trend.trend) : const Text('-');
      case 'Actions':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: null,
              color: Colors.grey,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
              onPressed: () => _showDeleteDialog(context, stock.id, provider),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
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
                          formatInr(currentPrice),
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
            _buildInfoColumn('6th Low', formatInr(sixthLow), Colors.purple),
            _buildInfoColumn('6th High', formatInr(sixthHigh), Colors.orange),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactPriceRangeBar(Stock stock) {
    final sixthLow = stock.sixthLowestPrice;
    final sixthHigh = stock.sixthHighestPrice;
    final currentPrice = stock.currentPrice;
    final buyPrice = stock.buyPrice;
    final currentLabel = formatInr(currentPrice);
    final buyLabel = formatInr(buyPrice);

    final range = sixthHigh - sixthLow;
    // Current & buy: below 6th low → leftmost; above 6th high → rightmost.
    final currentPricePosition = range > 0
        ? ((currentPrice - sixthLow) / range).clamp(0.0, 1.0)
        : 0.5;
    final buyPricePosition = range > 0
        ? ((buyPrice - sixthLow) / range).clamp(0.0, 1.0)
        : 0.5;

    return LayoutBuilder(
      builder: (context, constraints) {
        const labelStyle = TextStyle(fontSize: 9, fontWeight: FontWeight.w600);
        final maxW = constraints.maxWidth;

        double labelWidthFor(String text) =>
            (text.length * 5.2).clamp(28.0, maxW);

        double labelLeftFor(double center, double width) =>
            (center - width / 2).clamp(0.0, maxW - width);

        final currentCenter = currentPricePosition * maxW;
        final buyCenter = buyPricePosition * maxW;
        final currentLabelWidth = labelWidthFor(currentLabel);
        final buyLabelWidth = labelWidthFor(buyLabel);
        final currentLabelLeft = labelLeftFor(currentCenter, currentLabelWidth);
        final buyLabelLeft = labelLeftFor(buyCenter, buyLabelWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: buyLabelLeft,
                    top: 0,
                    child: SizedBox(
                      width: buyLabelWidth,
                      child: Text(
                        buyLabel,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: labelStyle.copyWith(color: Colors.green),
                      ),
                    ),
                  ),
                  Positioned(
                    left: currentLabelLeft,
                    top: 0,
                    child: SizedBox(
                      width: currentLabelWidth,
                      child: Text(
                        currentLabel,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: labelStyle.copyWith(color: Colors.blue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 12,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 3,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 3,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.purple.shade400,
                            Colors.orange.shade400,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    left: buyCenter - 4,
                    top: 0,
                    child: CustomPaint(
                      size: const Size(8, 10),
                      painter: _TrianglePainter(Colors.green),
                    ),
                  ),
                  Positioned(
                    left: currentCenter - 4,
                    top: 0,
                    child: CustomPaint(
                      size: const Size(8, 10),
                      painter: _TrianglePainter(Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatInr(sixthLow),
                  style: labelStyle.copyWith(color: Colors.purple),
                ),
                Text(
                  formatInr(sixthHigh),
                  style: labelStyle.copyWith(color: Colors.orange),
                ),
              ],
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
        // New default columns for existing prefs that predate them
        if (!_selectedColumns.contains('Market Cap')) {
          _selectedColumns.add('Market Cap');
        }
        if (!_selectedColumns.contains('Current Value')) {
          _selectedColumns.add('Current Value');
        }
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

  List<Stock> _sortedStocks(FinanceProvider provider) {
    final stocks = List<Stock>.from(provider.stocks);
    if (_sortColumn == null) {
      stocks.sort(_defaultStockCompare);
    } else {
      stocks.sort((a, b) {
        final cmp = _compareByColumn(a, b, _sortColumn!, provider);
        return _sortAscending ? cmp : -cmp;
      });
    }
    return stocks;
  }

  int _defaultStockCompare(Stock a, Stock b) {
    final sectorCmp = _compareEmptyLast(a.sector, b.sector);
    if (sectorCmp != 0) return sectorCmp;

    final marketCapCmp =
        _marketCapRank(a.marketCap).compareTo(_marketCapRank(b.marketCap));
    if (marketCapCmp != 0) return marketCapCmp;

    final nameA = a.name.isNotEmpty ? a.name : a.symbol;
    final nameB = b.name.isNotEmpty ? b.name : b.symbol;
    return nameA.toLowerCase().compareTo(nameB.toLowerCase());
  }

  int _marketCapRank(String marketCap) {
    switch (marketCap) {
      case 'Large Cap':
        return 0;
      case 'Mid Cap':
        return 1;
      case 'Small Cap':
        return 2;
      default:
        return 3;
    }
  }

  int _compareEmptyLast(String a, String b) {
    final aEmpty = a.isEmpty;
    final bEmpty = b.isEmpty;
    if (aEmpty && bEmpty) return 0;
    if (aEmpty) return 1;
    if (bEmpty) return -1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  int _compareByColumn(
    Stock a,
    Stock b,
    String column,
    FinanceProvider provider,
  ) {
    switch (column) {
      case 'Symbol':
        return a.symbol.toLowerCase().compareTo(b.symbol.toLowerCase());
      case 'Qty':
        return a.quantity.compareTo(b.quantity);
      case 'Current Value':
        return (a.quantity * a.currentPrice)
            .compareTo(b.quantity * b.currentPrice);
      case 'Buy Price':
        return a.buyPrice.compareTo(b.buyPrice);
      case 'Current':
        return a.currentPrice.compareTo(b.currentPrice);
      case 'P/L':
        return _profitLoss(a).compareTo(_profitLoss(b));
      case 'P/L %':
        return _profitLossPct(a).compareTo(_profitLossPct(b));
      case 'Sector':
        return _compareEmptyLast(a.sector, b.sector);
      case 'Market Cap':
        return _marketCapRank(a.marketCap).compareTo(_marketCapRank(b.marketCap));
      case 'Recommendation':
        return _getRecommendation(a, _trendFor(a, provider))
            .compareTo(_getRecommendation(b, _trendFor(b, provider)));
      case 'Price Range':
        return _priceRangeSortKey(a).compareTo(_priceRangeSortKey(b));
      case '6th High':
        return a.sixthHighestPrice.compareTo(b.sixthHighestPrice);
      case '6th Low':
        return a.sixthLowestPrice.compareTo(b.sixthLowestPrice);
      case 'Trend':
        final trendA = _trendFor(a, provider)?.trend ?? '';
        final trendB = _trendFor(b, provider)?.trend ?? '';
        return _compareEmptyLast(trendA, trendB);
      default:
        return 0;
    }
  }

  double _profitLoss(Stock stock) {
    final invested = stock.buyPrice * stock.quantity;
    final current = stock.currentPrice * stock.quantity;
    return current - invested;
  }

  double _profitLossPct(Stock stock) {
    final invested = stock.buyPrice * stock.quantity;
    if (invested <= 0) return 0;
    return (_profitLoss(stock) / invested) * 100;
  }

  double _priceRangeSortKey(Stock stock) {
    if (stock.sixthHighestPrice > 0 && stock.sixthLowestPrice > 0) {
      return (stock.sixthHighestPrice + stock.sixthLowestPrice) / 2;
    }
    return stock.sixthLowestPrice;
  }

  StockTrend? _trendFor(Stock stock, FinanceProvider provider) {
    try {
      return provider.stockTrends.firstWhere((t) => t.stockId == stock.id);
    } catch (_) {
      return null;
    }
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
