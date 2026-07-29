import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import '../providers/auth_provider.dart';
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../services/api_service.dart';
import '../services/recommendation_engine.dart';
import '../utils/currency_format.dart';
import '../widgets/auth_app_bar_actions.dart';
import 'add_stock_screen.dart';
import 'configure_screen.dart';
import 'edit_stock_screen.dart';
import 'stock_chart_screen.dart';

class StocksScreen extends StatefulWidget {
  const StocksScreen({super.key});

  @override
  State<StocksScreen> createState() => _StocksScreenState();
}

class _StocksScreenState extends State<StocksScreen> {
  bool _isTableView = true;

  /// null = default multi-key sort (Sector → Market Cap → Symbol → Source)
  String? _sortColumn;
  bool _sortAscending = true;

  static const String _unspecified = 'Unspecified';
  static const String _manualAddSource = 'Manual Add';
  static const List<String> _marketCapOptions = [
    'Large Cap',
    'Mid Cap',
    'Small Cap',
    _unspecified,
  ];
  static const List<String> _recommendationOptions = [
    'Book Profit',
    'BUY',
    'SELL',
    'AT BUY PRICE',
    'AT SELL PRICE',
    'AT HOLD PRICE',
    'NO ACTION REQD',
  ];
  static const List<String> _actionableRecommendations = [
    'Book Profit',
    'BUY',
    'SELL',
  ];
  static const List<String> _nonActionRecommendations = [
    'NO ACTION REQD',
    'AT BUY PRICE',
    'AT SELL PRICE',
    'AT HOLD PRICE',
  ];

  final Set<String> _selectedSectors = {};
  final Set<String> _selectedMarketCaps = {};
  final Set<String> _selectedSources = {};
  final Set<String> _selectedRecommendations = {};
  bool _onlyStocksToAction = true;

  static const double _headerHeight = 48;
  static const double _rowHeight = 90;
  static const double _symbolColumnWidth = 120;
  /// Below this width, prefer card view (table is too dense for phones).
  static const double _cardViewBreakpoint = 700;
  /// Below this width, slim the AppBar (icon Add, hide display name).
  static const double _narrowAppBarBreakpoint = 600;
  /// Below this width, stack card metric rows into 2 columns.
  static const double _narrowCardBreakpoint = 400;

  late final ScrollController _horizontalHeaderController;
  late final ScrollController _horizontalBodyController;
  late final ScrollController _verticalFrozenController;
  late final ScrollController _verticalBodyController;
  bool _syncingHorizontal = false;
  bool _syncingVertical = false;

  final Set<String> _selectedColumns = {..._defaultSelectedColumns};
  static const List<String> _allColumns = [
    'Symbol',
    'Source',
    'Qty',
    'Current Value',
    'Buy Price',
    'Current',
    'P/L',
    'P/L %',
    'Sector',
    'Last Actioned',
    'Price Range',
    '6th High',
    '6th Low',
    'Trend',
    'Recommendation',
    'Actions',
    'News',
  ];

