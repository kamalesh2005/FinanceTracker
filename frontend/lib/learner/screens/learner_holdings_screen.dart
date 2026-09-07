import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/stock.dart';
import '../../models/stock_trend.dart';
import '../../providers/auth_provider.dart';
import '../../services/recommendation_engine.dart';
import '../learner_api.dart';
import '../learner_provider.dart';
import '../learner_theme.dart';
import '../widgets/learner_stock_card.dart';
import '../widgets/learner_stock_table.dart';
import '../../utils/screen_tracker.dart';
import 'learner_thresholds_screen.dart';
import 'learner_trade_screen.dart';

class LearnerHoldingsScreen extends StatefulWidget {
  final int challengeId;

  const LearnerHoldingsScreen({super.key, required this.challengeId});

  @override
  State<LearnerHoldingsScreen> createState() => _LearnerHoldingsScreenState();
}

class _LearnerHoldingsScreenState extends State<LearnerHoldingsScreen> {
  bool _isTableView = true;
  bool _refreshing = false;

  String? _selectedIndustry;
  String? _selectedMarketCap;
  String? _selectedRecommendation;
  String? _selectedTrend;
  bool _onlyStocksToAction = true;

  static const _unspecified = 'Unspecified';
  static const _cardViewBreakpoint = 700.0;
  static const _marketCapOptions = [
    'Large Cap',
    'Mid Cap',
    'Small Cap',
    _unspecified,
  ];
  static const _recommendationOptions = [
    'Book Profit',
    'BUY',
    'SELL',
    'Review',
    'AT BUY PRICE',
    'AT SELL PRICE',
    'AT HOLD PRICE',
    'NO ACTION REQD',
  ];
  static const _actionableRecommendations = [
    'Book Profit',
    'BUY',
    'SELL',
    'Review',
  ];
  static const _nonActionRecommendations = [
    'NO ACTION REQD',
    'AT BUY PRICE',
    'AT SELL PRICE',
    'AT HOLD PRICE',
  ];
  static const _trendOptions = [
    'bullish',
    'moderately bullish',
    'bearish_st',
    'moderately bearish_st',
    'bearish_lt',
    'moderately bearish_lt',
    'neutral',
  ];

  String _signal(Stock s, StockTrend? trend) {
    final auth = context.read<AuthProvider>();
    return RecommendationEngine.evaluate(
      s,
      trend,
      auth.effectiveRecommendationRules,
    );
  }

