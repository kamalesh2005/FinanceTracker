import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import '../providers/auth_provider.dart';
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../services/api_service.dart';
import '../services/recommendation_engine.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
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

  /// null = default multi-key sort (Industry → Market Cap → Symbol → Account).
  /// Card layout always sorts by Symbol instead.
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

  String? _selectedIndustry;
  String? _selectedMarketCap;
  String? _selectedSource;
  String? _selectedRecommendation;
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
    'Industry',
    'Symbol',
    'Account',
    'Qty',
    'Current Value',
    'Buy Price',
    'Current',
    'P/L',
    'P/L %',
    'Last Actioned',
    'Price Range',
    'High',
    'Low',
    'Trend',
    'Signal',
    'Actions',
    'News',
  ];

  /// Columns pinned on the left when selected (order matters).
  static const List<String> _frozenColumnNames = [
    'Industry',
    'Symbol',
  ];

  /// Sentinel stored in hidden_columns so the v2 default-hide migration runs once.
  static const String _columnDefaultsV2Sentinel = '__defaults_v2';

  static const Set<String> _defaultHiddenColumns = {
    'Buy Price',
    'Current',
    'P/L',
    'High',
    'Low',
  };

  static const Set<String> _defaultSelectedColumns = {
    'Industry',
    'Symbol',
    'Qty',
    'Current Value',
    'P/L %',
    'Price Range',
    'Trend',
    'Signal',
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
      // Reuse post-login Yahoo warm if in flight / already done.
      await provider.ensureYahooWarmed();
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
      case 'Account':
        return 120;
      case 'Current Value':
        return 120;
      case 'Buy Price':
      case 'Current':
      case 'P/L':
      case 'High':
      case 'Low':
      case 'Last Actioned':
        return 120;
      case 'P/L %':
        return 80;
      case 'Industry':
        return 160;
      case 'Signal':
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
            title: const AppBrandTitle('Stocks'),
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
                IconButton(
                  tooltip: 'Configure',
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

              final stocks = _filteredAndSortedStocks(
                provider,
                sortBySymbol: !showTableView,
              );
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
      _selectedIndustry != null ||
      _selectedMarketCap != null ||
      _selectedSource != null ||
      _selectedRecommendation != null ||
      _onlyStocksToAction;

  void _clearFilters() {
    setState(() {
      _selectedIndustry = null;
      _selectedMarketCap = null;
      _selectedSource = null;
      _selectedRecommendation = null;
      _onlyStocksToAction = false;
    });
  }

  String _stockRowKey(Stock stock) => '${stock.id}|${stock.source}';

  String _industryKey(Stock stock) =>
      stock.industry.isNotEmpty ? stock.industry : _unspecified;

  String _marketCapKey(Stock stock) =>
      stock.marketCap.isNotEmpty ? stock.marketCap : _unspecified;

  String _sourceKey(Stock stock) =>
      stock.source.isNotEmpty ? stock.source : _unspecified;

  bool _isManualAddSource(Stock stock) =>
      stock.source.isEmpty || stock.source == _manualAddSource;

  List<String> _industryOptions(List<Stock> stocks) {
    final industries = stocks
        .map((s) => s.industry.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final hasUnspecified = stocks.any((s) => s.industry.trim().isEmpty);
    if (hasUnspecified) industries.add(_unspecified);
    return industries;
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
    final industryOptions = _industryOptions(provider.stocks);
    final sourceOptions = _sourceOptions(provider.stocks);
    final narrow = MediaQuery.sizeOf(context).width < _cardViewBreakpoint;
    final dropdownFilterCount = [
      _selectedIndustry,
      _selectedMarketCap,
      _selectedSource,
      _selectedRecommendation,
    ].whereType<String>().length;

    final industryMenu = _buildFilterMenu(
      label: 'Industry',
      selected: _selectedIndustry,
      options: industryOptions,
      onChanged: (next) => setState(() => _selectedIndustry = next),
    );
    final marketCapMenu = _buildFilterMenu(
      label: 'Market Cap',
      selected: _selectedMarketCap,
      options: _marketCapOptions,
      onChanged: (next) => setState(() => _selectedMarketCap = next),
    );
    final accountMenu = _buildFilterMenu(
      label: 'Account',
      selected: _selectedSource,
      options: sourceOptions,
      onChanged: (next) => setState(() => _selectedSource = next),
    );
    final recommendationMenu = _buildFilterMenu(
      label: 'Signal',
      selected: _selectedRecommendation,
      options: _recommendationOptions,
      onChanged: (next) => setState(() => _selectedRecommendation = next),
    );
    final actionChip = FilterChip(
      avatar: Icon(
        _onlyStocksToAction
            ? Icons.check_box
            : Icons.check_box_outline_blank,
        size: 18,
      ),
      showCheckmark: false,
      label: const Text('Only Stocks to Action'),
      selected: _onlyStocksToAction,
      onSelected: (value) => setState(() {
        _onlyStocksToAction = value;
      }),
    );
    final clearButton = _hasActiveFilters
        ? TextButton(
            onPressed: _clearFilters,
            child: const Text('Clear'),
          )
        : null;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: narrow
            ? Row(
                children: [
                  _buildCollapsedFiltersButton(
                    activeCount: dropdownFilterCount,
                    onPressed: () => _showCollapsedFiltersSheet(
                      industryOptions: industryOptions,
                      sourceOptions: sourceOptions,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: actionChip,
                    ),
                  ),
                  if (clearButton != null) clearButton,
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  industryMenu,
                  marketCapMenu,
                  accountMenu,
                  recommendationMenu,
                  actionChip,
                  if (clearButton != null) clearButton,
                ],
              ),
      ),
    );
  }

  Widget _buildCollapsedFiltersButton({
    required int activeCount,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = activeCount > 0;
    return IconButton(
      tooltip: active ? 'Filters ($activeCount)' : 'Filters',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: active ? colorScheme.primary : colorScheme.onSurface,
        side: BorderSide(
          color: active ? colorScheme.primary : colorScheme.outline,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      icon: Badge(
        isLabelVisible: active,
        label: Text('$activeCount'),
        child: const Icon(Icons.filter_list),
      ),
    );
  }

  Future<void> _showCollapsedFiltersSheet({
    required List<String> industryOptions,
    required List<String> sourceOptions,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void apply(VoidCallback update) {
              setState(update);
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Filters',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _buildFilterMenu(
                        label: 'Industry',
                        selected: _selectedIndustry,
                        options: industryOptions,
                        onChanged: (next) =>
                            apply(() => _selectedIndustry = next),
                      ),
                      const SizedBox(height: 8),
                      _buildFilterMenu(
                        label: 'Market Cap',
                        selected: _selectedMarketCap,
                        options: _marketCapOptions,
                        onChanged: (next) =>
                            apply(() => _selectedMarketCap = next),
                      ),
                      const SizedBox(height: 8),
                      _buildFilterMenu(
                        label: 'Account',
                        selected: _selectedSource,
                        options: sourceOptions,
                        onChanged: (next) =>
                            apply(() => _selectedSource = next),
                      ),
                      const SizedBox(height: 8),
                      _buildFilterMenu(
                        label: 'Signal',
                        selected: _selectedRecommendation,
                        options: _recommendationOptions,
                        onChanged: (next) =>
                            apply(() => _selectedRecommendation = next),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterMenu({
    required String label,
    required String? selected,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final active = selected != null;
    final buttonLabel = active ? '$label: $selected' : label;
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Filter by $label',
      onSelected: (value) {
        onChanged(selected == value ? null : value);
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
                checked: selected == option,
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
              overflow: TextOverflow.ellipsis,
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

  List<Stock> _filteredAndSortedStocks(
    FinanceProvider provider, {
    bool sortBySymbol = false,
  }) {
    final filtered = provider.stocks.where((stock) {
      if (_selectedIndustry != null &&
          _industryKey(stock) != _selectedIndustry) {
        return false;
      }
      if (_selectedMarketCap != null &&
          _marketCapKey(stock) != _selectedMarketCap) {
        return false;
      }
      if (_selectedSource != null && _sourceKey(stock) != _selectedSource) {
        return false;
      }
      final recommendation =
          _getRecommendation(stock, _trendFor(stock, provider));
      if (_selectedRecommendation != null) {
        final label = _selectedRecommendation!;
        final matches = label == 'NO ACTION REQD' ||
                label == 'AT BUY PRICE' ||
                label == 'AT SELL PRICE' ||
                label == 'AT HOLD PRICE'
            ? recommendation == label
            : recommendation.contains(label);
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
    return _sortedStocks(filtered, provider, sortBySymbol: sortBySymbol);
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

  Widget _buildRecommendationBadge(String recommendation,
      {StockTrend? trend, bool showDetails = true}) {
    final color = _recommendationColor(recommendation);
    final isDefault = recommendation == 'NO ACTION REQD' ||
        recommendation == 'AT BUY PRICE' ||
        recommendation == 'AT SELL PRICE' ||
        recommendation == 'AT HOLD PRICE';
    final badge = Container(
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
    );
    if (!showDetails || isDefault || trend == null) {
      return badge;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        badge,
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
    final industryLine = _cardIndustryMarketCapLine(stock);

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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        if (stock.name.isNotEmpty)
                          Text(
                            stock.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        if (industryLine != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            industryLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _buildCardActionButtons(stock, provider),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildCardRecommendationTrendRow(
              recommendation: recommendation,
              trend: trend,
            ),
            if (stock.sixthHighestPrice > 0 && stock.sixthLowestPrice > 0) ...[
              const Divider(height: 16),
              _buildPriceRangeBar(stock),
            ],
            const SizedBox(height: 12),
            _buildCardMetricsBlock(
              narrow: narrowCard,
              children: [
                _buildCompactInfoColumn(
                  'Quantity',
                  stock.quantity.toStringAsFixed(2),
                ),
                _buildCompactInfoColumn(
                  'Buy Price',
                  formatInr(stock.buyPrice),
                ),
                _buildCompactInfoColumn(
                  'Current',
                  formatInr(stock.currentPrice),
                ),
                _buildCompactInfoColumn(
                  'Current Value',
                  formatInr(current),
                ),
                _buildCompactInfoColumn(
                  'P/L',
                  formatInr(profitLoss),
                  profitLoss >= 0 ? Colors.green : Colors.red,
                ),
                _buildCompactInfoColumn(
                  'P/L %',
                  '${profitLossPercentage.toStringAsFixed(2)}%',
                  profitLoss >= 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
            if (trend != null &&
                (trend.ma7 > 0 || trend.ma20 > 0 || trend.ma50 > 0)) ...[
              const Divider(height: 20),
              Row(
                children: [
                  if (trend.ma7 > 0)
                    Expanded(
                      child: _buildCompactInfoColumn(
                        '7-DMA',
                        formatInr(trend.ma7),
                      ),
                    ),
                  if (trend.ma7 > 0 && trend.ma20 > 0)
                    const SizedBox(width: 8),
                  if (trend.ma20 > 0)
                    Expanded(
                      child: _buildCompactInfoColumn(
                        '20-DMA',
                        formatInr(trend.ma20),
                      ),
                    ),
                  if (trend.ma20 > 0 && trend.ma50 > 0)
                    const SizedBox(width: 8),
                  if (trend.ma50 > 0)
                    Expanded(
                      child: _buildCompactInfoColumn(
                        '50-DMA',
                        formatInr(trend.ma50),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (trend.ma20 > 0 && trend.ma50 > 0)
                _buildCardMetricsBlock(
                  narrow: narrowCard,
                  children: [
                    _buildCompactInfoColumn(
                      'Stock ST Δ',
                      '${trend.stockSTDelta.toStringAsFixed(2)}%',
                      trend.stockSTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    _buildCompactInfoColumn(
                      'Sensex ST Δ',
                      '${trend.marketSTDelta.toStringAsFixed(2)}%',
                      trend.marketSTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    _buildCompactInfoColumn(
                      'Adj ST Δ',
                      '${trend.adjustedSTDelta.toStringAsFixed(2)}%',
                      trend.adjustedSTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    _buildCompactInfoColumn(
                      'Stock MT Δ',
                      '${trend.stockMTDelta.toStringAsFixed(2)}%',
                      trend.stockMTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    _buildCompactInfoColumn(
                      'Sensex MT Δ',
                      '${trend.marketMTDelta.toStringAsFixed(2)}%',
                      trend.marketMTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    _buildCompactInfoColumn(
                      'Adj MT Δ',
                      '${trend.adjustedMTDelta.toStringAsFixed(2)}%',
                      trend.adjustedMTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _buildCompactInfoColumn(
                        'Stock ST Δ',
                        '${trend.stockSTDelta.toStringAsFixed(2)}%',
                        trend.stockSTDelta >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCompactInfoColumn(
                        'Sensex ST Δ',
                        '${trend.marketSTDelta.toStringAsFixed(2)}%',
                        trend.marketSTDelta >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCompactInfoColumn(
                        'Adj ST Δ',
                        '${trend.adjustedSTDelta.toStringAsFixed(2)}%',
                        trend.adjustedSTDelta >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
            ],
            const Divider(height: 20),
            _buildInfoColumnWidget('News', _buildNewsTeaser(stock)),
          ],
        ),
      ),
    );
  }

  Widget _buildCardActionButtons(Stock stock, FinanceProvider provider) {
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
          onPressed: () => _showBuySellDialog(stock, provider, isBuy: true),
          style: letterStyle(Colors.green.shade700),
          child: const Text('B'),
        ),
        TextButton(
          onPressed: stock.quantity > 0
              ? () => _showBuySellDialog(stock, provider, isBuy: false)
              : null,
          style: letterStyle(Colors.orange.shade800),
          child: const Text('S'),
        ),
        TextButton(
          onPressed: stock.currentPrice > 0
              ? () => _showHoldDialog(stock, provider)
              : null,
          style: letterStyle(Colors.indigo.shade700),
          child: const Text('H'),
        ),
        TextButton(
          onPressed: () => _showThresholdsDialog(stock, provider),
          style: letterStyle(Colors.teal.shade800),
          child: const Text('T'),
        ),
        if (_isManualAddSource(stock))
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => _openEditStock(stock),
            style: iconStyle,
          ),
        IconButton(
          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
          onPressed: () => _showDeleteDialog(context, stock, provider),
          style: iconStyle,
        ),
      ],
    );
  }

  String? _cardIndustryMarketCapLine(Stock stock) {
    final industry = stock.industry.trim();
    final marketCap = stock.marketCap.trim();
    if (industry.isEmpty && marketCap.isEmpty) return null;
    if (industry.isEmpty) return '($marketCap)';
    if (marketCap.isEmpty) return industry;
    return '$industry ($marketCap)';
  }

  Widget _buildCardRecommendationTrendRow({
    required String recommendation,
    required StockTrend? trend,
  }) {
    const labelStyle = TextStyle(
      fontSize: 11,
      color: Colors.grey,
      fontWeight: FontWeight.w500,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('Signal', style: labelStyle),
        const SizedBox(width: 8),
        Flexible(
          child: _buildRecommendationBadge(
            recommendation,
            trend: trend,
            showDetails: false,
          ),
        ),
        const SizedBox(width: 8),
        if (trend != null)
          _buildTrendBadge(trend.trend)
        else
          Text('-', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  /// Wide: one row of six. Narrow: two rows of three (no Wrap 2+1).
  Widget _buildCardMetricsBlock({
    required bool narrow,
    required List<Widget> children,
  }) {
    assert(children.length == 6);
    Widget rowOfThree(List<Widget> trio) {
      return Row(
        children: [
          for (var i = 0; i < trio.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: trio[i]),
          ],
        ],
      );
    }

    if (narrow) {
      return Column(
        children: [
          rowOfThree(children.sublist(0, 3)),
          const SizedBox(height: 10),
          rowOfThree(children.sublist(3, 6)),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
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
    final frozenColumns = _frozenColumnNames
        .where((column) => _selectedColumns.contains(column))
        .toList();
    final scrollableColumns = _allColumns
        .where((column) =>
            _selectedColumns.contains(column) &&
            !_frozenColumnNames.contains(column))
        .toList();
    final headerColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final borderColor = Theme.of(context).dividerColor;
    final minScrollableWidth = scrollableColumns.fold<double>(
      0,
      (sum, column) => sum + _columnWidth(column),
    );
    final frozenWidth = frozenColumns.fold<double>(
      0,
      (sum, column) => sum + _columnWidth(column),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableScrollableWidth =
            (constraints.maxWidth - frozenWidth).clamp(0.0, double.infinity);
        final needsHorizontalScroll =
            minScrollableWidth > availableScrollableWidth + 0.5;
        final contentWidth = needsHorizontalScroll
            ? minScrollableWidth
            : availableScrollableWidth;
        final stretchFactor = minScrollableWidth > 0 && !needsHorizontalScroll
            ? availableScrollableWidth / minScrollableWidth
            : 1.0;

        double widthFor(String column) => _columnWidth(column) * stretchFactor;

        final horizontalPhysics = needsHorizontalScroll
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics();

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
                    if (frozenColumns.isNotEmpty)
                      Row(
                        children: frozenColumns
                            .map((column) => _buildHeaderCell(
                                  column,
                                  width: _columnWidth(column),
                                  frozen: true,
                                  headerColor: headerColor,
                                  borderColor: borderColor,
                                ))
                            .toList(),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontalHeaderController,
                        scrollDirection: Axis.horizontal,
                        physics: horizontalPhysics,
                        child: SizedBox(
                          width: contentWidth,
                          child: Row(
                            children: scrollableColumns
                                .map((column) => _buildHeaderCell(
                                      column,
                                      width: widthFor(column),
                                      borderColor: borderColor,
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (frozenColumns.isNotEmpty)
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
                        width: frozenWidth,
                        child: ListView.builder(
                          controller: _verticalFrozenController,
                          itemCount: stocks.length,
                          itemExtent: _rowHeight,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemBuilder: (context, index) {
                            return _buildFrozenRow(
                              stocks[index],
                              provider,
                              borderColor,
                              index.isEven,
                              frozenColumns,
                            );
                          },
                        ),
                      ),
                    ),
                  Expanded(
                    child: Scrollbar(
                      controller: _horizontalBodyController,
                      thumbVisibility: needsHorizontalScroll,
                      trackVisibility: needsHorizontalScroll,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      child: SingleChildScrollView(
                        controller: _horizontalBodyController,
                        scrollDirection: Axis.horizontal,
                        physics: horizontalPhysics,
                        child: SizedBox(
                          width: contentWidth,
                          child: RefreshIndicator(
                            onRefresh: () => provider.refreshStockPrices(),
                            child: Scrollbar(
                              controller: _verticalBodyController,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _verticalBodyController,
                                itemCount: stocks.length,
                                itemExtent: _rowHeight,
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemBuilder: (context, index) {
                                  final stock = stocks[index];
                                  final invested =
                                      stock.buyPrice * stock.quantity;
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
                                          ? Theme.of(context)
                                              .colorScheme
                                              .surface
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
                                                width: widthFor(column),
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
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
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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

  Widget _buildFrozenRow(
    Stock stock,
    FinanceProvider provider,
    Color borderColor,
    bool isEven,
    List<String> frozenColumns,
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
      child: Row(
        children: frozenColumns
            .map(
              (column) => SizedBox(
                width: _columnWidth(column),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildCellWidget(
                      column,
                      stock,
                      0,
                      0,
                      null,
                      '',
                      provider,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                stock.symbol,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (stock.source.isNotEmpty)
                Text(
                  stock.source,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        );
      case 'Qty':
        return Text(stock.quantity.toStringAsFixed(2));
      case 'Account':
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
      case 'Industry':
        return _buildIndustryWithMarketCap(stock);
      case 'Trend':
        return trend != null
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _buildTrendBadge(trend.trend),
              )
            : const Text('-');
      case 'Signal':
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
      case 'High':
        return Text(
          stock.sixthHighestPrice > 0
              ? formatInr(stock.sixthHighestPrice)
              : '-',
          style: const TextStyle(color: Colors.orange),
        );
      case 'Low':
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
              onPressed: () => _showDeleteDialog(context, stock, provider),
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
            'No data',
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
    return _infoColumn(
      label: label,
      value: value,
      valueColor: valueColor,
    );
  }

  Widget _buildCompactInfoColumn(String label, String value,
      [Color? valueColor]) {
    return _infoColumn(
      label: label,
      value: value,
      valueColor: valueColor,
      compact: true,
    );
  }

  Widget _infoColumn({
    required String label,
    required String value,
    Color? valueColor,
    bool compact = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: compact ? 10 : 12,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 12 : 14,
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

  /// Industry with market-cap letter, e.g. Oil & Gas(L). Tooltip on L/M/S.
  Widget _buildIndustryWithMarketCap(Stock stock) {
    const style = TextStyle(color: Colors.blue);
    final industry = stock.industry.trim();
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

    if (industry.isEmpty && letter.isEmpty) {
      return const Text('-', style: style);
    }
    if (letter.isEmpty) {
      return Text(
        industry.isEmpty ? '-' : industry,
        style: style,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (industry.isNotEmpty) TextSpan(text: industry),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Tooltip(
          message: 'High and Low used to remove spikes',
          waitDuration: Duration(milliseconds: 300),
          child: Text(
            'Price Range*',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildCompactPriceRangeBar(stock),
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
    if (!mounted) return;
    await context.read<FinanceProvider>().loadStocks();
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
                Text('Account: $sourceLabel',
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
            Text('Account: $sourceLabel',
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
                      Text('Account: $sourceLabel',
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
      BuildContext context, Stock stock, FinanceProvider provider) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Stock'),
        content: Text(
          'Remove ${stock.symbol} from your holdings'
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
              final source =
                  stock.source.trim().isEmpty ? _manualAddSource : stock.source;
              final ok = await provider.deleteStock(stock.id, source: source);
              if (!context.mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(provider.error ?? 'Failed to delete stock'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadColumnPreferences() async {
    try {
      final raw = await ApiService.getHiddenStockColumns();
      final hasV2 = raw.contains(_columnDefaultsV2Sentinel);
      final hidden = <String>{
        ..._normalizeHiddenColumns(raw),
        if (!hasV2) ..._defaultHiddenColumns,
      }.toList();
      if (!mounted) return;
      setState(() {
        _selectedColumns
          ..clear()
          ..addAll(_allColumns.where((c) => !hidden.contains(c)));
        if (_selectedColumns.isEmpty) {
          _selectedColumns.addAll(_defaultSelectedColumns);
        }
      });
      if (!hasV2) {
        // Persist migrated hide-set + sentinel so this does not re-run.
        await _saveColumnPreferences();
      }
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
        case 'Source':
          // Renamed to Account; preserve hidden preference.
          out.add('Account');
          break;
        case 'Sector':
          // Renamed to Industry; preserve hidden preference.
          out.add('Industry');
          break;
        case 'Recommendation':
          out.add('Signal');
          break;
        case '6th High':
          out.add('High');
          break;
        case '6th Low':
          out.add('Low');
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
    final hidden = [
      ..._allColumns.where((c) => !_selectedColumns.contains(c)),
      _columnDefaultsV2Sentinel,
    ];
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

  List<Stock> _sortedStocks(
    List<Stock> input,
    FinanceProvider provider, {
    bool sortBySymbol = false,
  }) {
    final stocks = List<Stock>.from(input);
    if (sortBySymbol) {
      stocks.sort(
        (a, b) => a.symbol.toLowerCase().compareTo(b.symbol.toLowerCase()),
      );
    } else if (_sortColumn == null) {
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
    final industryCmp = _compareEmptyLast(a.industry, b.industry);
    if (industryCmp != 0) return industryCmp;

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
      case 'Account':
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
      case 'Industry':
        return _compareEmptyLast(a.industry, b.industry);
      case 'Signal':
        return _getRecommendation(a, _trendFor(a, provider))
            .compareTo(_getRecommendation(b, _trendFor(b, provider)));
      case 'Price Range':
        return _priceRangeSortKey(a).compareTo(_priceRangeSortKey(b));
      case 'High':
        return a.sixthHighestPrice.compareTo(b.sixthHighestPrice);
      case 'Low':
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