  static const Set<String> _defaultSelectedColumns = {
    'Symbol',
    'Source',
    'Qty',
    'Current Value',
    'Buy Price',
    'Current',
    'P/L',
    'P/L %',
    'Sector',
    'Price Range',
    '6th High',
    '6th Low',
    'Trend',
    'Recommendation',
    'Actions',
    'News',
  };

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
      await context.read<AuthProvider>().loadPreferences();
      if (!mounted) return;
      final provider = context.read<FinanceProvider>();
      await provider.loadStocks();
      // Show persisted trends immediately; don't block on Yahoo refresh.
      await provider.loadStockTrends();
      await provider.refreshStockPrices();
      // Pick up any trends refresh computed for incomplete symbols.
      await provider.loadStockTrends();
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
      case 'Source':
        return 120;
      case 'Current Value':
        return 120;
      case 'Buy Price':
      case 'Current':
      case 'P/L':
      case '6th High':
      case '6th Low':
      case 'Last Actioned':
        return 120;
      case 'P/L %':
        return 80;
      case 'Sector':
        return 160;
      case 'Recommendation':
        return 160;
      case 'Price Range':
        return 160;
      case 'Trend':
        return 170;
      case 'Actions':
        return 250;
      case 'News':
        return 180;
      default:
        return 100;
    }
  }

  Future<void> _openAddStock() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddStockScreen()),
    );
    if (!mounted) return;
    await context.read<FinanceProvider>().loadStocks();
  }

  Future<void> _openConfigure() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConfigureScreen()),
    );
    if (!mounted) return;
    await context.read<AuthProvider>().loadPreferences();
    if (!mounted) return;
    await context.read<FinanceProvider>().loadStocks();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final narrowAppBar = screenWidth < _narrowAppBarBreakpoint;
    // Force card view on phones; respect toggle on tablet/desktop.
    final showTableView =
        screenWidth >= _cardViewBreakpoint && _isTableView;
    final canToggleView = screenWidth >= _cardViewBreakpoint;

    return Consumer<FinanceProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Stocks'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: authAppBarActions(
              context,
              extra: [
                if (narrowAppBar)
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add Stock',
                    onPressed: _openAddStock,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: OutlinedButton.icon(
                      onPressed: _openAddStock,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Stock'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.primary,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                if (provider.isRefreshingPrices)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh prices',
                    onPressed: () => provider.refreshStockPrices(),
                  ),
                if (showTableView)
                  IconButton(
                    icon: const Icon(Icons.view_column),
                    onPressed: _showColumnSelectionDialog,
                    tooltip: 'Select columns',
                  ),
                if (canToggleView)
                  IconButton(
                    icon: Icon(
                        showTableView ? Icons.view_module : Icons.table_rows),
                    onPressed: () {
                      setState(() {
                        _isTableView = !_isTableView;
                      });
                    },
                    tooltip: showTableView ? 'Card view' : 'Table view',
                  ),
                if (!narrowAppBar)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Text(
                        auth.user?.displayName ?? '',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: () {
                    if (!narrowAppBar) return 'Configure';
                    final name = auth.user?.displayName ?? '';
                    return name.isNotEmpty ? 'Configure ($name)' : 'Configure';
                  }(),
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _openConfigure,
                ),
              ],
            ),
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

              final stocks = _filteredAndSortedStocks(provider);
              final hasFilters = _hasActiveFilters;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFilterBar(provider),
                  Expanded(
                    child: stocks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('No stocks match filters'),
                                if (hasFilters) ...[
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _clearFilters,
                                    child: const Text('Clear filters'),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : showTableView
                            ? _buildStockTable(provider, stocks)
                            : RefreshIndicator(
                                onRefresh: () => provider.refreshStockPrices(),
                                child: ListView.builder(
                                  itemCount: stocks.length,
                                  itemBuilder: (context, index) {
                                    final stock = stocks[index];
                                    return KeyedSubtree(
                                      key: ValueKey(_stockRowKey(stock)),
                                      child: _buildStockCard(
                                        context,
                                        stock,
                                        provider,
                                      ),
                                    );
                                  },
                                ),
                              ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  bool get _hasActiveFilters =>
      _selectedSectors.isNotEmpty ||
      _selectedMarketCaps.isNotEmpty ||
      _selectedSources.isNotEmpty ||
      _selectedRecommendations.isNotEmpty ||
      !_onlyStocksToAction;

  void _clearFilters() {
    setState(() {
      _selectedSectors.clear();
      _selectedMarketCaps.clear();
      _selectedSources.clear();
      _selectedRecommendations.clear();
      _onlyStocksToAction = true;
    });
  }

  String _stockRowKey(Stock stock) => '${stock.id}|${stock.source}';

  String _sectorKey(Stock stock) =>
      stock.sector.isNotEmpty ? stock.sector : _unspecified;

  String _marketCapKey(Stock stock) =>
      stock.marketCap.isNotEmpty ? stock.marketCap : _unspecified;

  String _sourceKey(Stock stock) =>
      stock.source.isNotEmpty ? stock.source : _unspecified;

  bool _isManualAddSource(Stock stock) =>
      stock.source.isEmpty || stock.source == _manualAddSource;

  List<String> _sectorOptions(List<Stock> stocks) {
    final sectors = stocks
        .map((s) => s.sector.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final hasUnspecified = stocks.any((s) => s.sector.trim().isEmpty);
    if (hasUnspecified) sectors.add(_unspecified);
    return sectors;
  }

  List<String> _sourceOptions(List<Stock> stocks) {
    final sources = stocks
        .map((s) => s.source.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final hasUnspecified = stocks.any((s) => s.source.trim().isEmpty);
    if (hasUnspecified) sources.add(_unspecified);
    return sources;
  }

  Widget _buildFilterBar(FinanceProvider provider) {
    final sectorOptions = _sectorOptions(provider.stocks);
    final sourceOptions = _sourceOptions(provider.stocks);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildFilterMenu(
              label: 'Sector',
              selected: _selectedSectors,
              options: sectorOptions,
              onChanged: (next) => setState(() {
                _selectedSectors
                  ..clear()
                  ..addAll(next);
              }),
            ),
            _buildFilterMenu(
              label: 'Market Cap',
              selected: _selectedMarketCaps,
              options: _marketCapOptions,
              onChanged: (next) => setState(() {
                _selectedMarketCaps
                  ..clear()
                  ..addAll(next);
              }),
            ),
            _buildFilterMenu(
              label: 'Source',
              selected: _selectedSources,
              options: sourceOptions,
              onChanged: (next) => setState(() {
                _selectedSources
                  ..clear()
                  ..addAll(next);
              }),
            ),
            _buildFilterMenu(
              label: 'Recommendation',
              selected: _selectedRecommendations,
              options: _recommendationOptions,
              onChanged: (next) => setState(() {
                _selectedRecommendations
                  ..clear()
                  ..addAll(next);
              }),
            ),
            FilterChip(
              label: const Text('Only Stocks to Action'),
              selected: _onlyStocksToAction,
              onSelected: (value) => setState(() {
                _onlyStocksToAction = value;
              }),
            ),
            if (_hasActiveFilters)
              TextButton(
                onPressed: _clearFilters,
                child: const Text('Clear'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterMenu({
    required String label,
    required Set<String> selected,
    required List<String> options,
    required ValueChanged<Set<String>> onChanged,
  }) {
    final count = selected.length;
    final buttonLabel = count > 0 ? '$label ($count)' : label;
    final colorScheme = Theme.of(context).colorScheme;
    final active = count > 0;
    return PopupMenuButton<String>(
      tooltip: 'Filter by $label',
      onSelected: (value) {
        final next = Set<String>.from(selected);
        if (next.contains(value)) {
          next.remove(value);
        } else {
          next.add(value);
        }
        onChanged(next);
      },
      itemBuilder: (context) {
        if (options.isEmpty) {
          return [
            const PopupMenuItem<String>(
              enabled: false,
              child: Text('No options'),
            ),
          ];
        }
        return options
            .map(
              (option) => CheckedPopupMenuItem<String>(
                value: option,
                checked: selected.contains(option),
                child: Text(option),
              ),
            )
            .toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? colorScheme.primary : colorScheme.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list,
              size: 16,
              color: active ? colorScheme.primary : colorScheme.onSurface,
            ),
            const SizedBox(width: 6),
            Text(
              buttonLabel,
              style: TextStyle(
                color: active ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: active ? colorScheme.primary : colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  List<Stock> _filteredAndSortedStocks(FinanceProvider provider) {
    final filtered = provider.stocks.where((stock) {
      if (_selectedSectors.isNotEmpty &&
          !_selectedSectors.contains(_sectorKey(stock))) {
        return false;
      }
      if (_selectedMarketCaps.isNotEmpty &&
          !_selectedMarketCaps.contains(_marketCapKey(stock))) {
        return false;
      }
      if (_selectedSources.isNotEmpty &&
          !_selectedSources.contains(_sourceKey(stock))) {
        return false;
      }
      final recommendation =
          _getRecommendation(stock, _trendFor(stock, provider));
      if (_selectedRecommendations.isNotEmpty) {
        final matches = _selectedRecommendations.any((label) {
          if (label == 'NO ACTION REQD' ||
              label == 'AT BUY PRICE' ||
              label == 'AT SELL PRICE' ||
              label == 'AT HOLD PRICE') {
            return recommendation == label;
          }
          return recommendation.contains(label);
        });
        if (!matches) return false;
      }
      if (_onlyStocksToAction) {
        if (_nonActionRecommendations.contains(recommendation)) {
          return false;
        }
        final actionable = _actionableRecommendations
            .any((label) => recommendation.contains(label));
        if (!actionable) return false;
      }
      return true;
    }).toList();
    return _sortedStocks(filtered, provider);
  }

  String _getRecommendation(Stock stock, StockTrend? trend) {
    final rules = context.read<AuthProvider>().effectiveRecommendationRules;
    return RecommendationEngine.evaluate(stock, trend, rules);
  }

  Color _recommendationColor(String recommendation) {
    if (recommendation.contains('SELL') && recommendation != 'AT SELL PRICE') {
      return Colors.red;
    }
    if (recommendation.contains('Book Profit')) return Colors.orange;
    if (recommendation.contains('BUY') && recommendation != 'AT BUY PRICE') {
      return Colors.green;
    }
    return Colors.grey;
  }

  Widget _buildRecommendationBadge(String recommendation, {StockTrend? trend}) {
    final color = _recommendationColor(recommendation);
    final isDefault = recommendation == 'NO ACTION REQD' ||
        recommendation == 'AT BUY PRICE' ||
        recommendation == 'AT SELL PRICE' ||
        recommendation == 'AT HOLD PRICE';
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            'M7: ${formatInr(trend.ma7)}  M20: ${formatInr(trend.ma20)}  M50: ${formatInr(trend.ma50)}',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade700,
              height: 1.2,
            ),
          ),
          Text(
            'Adj ST Δ: ${trend.adjustedSTDelta.toStringAsFixed(2)}%  Adj MT Δ: ${trend.adjustedMTDelta.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 10,
              color: trend.adjustedSTDelta >= 0 ? Colors.green : Colors.red,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStockCard(
      BuildContext context, Stock stock, FinanceProvider provider) {
    final invested = stock.buyPrice * stock.quantity;
    final current = stock.currentPrice * stock.quantity;
    final profitLoss = current - invested;
    final profitLossPercentage =
        invested > 0 ? (profitLoss / invested) * 100 : 0.0;
    final narrowCard =
        MediaQuery.sizeOf(context).width < _narrowCardBreakpoint;

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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                            style: const TextStyle(
                                fontSize: 13, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      _buildRecommendationBadge(recommendation, trend: trend),
                      if (trend != null) _buildTrendBadge(trend.trend),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 0,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildBuySellActionButtons(stock, provider),
                  if (_isManualAddSource(stock))
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _openEditStock(stock),
                    ),
                  IconButton(
                    icon:
                        const Icon(Icons.delete, size: 20, color: Colors.red),
                    onPressed: () {
                      _showDeleteDialog(context, stock.id, provider);
                    },
                  ),
                ],
              ),
            ),
            if (stock.source.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                stock.source,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 12),
            _buildMetricRow(
              narrow: narrowCard,
              children: [
                _buildInfoColumn(
                    'Quantity', stock.quantity.toStringAsFixed(2)),
                _buildInfoColumn('Buy Price', formatInr(stock.buyPrice)),
                _buildInfoColumn('Current', formatInr(stock.currentPrice)),
              ],
            ),
            const SizedBox(height: 12),
            _buildMetricRow(
              narrow: narrowCard,
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
              _buildInfoColumnWidget(
                'Sector',
                _buildSectorWithMarketCap(stock),
              ),
            ],
            if (trend != null &&
                (trend.ma7 > 0 || trend.ma20 > 0 || trend.ma50 > 0)) ...[
              const Divider(height: 20),
              _buildMetricRow(
                narrow: narrowCard,
                children: [
                  if (trend.ma7 > 0)
                    _buildInfoColumn('7-DMA', formatInr(trend.ma7)),
                  if (trend.ma20 > 0)
                    _buildInfoColumn('20-DMA', formatInr(trend.ma20)),
                  if (trend.ma50 > 0)
                    _buildInfoColumn('50-DMA', formatInr(trend.ma50)),
                  if (trend.ma7 > 0 && trend.ma20 > 0)
                    _buildInfoColumn(
                      'ST: 7 vs 20',
                      trend.ma7 > trend.ma20 ? '▲ Above' : '▼ Below',
                      trend.ma7 > trend.ma20 ? Colors.green : Colors.red,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _buildMetricRow(
                narrow: narrowCard,
                children: [
                  _buildInfoColumn(
                    'Stock ST Δ',
                    '${trend.stockSTDelta.toStringAsFixed(2)}%',
                    trend.stockSTDelta >= 0 ? Colors.green : Colors.red,
                  ),
                  _buildInfoColumn(
                    'Sensex ST Δ',
                    '${trend.marketSTDelta.toStringAsFixed(2)}%',
                    trend.marketSTDelta >= 0 ? Colors.green : Colors.red,
                  ),
                  _buildInfoColumn(
                    'Adj ST Δ',
                    '${trend.adjustedSTDelta.toStringAsFixed(2)}%',
                    trend.adjustedSTDelta >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              ),
              if (trend.ma20 > 0 && trend.ma50 > 0) ...[
                const SizedBox(height: 8),
                _buildMetricRow(
                  narrow: narrowCard,
                  children: [
                    _buildInfoColumn(
                      'Stock MT Δ',
                      '${trend.stockMTDelta.toStringAsFixed(2)}%',
                      trend.stockMTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    _buildInfoColumn(
                      'Sensex MT Δ',
                      '${trend.marketMTDelta.toStringAsFixed(2)}%',
                      trend.marketMTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    _buildInfoColumn(
                      'Adj MT Δ',
                      '${trend.adjustedMTDelta.toStringAsFixed(2)}%',
                      trend.adjustedMTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                  ],
                ),
              ],
            ],
            const Divider(height: 20),
            _buildInfoColumnWidget('News', _buildNewsTeaser(stock)),
          ],
        ),
      ),
    );
  }

  /// Wide: single spaceBetween row. Narrow: wrap into ~2 columns.
  Widget _buildMetricRow({
    required bool narrow,
    required List<Widget> children,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (!narrow) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: children,
      );
    }
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: children
          .map(
            (child) => SizedBox(
              width: 140,
              child: child,
            ),
          )
          .toList(),
    );
  }

  Widget _buildStockTable(FinanceProvider provider, List<Stock> stocks) {
    final freezeSymbol = _selectedColumns.contains('Symbol');
    final scrollableColumns = _allColumns
        .where(
            (column) => _selectedColumns.contains(column) && column != 'Symbol')
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
                                                alignment: Alignment.centerLeft,
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
                    color:
                        isSorted ? Theme.of(context).colorScheme.primary : null,
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
      case 'Source':
        return Text(
          stock.source.isNotEmpty ? stock.source : '-',
          overflow: TextOverflow.ellipsis,
        );
      case 'Current Value':
        return Text(formatInr(stock.quantity * stock.currentPrice));
      case 'Buy Price':
        return Text(formatInr(stock.buyPrice));
      case 'Last Actioned':
        final label = stock.lastActionLabel;
        final price = stock.lastActionPrice;
        final date = stock.lastActionDate;
        if (label == null || price == null || date == null) {
          return const Text('-');
        }
        final color = switch (stock.lastActionType) {
          'buy' => Colors.green.shade700,
          'sell' => Colors.deepOrange,
          'hold' => Colors.indigo.shade700,
          _ => Colors.grey.shade700,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: color,
              ),
            ),
            Text(
              formatInr(price),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              _formatTradeDate(date),
              style: TextStyle(
                fontSize: 11,
                color: color,
              ),
            ),
          ],
        );
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
        return _buildSectorWithMarketCap(stock);
      case 'Trend':
        return trend != null
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _buildTrendBadge(trend.trend),
              )
            : const Text('-');
      case 'Recommendation':
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: _buildRecommendationBadge(recommendation, trend: trend),
        );
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
          stock.sixthLowestPrice > 0 ? formatInr(stock.sixthLowestPrice) : '-',
          style: const TextStyle(color: Colors.purple),
        );
      case 'Actions':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBuySellActionButtons(stock, provider),
            if (_isManualAddSource(stock))
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => _openEditStock(stock),
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
      case 'News':
        return _buildNewsTeaser(stock);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildNewsTeaser(Stock stock) {
    if (!stock.hasConsensus) {
      return InkWell(
        onTap: () => _showNewsDialog(stock),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Text(
            'No consensus data',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    final type = stock.consensusType.trim().isEmpty
        ? '—'
        : stock.consensusType.trim().toUpperCase();
    final targetLine = stock.consensusTarget > 0
        ? '$type @ ${formatInr(stock.consensusTarget)}'
        : type;
    final upsideSign = stock.consensusUpside >= 0 ? '+' : '';
    final detailLine = [
      if (stock.consensusUpside != 0 || stock.consensusTarget > 0)
        '$upsideSign${stock.consensusUpside.toStringAsFixed(2)}%',
      if (stock.consensusDate != null) _formatTradeDate(stock.consensusDate),
    ].join(' · ');

    final typeColor = switch (stock.consensusType.trim().toLowerCase()) {
      'buy' || 'accumulate' => Colors.green.shade700,
      'sell' => Colors.red.shade700,
      'hold' => Colors.orange.shade800,
      _ => Colors.teal.shade800,
    };

    return InkWell(
      onTap: () => _showNewsDialog(stock),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              targetLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: typeColor,
              ),
            ),
            if (detailLine.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                detailLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade700,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showNewsDialog(Stock stock) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('${stock.symbol} — News'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Trendlyne Consensus Share Price Target',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (!stock.hasConsensus)
                    Text(
                      'No consensus data available.',
                      style: TextStyle(color: Colors.grey.shade700),
                    )
                  else ...[
                    _consensusDetailRow(
                      'Date',
                      stock.consensusDate != null
                          ? _formatTradeDate(stock.consensusDate)
                          : '—',
                    ),
                    _consensusDetailRow(
                      'LTP',
                      stock.consensusLtp > 0
                          ? formatInr(stock.consensusLtp)
                          : '—',
                    ),
                    _consensusDetailRow(
                      'Target',
                      stock.consensusTarget > 0
                          ? formatInr(stock.consensusTarget)
                          : '—',
                    ),
                    _consensusDetailRow(
                      'Upside',
                      '${stock.consensusUpside >= 0 ? '+' : ''}${stock.consensusUpside.toStringAsFixed(2)}%',
                    ),
                    _consensusDetailRow(
                      'Type',
                      stock.consensusType.trim().isEmpty
                          ? '—'
                          : stock.consensusType.trim().toUpperCase(),
                    ),
                  ],
                  if (stock.lastConsensusFetchedDate != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Fetched ${_formatTradeDate(stock.lastConsensusFetchedDate)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  if (stock.trendlyneUrl.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Source',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      stock.trendlyneUrl.trim(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _consensusDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTradeDate(DateTime? date) {
    if (date == null) return '-';
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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
      case 'bearish_st':
        color = Colors.red;
        icon = Icons.trending_down;
        label = 'Bearish ST';
        break;
      case 'moderately bearish_st':
        color = Colors.orange;
        icon = Icons.trending_down;
        label = 'Mod. Bearish ST';
        break;
      case 'bearish_lt':
        color = Colors.red;
        icon = Icons.trending_down;
        label = 'Bearish LT';
        break;
      case 'moderately bearish_lt':
        color = Colors.deepOrange;
        icon = Icons.trending_down;
        label = 'Mod. Bearish LT';
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
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold),
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

  Widget _buildInfoColumnWidget(String label, Widget value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        DefaultTextStyle.merge(
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          child: value,
        ),
      ],
    );
  }

  /// Sector with market-cap letter, e.g. Energy(L). Tooltip on L/M/S.
  Widget _buildSectorWithMarketCap(Stock stock) {
    const style = TextStyle(color: Colors.blue);
    final sector = stock.sector.trim();
    final letter = switch (stock.marketCap) {
      'Large Cap' => 'L',
      'Mid Cap' => 'M',
      'Small Cap' => 'S',
      _ => '',
    };
    final tooltip = switch (stock.marketCap) {
      'Large Cap' => 'Large Cap',
      'Mid Cap' => 'Mid Cap',
      'Small Cap' => 'Small Cap',
      _ => '',
    };

    if (sector.isEmpty && letter.isEmpty) {
      return const Text('-', style: style);
    }
    if (letter.isEmpty) {
      return Text(
        sector.isEmpty ? '-' : sector,
        style: style,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (sector.isNotEmpty) TextSpan(text: sector),
          const TextSpan(text: '('),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Tooltip(
              message: tooltip,
              waitDuration: const Duration(milliseconds: 300),
              child: Text(letter, style: style),
            ),
          ),
          const TextSpan(text: ')'),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  Widget _buildPriceRangeBar(Stock stock) {
    final sixthLow = stock.sixthLowestPrice;
    final sixthHigh = stock.sixthHighestPrice;
    final currentPrice = stock.currentPrice;

    final range = sixthHigh - sixthLow;
    var currentPricePosition =
        range > 0 ? (currentPrice - sixthLow) / range : 0.5;
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
                        colors: [
                          Colors.purple.shade400,
                          Colors.orange.shade400
                        ],
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
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
    final currentPricePosition =
        range > 0 ? ((currentPrice - sixthLow) / range).clamp(0.0, 1.0) : 0.5;
    final buyPricePosition =
        range > 0 ? ((buyPrice - sixthLow) / range).clamp(0.0, 1.0) : 0.5;

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

  Future<void> _openEditStock(Stock stock) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditStockScreen(stock: stock),
      ),
    );
  }

  Widget _buildBuySellActionButtons(Stock stock, FinanceProvider provider) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => _showBuySellDialog(stock, provider, isBuy: true),
          style: TextButton.styleFrom(
            foregroundColor: Colors.green.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('B', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: stock.quantity > 0
              ? () => _showBuySellDialog(stock, provider, isBuy: false)
              : null,
          style: TextButton.styleFrom(
            foregroundColor: Colors.orange.shade800,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('S', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: stock.currentPrice > 0
              ? () => _showHoldDialog(stock, provider)
              : null,
          style: TextButton.styleFrom(
            foregroundColor: Colors.indigo.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('H', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: () => _showThresholdsDialog(stock, provider),
          style: TextButton.styleFrom(
            foregroundColor: Colors.teal.shade800,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('T', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Future<void> _showThresholdsDialog(
    Stock stock,
    FinanceProvider provider,
  ) async {
    final sourceLabel =
        stock.source.trim().isEmpty ? _manualAddSource : stock.source.trim();
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
                Text('Source: $sourceLabel',
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

    if (result == null || !mounted) return;

    final ok = await provider.setStockThresholds(
      stockId: stock.id,
      source: sourceLabel,
      setBuyPrice: result['buy']!,
      setProfitBookingPrice: result['profit']!,
      setStopLossPrice: result['stop']!,
    );
    if (!mounted) return;
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

  Future<void> _showHoldDialog(Stock stock, FinanceProvider provider) async {
    final price = stock.currentPrice;
    final sourceLabel =
        stock.source.trim().isEmpty ? _manualAddSource : stock.source.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hold ${stock.symbol}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Source: $sourceLabel',
                style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            const Text(
              'Mark this stock as Hold and use the current price as the baseline for % fluctuation in recommendation logic?',
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
    if (confirmed != true || !mounted) return;

    final ok = await provider.holdStock(
      stockId: stock.id,
      price: price,
      source: sourceLabel,
      heldAt: DateTime.now(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Hold recorded' : (provider.error ?? 'Hold failed')),
      ),
    );
  }

  Future<void> _showBuySellDialog(
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
    final sourceLabel =
        stock.source.trim().isEmpty ? _manualAddSource : stock.source.trim();
    final maxSellQty = stock.quantity;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title:
                  Text(isBuy ? 'Buy ${stock.symbol}' : 'Sell ${stock.symbol}'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Source: $sourceLabel',
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

    // Dispose after the dialog route has finished tearing down its fields.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      qtyController.dispose();
      priceController.dispose();
    });

    if (result == null) return;

    final qty = result['quantity'] as double;
    final price = result['price'] as double;
    final date = result['date'] as DateTime;

    final ok = isBuy
        ? await provider.buyStockTransaction(
            symbol: stock.symbol,
            quantity: qty,
            price: price,
            transactionDate: date,
            source: sourceLabel,
            name: stock.name,
          )
        : await provider.sellStockTransaction(
            symbol: stock.symbol,
            quantity: qty,
            price: price,
            transactionDate: date,
            source: sourceLabel,
          );

    if (!mounted) return;
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

  void _showDeleteDialog(
      BuildContext context, int id, FinanceProvider provider) {
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
    try {
      final hidden =
          _normalizeHiddenColumns(await ApiService.getHiddenStockColumns());
      if (!mounted) return;
      setState(() {
        _selectedColumns
          ..clear()
          ..addAll(_allColumns.where((c) => !hidden.contains(c)));
        if (_selectedColumns.isEmpty) {
          _selectedColumns.addAll(_defaultSelectedColumns);
        }
      });
    } catch (_) {
      // Keep defaults if config cannot be loaded.
    }
  }

  List<String> _normalizeHiddenColumns(List<String> hidden) {
    final out = <String>{};
    var hideLastBuy = false;
    var hideLastSale = false;
    for (final name in hidden) {
      switch (name) {
        case 'Last Buy Price':
        case 'Last Buy Date':
        case 'Last Buy':
          hideLastBuy = true;
          break;
        case 'Last Sale Price':
        case 'Last Sale Date':
        case 'Last Sale':
          hideLastSale = true;
          break;
        default:
          // Drop removed columns (e.g. Market Cap) from persisted prefs.
          if (_allColumns.contains(name)) {
            out.add(name);
          }
      }
    }
    // Hide Last Actioned only when both former last-trade columns were hidden.
    if (hideLastBuy && hideLastSale) {
      out.add('Last Actioned');
    }
    return out.toList();
  }

  Future<void> _saveColumnPreferences() async {
    final hidden =
        _allColumns.where((c) => !_selectedColumns.contains(c)).toList();
    try {
      await ApiService.saveHiddenStockColumns(hidden);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save column preferences: $e')),
        );
      }
    }
  }

  void _showColumnSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                    setDialogState(() {
                      if (value == true) {
                        _selectedColumns.add(column);
                      } else {
                        _selectedColumns.remove(column);
                      }
                    });
                    setState(() {});
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
              onPressed: () async {
                await _saveColumnPreferences();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  List<Stock> _sortedStocks(List<Stock> input, FinanceProvider provider) {
    final stocks = List<Stock>.from(input);
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

    final symbolCmp = a.symbol.toLowerCase().compareTo(b.symbol.toLowerCase());
    if (symbolCmp != 0) return symbolCmp;

    return _compareEmptyLast(a.source, b.source);
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
      case 'Source':
        return _compareEmptyLast(a.source, b.source);
      case 'Qty':
        return a.quantity.compareTo(b.quantity);
      case 'Current Value':
        return (a.quantity * a.currentPrice)
            .compareTo(b.quantity * b.currentPrice);
      case 'Buy Price':
        return a.buyPrice.compareTo(b.buyPrice);
      case 'Last Actioned':
        return (a.lastActionPrice ?? 0).compareTo(b.lastActionPrice ?? 0);
      case 'Current':
        return a.currentPrice.compareTo(b.currentPrice);
      case 'P/L':
        return _profitLoss(a).compareTo(_profitLoss(b));
      case 'P/L %':
        return _profitLossPct(a).compareTo(_profitLossPct(b));
      case 'Sector':
        return _compareEmptyLast(a.sector, b.sector);
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
      case 'News':
        return a.consensusTarget.compareTo(b.consensusTarget);
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