  Future<void> _refreshPrices() async {
    setState(() => _refreshing = true);
    try {
      await LearnerApi.refreshPrices(widget.challengeId);
      if (!mounted) return;
      await context.read<LearnerProvider>().openChallenge(widget.challengeId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  bool get _hasActiveFilters =>
      _selectedIndustry != null ||
      _selectedMarketCap != null ||
      _selectedRecommendation != null ||
      _selectedTrend != null ||
      _onlyStocksToAction;

  void _clearFilters() {
    setState(() {
      _selectedIndustry = null;
      _selectedMarketCap = null;
      _selectedRecommendation = null;
      _selectedTrend = null;
      _onlyStocksToAction = false;
    });
  }

  String _industryKey(Stock stock) =>
      stock.industry.isNotEmpty ? stock.industry : _unspecified;

  String _marketCapKey(Stock stock) =>
      stock.marketCap.isNotEmpty ? stock.marketCap : _unspecified;

  String? _trendFilterKey(String? trend) {
    if (trend == null || trend.isEmpty) return 'neutral';
    return trend;
  }

  List<String> _industryOptions(List<Stock> stocks) {
    final industries = stocks
        .map((s) => s.industry.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (stocks.any((s) => s.industry.trim().isEmpty)) {
      industries.add(_unspecified);
    }
    return industries;
  }

  List<Stock> _filteredStocks(LearnerProvider provider) {
    final showZero = context.read<AuthProvider>().showZeroQuantityStocks;
    var rows = provider.holdings.where((stock) {
      if (!showZero && stock.quantity <= 0) return false;
      if (_selectedIndustry != null &&
          _industryKey(stock) != _selectedIndustry) {
        return false;
      }
      if (_selectedMarketCap != null &&
          _marketCapKey(stock) != _selectedMarketCap) {
        return false;
      }
      final trend = provider.trendFor(stock.id);
      final recommendation = _signal(stock, trend);
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
      if (_selectedTrend != null) {
        if (_trendFilterKey(trend?.trend) != _selectedTrend) return false;
      }
      if (_onlyStocksToAction) {
        if (_nonActionRecommendations.contains(recommendation)) return false;
        if (!_actionableRecommendations.any(recommendation.contains)) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) => a.symbol.compareTo(b.symbol));
    return rows;
  }

  Widget _buildFilterMenu({
    required String label,
    required String? selected,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String Function(String)? optionLabel,
  }) {
    final active = selected != null;
    final selectedText =
        selected == null ? '' : (optionLabel?.call(selected) ?? selected);
    final buttonLabel = active ? '$label: $selectedText' : label;
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Filter by $label',
      onSelected: (value) => onChanged(selected == value ? null : value),
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
                child: Text(optionLabel?.call(option) ?? option),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: Badge(
        isLabelVisible: active,
        label: Text('$activeCount'),
        child: const Icon(Icons.filter_list),
      ),
    );
  }

  Future<void> _showCollapsedFiltersSheet(List<String> industryOptions) async {
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
                        label: 'Signal',
                        selected: _selectedRecommendation,
                        options: _recommendationOptions,
                        onChanged: (next) =>
                            apply(() => _selectedRecommendation = next),
                      ),
                      const SizedBox(height: 8),
                      _buildFilterMenu(
                        label: 'Trend',
                        selected: _selectedTrend,
                        options: _trendOptions,
                        optionLabel: _trendDisplayLabel,
                        onChanged: (next) => apply(() => _selectedTrend = next),
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

  String _trendDisplayLabel(String trend) {
    switch (trend) {
      case 'bullish':
        return 'Bullish';
      case 'moderately bullish':
        return 'Mod. Bullish';
      case 'bearish_st':
        return 'Bearish ST';
      case 'moderately bearish_st':
        return 'Mod. Bearish ST';
      case 'bearish_lt':
        return 'Bearish LT';
      case 'moderately bearish_lt':
        return 'Mod. Bearish LT';
      default:
        return 'Neutral';
    }
  }

  Widget _buildFilterBar(List<Stock> listed) {
    final industryOptions = _industryOptions(listed);
    final narrow = MediaQuery.sizeOf(context).width < _cardViewBreakpoint;
    final dropdownFilterCount = [
      _selectedIndustry,
      _selectedMarketCap,
      _selectedRecommendation,
      _selectedTrend,
    ].whereType<String>().length;

    final actionChip = FilterChip(
      avatar: Icon(
        _onlyStocksToAction ? Icons.check_box : Icons.check_box_outline_blank,
        size: 18,
      ),
      showCheckmark: false,
      label: const Text('Only Stocks to Action'),
      selected: _onlyStocksToAction,
      onSelected: (value) => setState(() => _onlyStocksToAction = value),
    );
    final clearButton = _hasActiveFilters
        ? TextButton(onPressed: _clearFilters, child: const Text('Clear'))
        : null;
    final reviewButton = OutlinedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          appPageRoute(
            LearnerThresholdsScreen(
              challengeId: widget.challengeId,
            ),
          ),
        );
      },
      icon: const Icon(Icons.visibility_outlined, size: 18),
      label: const Text('Review Thresholds'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
    );

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: narrow
            ? Row(
                children: [
                  _buildCollapsedFiltersButton(
                    activeCount: dropdownFilterCount,
                    onPressed: () =>
                        _showCollapsedFiltersSheet(industryOptions),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: actionChip,
                    ),
                  ),
                  if (clearButton != null) clearButton,
                  reviewButton,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildFilterMenu(
                          label: 'Industry',
                          selected: _selectedIndustry,
                          options: industryOptions,
                          onChanged: (next) =>
                              setState(() => _selectedIndustry = next),
                        ),
                        _buildFilterMenu(
                          label: 'Market Cap',
                          selected: _selectedMarketCap,
                          options: _marketCapOptions,
                          onChanged: (next) =>
                              setState(() => _selectedMarketCap = next),
                        ),
                        _buildFilterMenu(
                          label: 'Signal',
                          selected: _selectedRecommendation,
                          options: _recommendationOptions,
                          onChanged: (next) =>
                              setState(() => _selectedRecommendation = next),
                        ),
                        _buildFilterMenu(
                          label: 'Trend',
                          selected: _selectedTrend,
                          options: _trendOptions,
                          optionLabel: _trendDisplayLabel,
                          onChanged: (next) =>
                              setState(() => _selectedTrend = next),
                        ),
                        actionChip,
                        if (clearButton != null) clearButton,
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  reviewButton,
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LearnerProvider>();
    final tradingOpen = provider.detail?.tradingOpen ?? false;
    final challengeName = provider.detail?.name ?? 'Challenge';
    final listed = provider.holdings;
    final stocks = _filteredStocks(provider);
    final width = MediaQuery.sizeOf(context).width;
    final canToggleView = width >= _cardViewBreakpoint;
    final showTableView = canToggleView && _isTableView;

    return wrapLearnerPage(
      Scaffold(
        appBar: AppBar(
          title: learnerBrandTitle(
            context,
            'LP : $challengeName : Stock Holdings',
          ),
          actions: learnerAppBarActions(
            context,
            extra: [
              if (canToggleView)
                IconButton(
                  icon: Icon(
                    showTableView ? Icons.view_module : Icons.table_rows,
                  ),
                  onPressed: () => setState(() => _isTableView = !_isTableView),
                  tooltip: showTableView ? 'Card view' : 'Table view',
                ),
              IconButton(
                tooltip: 'Refresh prices',
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _refreshing ? null : _refreshPrices,
              ),
            ],
          ),
        ),
        floatingActionButton: tradingOpen
            ? FloatingActionButton.extended(
                onPressed: () {
                  Navigator.push(
                    context,
                    appPageRoute(
                      LearnerTradeScreen(
                        challengeId: widget.challengeId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Trade'),
              )
            : null,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFilterBar(listed),
            Expanded(
              child: stocks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _hasActiveFilters
                                ? 'No stocks match filters'
                                : 'No holdings in this challenge yet.',
                          ),
                          if (_hasActiveFilters) ...[
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
                      ? LearnerStockTable(
                          stocks: stocks,
                          challengeId: widget.challengeId,
                          tradingOpen: tradingOpen,
                          recommendationFor: (stock, trend) =>
                              _signal(stock, trend),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: stocks.length,
                          itemBuilder: (context, index) {
                            final stock = stocks[index];
                            final trend = provider.trendFor(stock.id);
                            return LearnerStockCard(
                              stock: stock,
                              challengeId: widget.challengeId,
                              tradingOpen: tradingOpen,
                              trend: trend,
                              recommendation: _signal(stock, trend),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
