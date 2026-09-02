import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/screener_stock.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import '../widgets/screener_stock_table.dart';
import '../utils/screen_tracker.dart';
import 'add_stock_screen.dart';
import 'stock_watchlist_screen.dart';

class StockScreenerScreen extends StatefulWidget {
  const StockScreenerScreen({super.key});

  @override
  State<StockScreenerScreen> createState() => _StockScreenerScreenState();
}

class _StockScreenerScreenState extends State<StockScreenerScreen>
    with ScreenerColumnController {
  static const List<String> _marketCapOptions = [
    'Large Cap',
    'Mid Cap',
    'Small Cap',
  ];
  static const List<String> _trendOptions = [
    'bullish',
    'moderately bullish',
    'bearish_st',
    'moderately bearish_st',
    'bearish_lt',
    'moderately bearish_lt',
    'neutral',
  ];
  static const Set<String> _defaultTrends = {
    'bullish',
    'moderately bullish',
  };
  static const Set<String> _defaultConsensusTypes = {
    'buy',
    'strong_buy',
  };
  static const String _defaultUpsideMin = '10';

  final _adjStMin = TextEditingController();
  final _adjMtMin = TextEditingController();
  final _upsideMin = TextEditingController(text: _defaultUpsideMin);
  final _nameLike = TextEditingController();

  final Set<String> _industriesSelected = {};
  final Set<String> _marketCaps = {};
  final Set<String> _trends = {..._defaultTrends};
  final Set<String> _consensusTypesSelected = {..._defaultConsensusTypes};
  final Set<String> _labelsSelected = ScreenerStock.defaultSelectedLabels();
  List<String> _industries = [];
  List<String> _consensusTypes = [];
  List<String> _labelOptions = [];

  List<ScreenerStock> _items = [];
  int _page = 1;
  int _total = 0;
  int _pageSize = 20;
  bool _hasSearched = false;
  bool _loading = false;
  bool _loadingOptions = true;
  String? _error;
  int? _busyStockId;

  @override
  void initState() {
    super.initState();
    _loadOptions();
    loadScreenerColumns();
  }

  @override
  void dispose() {
    _adjStMin.dispose();
    _adjMtMin.dispose();
    _upsideMin.dispose();
    _nameLike.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final opts = await ApiService.screenerOptions();
      if (!mounted) return;
      setState(() {
        _industries = opts.industries;
        _consensusTypes = opts.consensusTypes;
        _labelOptions = opts.labels;
        _applyDefaultLabelSelection();
        _loadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingOptions = false);
    }
  }

  void _applyDefaultLabelSelection() {
    for (final label in _labelOptions) {
      if (!ScreenerStock.isDefaultExcludedLabel(label)) {
        _labelsSelected.add(label);
      }
    }
  }

  Set<String> _defaultLabelSelection() {
    final out = ScreenerStock.defaultSelectedLabels();
    for (final label in _labelOptions) {
      if (!ScreenerStock.isDefaultExcludedLabel(label)) {
        out.add(label);
      }
    }
    return out;
  }

  bool get _labelsFilterIsDefault {
    final defaults = _defaultLabelSelection();
    return _sameSet(_labelsSelected, defaults);
  }

  bool get _trendsFilterIsDefault => _sameSet(_trends, _defaultTrends);

  bool get _consensusFilterIsDefault =>
      _sameSet(_consensusTypesSelected, _defaultConsensusTypes);

  bool get _upsideFilterIsDefault =>
      _upsideMin.text.trim() == _defaultUpsideMin;

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  List<String> get _labelFilterOptions => [
        ScreenerStock.unlabeledSentinel,
        ..._labelOptions,
      ];

  String _labelFilterLabel(String value) =>
      value == ScreenerStock.unlabeledSentinel
          ? ScreenerStock.unlabeledDisplay
          : value;

  Future<void> _search({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
      _hasSearched = true;
      _page = page;
    });
    try {
      final result = await ApiService.searchScreener(
        industries: _industriesSelected.toList(),
        marketCaps: _marketCaps.toList(),
        trends: _trends.toList(),
        consensusTypes: _consensusTypesSelected.toList(),
        labels: _labelsSelected.toList(),
        nameLike: _nameLike.text,
        adjStMin: _parseNum(_adjStMin.text),
        adjMtMin: _parseNum(_adjMtMin.text),
        consensusUpsideMin: _parseNum(_upsideMin.text),
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _total = result.total;
        _page = result.page;
        _pageSize = result.pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  double? _parseNum(String raw) => double.tryParse(raw.trim());

  Future<void> _addWatchlist(ScreenerStock stock) async {
    setState(() => _busyStockId = stock.id);
    try {
      await ApiService.addToWatchlist(stock.id);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((s) => s.id == stock.id ? s.copyWith(inWatchlist: true) : s)
            .toList();
        _busyStockId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${stock.symbol} added to WatchList')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyStockId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _removeWatchlist(ScreenerStock stock) async {
    setState(() => _busyStockId = stock.id);
    try {
      await ApiService.removeFromWatchlist(stock.id);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((s) => s.id == stock.id ? s.copyWith(inWatchlist: false) : s)
            .toList();
        _busyStockId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyStockId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _buy(ScreenerStock stock) async {
    await Navigator.push(
      context,
      appPageRoute(AddStockScreen(stock: stock.toBuyStock())),
    );
  }

  Future<void> _addLabel(ScreenerStock stock, String label) async {
    setState(() => _busyStockId = stock.id);
    try {
      final updated = await ApiService.addScreenerLabel(stock.id, label);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((s) => s.id == stock.id ? s.copyWith(labels: updated.labels) : s)
            .toList();
        _busyStockId = null;
        if (!_labelOptions.contains(label)) {
          _labelOptions = [..._labelOptions, label]..sort();
          if (!ScreenerStock.isDefaultExcludedLabel(label)) {
            _labelsSelected.add(label);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyStockId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _removeLabel(ScreenerStock stock, String label) async {
    setState(() => _busyStockId = stock.id);
    try {
      await ApiService.removeScreenerLabel(stock.id, label);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((s) => s.id == stock.id
                ? s.copyWith(
                    labels: s.labels.where((l) => l != label).toList(),
                  )
                : s)
            .toList();
        _busyStockId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyStockId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _openWatchlist() {
    Navigator.pushReplacement(
      context,
      appPageRoute(const StockWatchlistScreen()),
    );
  }

  int get _lastPage {
    if (_total <= 0) return 1;
    return ((_total - 1) ~/ _pageSize) + 1;
  }

  bool get _hasActiveFilters =>
      _industriesSelected.isNotEmpty ||
      _marketCaps.isNotEmpty ||
      !_trendsFilterIsDefault ||
      !_consensusFilterIsDefault ||
      !_labelsFilterIsDefault ||
      _adjStMin.text.trim().isNotEmpty ||
      _adjMtMin.text.trim().isNotEmpty ||
      !_upsideFilterIsDefault ||
      _nameLike.text.trim().isNotEmpty;

  int get _activeFilterCount => [
        _industriesSelected.isNotEmpty,
        _marketCaps.isNotEmpty,
        !_trendsFilterIsDefault,
        !_consensusFilterIsDefault,
        !_labelsFilterIsDefault,
        _adjStMin.text.trim().isNotEmpty,
        _adjMtMin.text.trim().isNotEmpty,
        !_upsideFilterIsDefault,
        _nameLike.text.trim().isNotEmpty,
      ].where((active) => active).length;

  void _clearFilters() {
    setState(() {
      _industriesSelected.clear();
      _marketCaps.clear();
      _trends
        ..clear()
        ..addAll(_defaultTrends);
      _consensusTypesSelected
        ..clear()
        ..addAll(_defaultConsensusTypes);
      _labelsSelected
        ..clear()
        ..addAll(_defaultLabelSelection());
      _adjStMin.clear();
      _adjMtMin.clear();
      _upsideMin.text = _defaultUpsideMin;
      _nameLike.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final showTableView = MediaQuery.sizeOf(context).width >=
        ScreenerStockTable.cardViewBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Evaluate Stocks to Buy'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            if (showTableView)
              IconButton(
                icon: const Icon(Icons.view_column),
                tooltip: 'Columns',
                onPressed: showScreenerColumnDialog,
              ),
            TextButton(
              onPressed: _openWatchlist,
              child: const Text('WatchList'),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ScreenerDataDisclaimer(),
            const SizedBox(height: 12),
            _buildFilters(),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final narrow = MediaQuery.sizeOf(context).width <
        ScreenerStockTable.cardViewBreakpoint;
    if (narrow) {
      return _buildNarrowFilters();
    }
    return _buildWideFilters();
  }

  Widget _buildWideFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: _wideFilterChildren(includeSearch: true),
    );
  }

  List<Widget> _wideFilterChildren({required bool includeSearch}) {
    return [
      _filterMenu(
        label: 'Industry',
        selected: _industriesSelected,
        options: _industries,
      ),
      _filterMenu(
        label: 'Market Cap',
        selected: _marketCaps,
        options: _marketCapOptions,
      ),
      _filterMenu(
        label: 'Trend',
        selected: _trends,
        options: _trendOptions,
        optionLabel: ScreenerStockTable.trendLabel,
      ),
      _gtField('Adj ST', _adjStMin),
      _gtField('Adj MT', _adjMtMin),
      _gtField('Upside', _upsideMin),
      _filterMenu(
        label: 'Consensus',
        selected: _consensusTypesSelected,
        options: _consensusTypes,
        optionLabel: ScreenerStockTable.consensusLabel,
      ),
      _filterMenu(
        label: 'Labels',
        selected: _labelsSelected,
        options: _labelFilterOptions,
        optionLabel: _labelFilterLabel,
      ),
      _nameLikeField(),
      if (_loadingOptions)
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      if (includeSearch)
        FilledButton.icon(
          onPressed: _loading ? null : () => _search(page: 1),
          icon: const Icon(Icons.search),
          label: const Text('Search'),
        ),
      if (includeSearch && _hasActiveFilters)
        TextButton(
          onPressed: _clearFilters,
          child: const Text('Clear'),
        ),
    ];
  }

  Widget _buildNarrowFilters() {
    final clearButton = _hasActiveFilters
        ? TextButton(
            onPressed: _clearFilters,
            child: const Text('Clear'),
          )
        : null;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            _buildCollapsedFiltersButton(
              activeCount: _activeFilterCount,
              onPressed: _showCollapsedFiltersSheet,
            ),
            if (_loadingOptions) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            const Spacer(),
            if (clearButton != null) clearButton,
            FilledButton.icon(
              onPressed: _loading ? null : () => _search(page: 1),
              icon: const Icon(Icons.search),
              label: const Text('Search'),
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

  Future<void> _showCollapsedFiltersSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget sheetFilterMenu({
              required String label,
              required Set<String> selected,
              required List<String> options,
              String Function(String)? optionLabel,
            }) {
              return _filterMenu(
                label: label,
                selected: selected,
                options: options,
                optionLabel: optionLabel,
                onUpdated: () => setSheetState(() {}),
              );
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
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 12),
                      sheetFilterMenu(
                        label: 'Industry',
                        selected: _industriesSelected,
                        options: _industries,
                      ),
                      const SizedBox(height: 8),
                      sheetFilterMenu(
                        label: 'Market Cap',
                        selected: _marketCaps,
                        options: _marketCapOptions,
                      ),
                      const SizedBox(height: 8),
                      sheetFilterMenu(
                        label: 'Trend',
                        selected: _trends,
                        options: _trendOptions,
                        optionLabel: ScreenerStockTable.trendLabel,
                      ),
                      const SizedBox(height: 8),
                      _gtField(
                        'Adj ST',
                        _adjStMin,
                        onChanged: () => setSheetState(() {}),
                      ),
                      const SizedBox(height: 8),
                      _gtField(
                        'Adj MT',
                        _adjMtMin,
                        onChanged: () => setSheetState(() {}),
                      ),
                      const SizedBox(height: 8),
                      _gtField(
                        'Upside',
                        _upsideMin,
                        onChanged: () => setSheetState(() {}),
                      ),
                      const SizedBox(height: 8),
                      sheetFilterMenu(
                        label: 'Consensus',
                        selected: _consensusTypesSelected,
                        options: _consensusTypes,
                        optionLabel: ScreenerStockTable.consensusLabel,
                      ),
                      const SizedBox(height: 8),
                      sheetFilterMenu(
                        label: 'Labels',
                        selected: _labelsSelected,
                        options: _labelFilterOptions,
                        optionLabel: _labelFilterLabel,
                      ),
                      const SizedBox(height: 8),
                      _nameLikeField(
                        expanded: true,
                        onChanged: () => setSheetState(() {}),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (_hasActiveFilters)
                            TextButton(
                              onPressed: () {
                                _clearFilters();
                                setSheetState(() {});
                              },
                              child: const Text('Clear all'),
                            ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Done'),
                          ),
                        ],
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

  Widget _nameLikeField({
    VoidCallback? onChanged,
    bool expanded = false,
  }) {
    final field = TextField(
      controller: _nameLike,
      onChanged: (_) {
        setState(() {});
        onChanged?.call();
      },
      onSubmitted: (_) {
        if (!_loading) _search(page: 1);
      },
      decoration: const InputDecoration(
        labelText: 'Name like',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(),
      ),
    );
    if (expanded) return field;
    return SizedBox(width: 150, child: field);
  }

  Widget _gtField(
    String label,
    TextEditingController controller, {
    VoidCallback? onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('>'),
        ),
        _numField(controller, '', onChanged: onChanged),
      ],
    );
  }

  Widget _numField(
    TextEditingController controller,
    String hint, {
    VoidCallback? onChanged,
  }) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: controller,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
        ],
        onChanged: onChanged == null ? null : (_) => onChanged(),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _filterMenu({
    required String label,
    required Set<String> selected,
    required List<String> options,
    String Function(String)? optionLabel,
    VoidCallback? onUpdated,
  }) {
    final active = selected.isNotEmpty;
    final buttonLabel = _filterButtonLabel(label, selected, optionLabel);
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showMultiSelectDialog(
        label: label,
        selected: selected,
        options: options,
        optionLabel: optionLabel,
        onUpdated: onUpdated,
      ),
      borderRadius: BorderRadius.circular(20),
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                buttonLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? colorScheme.primary : colorScheme.onSurface,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
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

  String _filterButtonLabel(
    String label,
    Set<String> selected,
    String Function(String)? optionLabel,
  ) {
    if (selected.isEmpty) return label;
    if (selected.length == 1) {
      final value = selected.first;
      return '$label: ${optionLabel?.call(value) ?? value}';
    }
    return '$label: ${selected.length} selected';
  }

  void _showMultiSelectDialog({
    required String label,
    required Set<String> selected,
    required List<String> options,
    String Function(String)? optionLabel,
    VoidCallback? onUpdated,
  }) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(label),
          content: SizedBox(
            width: double.maxFinite,
            height: options.length > 8 ? 360 : null,
            child: options.isEmpty
                ? const Text('No options')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return CheckboxListTile(
                        title: Text(optionLabel?.call(option) ?? option),
                        value: selected.contains(option),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selected.add(option);
                            } else {
                              selected.remove(option);
                            }
                          });
                          setState(() {});
                          onUpdated?.call();
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(selected.clear);
                setState(() {});
                onUpdated?.call();
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () {
                onUpdated?.call();
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_hasSearched) {
      return const Center(
        child: Text('Set filters and click Search'),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No stocks match these filters'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ScreenerStockTable(
            stocks: _items,
            selectedColumns: selectedScreenerColumns,
            busyStockId: _busyStockId,
            labelOptions: _labelFilterOptions
                .where((l) => l != ScreenerStock.unlabeledSentinel)
                .toList(),
            onBuy: _buy,
            onAddWatchlist: _addWatchlist,
            onRemoveWatchlist: _removeWatchlist,
            onAddLabel: _addLabel,
            onRemoveLabel: _removeLabel,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              _total == 0
                  ? 'No results'
                  : 'Showing ${(_page - 1) * _pageSize + 1}–${(_page - 1) * _pageSize + _items.length} of $_total',
            ),
            const Spacer(),
            TextButton(
              onPressed: _page > 1 && !_loading
                  ? () => _search(page: _page - 1)
                  : null,
              child: const Text('Prev'),
            ),
            Text('Page $_page of $_lastPage'),
            TextButton(
              onPressed: _page < _lastPage && !_loading
                  ? () => _search(page: _page + 1)
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }
}
