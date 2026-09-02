import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../models/screener_stock.dart';
import '../services/api_service.dart';

class ScreenerDataDisclaimer extends StatelessWidget {
  const ScreenerDataDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: Colors.grey.shade700,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Data shown here — including target prices and consensus '
                'ratings — is based on publicly available online sources and '
                'is not directly sourced from analysts.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScreenerStockTable extends StatefulWidget {
  const ScreenerStockTable({
    super.key,
    required this.stocks,
    required this.selectedColumns,
    required this.onBuy,
    this.onAddWatchlist,
    this.onRemoveWatchlist,
    this.onAddLabel,
    this.onRemoveLabel,
    this.labelOptions = const [],
    this.busyStockId,
  });

  final List<ScreenerStock> stocks;
  final Set<String> selectedColumns;
  final ValueChanged<ScreenerStock> onBuy;
  final ValueChanged<ScreenerStock>? onAddWatchlist;
  final ValueChanged<ScreenerStock>? onRemoveWatchlist;
  final void Function(ScreenerStock stock, String label)? onAddLabel;
  final void Function(ScreenerStock stock, String label)? onRemoveLabel;
  final List<String> labelOptions;
  final int? busyStockId;

  static const double headerHeight = 48;
  static const double rowHeight = 72;
  static const String frozenColumn = 'Symbol';

  /// Below this width, use card layout (table is too dense for phones).
  static const double cardViewBreakpoint = 700;

  /// Below this width, stack card metric rows into groups of three.
  static const double narrowCardBreakpoint = 400;

  static const List<String> allColumns = [
    'Symbol',
    'Name',
    'Industry',
    'Market Cap',
    'Trend',
    'Adj ST',
    'Adj MT',
    'LTP',
    'DMA-7',
    'DMA-20',
    'DMA-50',
    'FY21',
    'FY22',
    'FY23',
    'FY24',
    'FY25',
    'FY26 YTD',
    'Target',
    'Upside',
    'Consensus',
    'News',
    'Labels',
    'Actions',
  ];

  static const Set<String> defaultHiddenColumns = {
    'DMA-7',
    'DMA-20',
    'DMA-50',
    'FY21',
    'FY22',
    'FY23',
    'FY24',
    'FY25',
    'FY26 YTD',
  };

  /// One-shot: hide FY columns for users who already saved screener prefs.
  static const String fyDefaultsSentinel = '__fy_defaults_v1';

  static final Set<String> defaultSelectedColumns = {
    ...allColumns.where((c) => !defaultHiddenColumns.contains(c)),
  };

  static double columnWidth(String column) {
    switch (column) {
      case 'Symbol':
        return 128;
      case 'Name':
        return 180;
      case 'Industry':
        return 160;
      case 'Labels':
        return 120;
      case 'Market Cap':
        return 110;
      case 'Trend':
        return 140;
      case 'Adj ST':
      case 'Adj MT':
      case 'FY21':
      case 'FY22':
      case 'FY23':
      case 'FY24':
      case 'FY25':
      case 'FY26 YTD':
        return 80;
      case 'LTP':
      case 'DMA-7':
      case 'DMA-20':
      case 'DMA-50':
      case 'Target':
        return 90;
      case 'Upside':
        return 108;
      case 'Consensus':
        return 110;
      case 'News':
        return 220;
      case 'Actions':
        return 210;
      default:
        return 120;
    }
  }

  static String trendLabel(String trend) {
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
      case 'neutral':
        return 'Neutral';
      default:
        return trend.trim().isEmpty ? '-' : trend;
    }
  }

  static String consensusLabel(String raw) {
    final label = raw.trim().replaceAll('_', ' ');
    if (label.isEmpty) return '-';
    return label.toUpperCase();
  }

  @override
  State<ScreenerStockTable> createState() => _ScreenerStockTableState();
}

mixin ScreenerColumnController<T extends StatefulWidget> on State<T> {
  final Set<String> selectedScreenerColumns = {
    ...ScreenerStockTable.defaultSelectedColumns,
  };

  Future<void> loadScreenerColumns() async {
    try {
      final raw = await ApiService.getHiddenScreenerColumns();
      final hasFyDefaults = raw.contains(ScreenerStockTable.fyDefaultsSentinel);
      final hidden = <String>{};
      for (final c in raw) {
        if (c == ScreenerStockTable.fyDefaultsSentinel) continue;
        if (c == 'YTD') {
          hidden.add('FY26 YTD');
        } else if (c == 'Type') {
          hidden.add('Consensus');
        } else {
          hidden.add(c);
        }
      }
      if (hidden.isEmpty) {
        hidden.addAll(ScreenerStockTable.defaultHiddenColumns);
      } else if (!hasFyDefaults) {
        hidden.addAll({
          'FY21',
          'FY22',
          'FY23',
          'FY24',
          'FY25',
          'FY26 YTD',
        });
      }
      if (!mounted) return;
      setState(() {
        selectedScreenerColumns
          ..clear()
          ..addAll(ScreenerStockTable.allColumns
              .where((c) => !hidden.contains(c)));
        selectedScreenerColumns.add(ScreenerStockTable.frozenColumn);
        if (selectedScreenerColumns.isEmpty) {
          selectedScreenerColumns
              .addAll(ScreenerStockTable.defaultSelectedColumns);
        }
      });
      if (!hasFyDefaults) {
        await saveScreenerColumns();
      }
    } catch (_) {}
  }

  Future<void> saveScreenerColumns() async {
    final hidden = [
      ...ScreenerStockTable.allColumns
          .where((c) => !selectedScreenerColumns.contains(c)),
      ScreenerStockTable.fyDefaultsSentinel,
    ];
    try {
      await ApiService.saveHiddenScreenerColumns(hidden);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save column preferences: $e')),
        );
      }
    }
  }

  void showScreenerColumnDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select Columns'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: ScreenerStockTable.allColumns.length,
              itemBuilder: (context, index) {
                final column = ScreenerStockTable.allColumns[index];
                final locked = column == ScreenerStockTable.frozenColumn;
                return CheckboxListTile(
                  title: Text(column),
                  value: selectedScreenerColumns.contains(column),
                  onChanged: locked
                      ? null
                      : (value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedScreenerColumns.add(column);
                            } else {
                              selectedScreenerColumns.remove(column);
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
                await saveScreenerColumns();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenerStockTableState extends State<ScreenerStockTable> {
  late final ScrollController _horizontalHeaderController;
  late final ScrollController _horizontalBodyController;
  late final ScrollController _verticalFrozenController;
  late final ScrollController _verticalBodyController;
  bool _syncingHorizontal = false;
  bool _syncingVertical = false;
  String? _sortColumn;
  bool _sortAscending = true;

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

  List<String> get _scrollableColumns => ScreenerStockTable.allColumns
      .where((column) =>
          widget.selectedColumns.contains(column) &&
          column != ScreenerStockTable.frozenColumn)
      .toList();

  List<ScreenerStock> get _sortedStocks {
    final stocks = List<ScreenerStock>.from(widget.stocks);
    final column = _sortColumn;
    if (column == null) return stocks;
    stocks.sort((a, b) {
      final cmp = _compareByColumn(a, b, column);
      if (cmp != 0) return _sortAscending ? cmp : -cmp;
      return a.symbol.toLowerCase().compareTo(b.symbol.toLowerCase());
    });
    return stocks;
  }

  int _compareByColumn(ScreenerStock a, ScreenerStock b, String column) {
    switch (column) {
      case 'Symbol':
        return a.symbol.toLowerCase().compareTo(b.symbol.toLowerCase());
      case 'Name':
        return _compareEmptyLast(a.name, b.name);
      case 'Industry':
        return _compareEmptyLast(a.industry, b.industry);
      case 'Labels':
        return _compareEmptyLast(
          a.labels.join(', '),
          b.labels.join(', '),
        );
      case 'Market Cap':
        return _marketCapRank(a.marketCap)
            .compareTo(_marketCapRank(b.marketCap));
      case 'Trend':
        return _trendRank(a.trend).compareTo(_trendRank(b.trend));
      case 'Adj ST':
        return a.adjustedSTDelta.compareTo(b.adjustedSTDelta);
      case 'Adj MT':
        return a.adjustedMTDelta.compareTo(b.adjustedMTDelta);
      case 'LTP':
        return _compareMissingZeroLast(a.currentPrice, b.currentPrice);
      case 'DMA-7':
        return _compareMissingZeroLast(a.ma7, b.ma7);
      case 'DMA-20':
        return _compareMissingZeroLast(a.ma20, b.ma20);
      case 'DMA-50':
        return _compareMissingZeroLast(a.ma50, b.ma50);
      case 'Target':
        return _compareMissingZeroLast(a.consensusTarget, b.consensusTarget);
      case 'Upside':
        return a.consensusUpside.compareTo(b.consensusUpside);
      case 'FY21':
      case 'FY22':
      case 'FY23':
      case 'FY24':
      case 'FY25':
        final year = _yearFromFyColumn(column);
        return (a.returnForYear(year) ?? double.negativeInfinity).compareTo(
            b.returnForYear(year) ?? double.negativeInfinity);
      case 'FY26 YTD':
        return (a.returnYtd ?? double.negativeInfinity)
            .compareTo(b.returnYtd ?? double.negativeInfinity);
      case 'Type':
      case 'Consensus':
        return _compareEmptyLast(
          ScreenerStockTable.consensusLabel(a.consensusType),
          ScreenerStockTable.consensusLabel(b.consensusType),
        );
      case 'News':
        return _compareEmptyLast(a.newsHeadline, b.newsHeadline);
      default:
        return 0;
    }
  }

  int _compareEmptyLast(String a, String b) {
    final aEmpty = a.trim().isEmpty;
    final bEmpty = b.trim().isEmpty;
    if (aEmpty && bEmpty) return 0;
    if (aEmpty) return 1;
    if (bEmpty) return -1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  int _compareMissingZeroLast(double a, double b) {
    final aMissing = a == 0;
    final bMissing = b == 0;
    if (aMissing && bMissing) return 0;
    if (aMissing) return 1;
    if (bMissing) return -1;
    return a.compareTo(b);
  }

  int _yearFromFyColumn(String column) {
    if (column.startsWith('FY') && column.length >= 3) {
      final two = int.tryParse(column.substring(2));
      if (two != null) return 2000 + two;
    }
    return 0;
  }

  String _formatReturn(double? v) {
    if (v == null) return '—';
    return '${v.toStringAsFixed(1)}%';
  }

  Color? _returnColor(double? v) {
    if (v == null) return null;
    return v >= 0 ? Colors.green : Colors.red;
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

  int _trendRank(String trend) {
    const order = [
      'bullish',
      'moderately bullish',
      'neutral',
      'moderately bearish_st',
      'bearish_st',
      'moderately bearish_lt',
      'bearish_lt',
    ];
    final i = order.indexOf(trend);
    return i < 0 ? order.length : i;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  List<ScreenerStock> get _symbolSortedStocks {
    final stocks = List<ScreenerStock>.from(widget.stocks);
    stocks.sort(
      (a, b) => a.symbol.toLowerCase().compareTo(b.symbol.toLowerCase()),
    );
    return stocks;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stocks.isEmpty) {
      return const SizedBox.shrink();
    }

    final showTableView =
        MediaQuery.sizeOf(context).width >= ScreenerStockTable.cardViewBreakpoint;
    if (!showTableView) {
      return _buildCardList(context);
    }

    final headerColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final borderColor = Theme.of(context).dividerColor;
    final frozenWidth =
        ScreenerStockTable.columnWidth(ScreenerStockTable.frozenColumn);
    final minScrollableWidth = _scrollableColumns.fold<double>(
      0,
      (sum, column) => sum + ScreenerStockTable.columnWidth(column),
    );

    final stocks = _sortedStocks;

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
        double widthFor(String column) =>
            ScreenerStockTable.columnWidth(column) * stretchFactor;
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
                height: ScreenerStockTable.headerHeight,
                child: Row(
                  children: [
                    _headerCell(
                      ScreenerStockTable.frozenColumn,
                      width: frozenWidth,
                      frozen: true,
                      headerColor: headerColor,
                      borderColor: borderColor,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontalHeaderController,
                        scrollDirection: Axis.horizontal,
                        physics: horizontalPhysics,
                        child: SizedBox(
                          width: contentWidth,
                          child: Row(
                            children: _scrollableColumns
                                .map((column) => _headerCell(
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
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(right: BorderSide(color: borderColor)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
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
                        itemExtent: ScreenerStockTable.rowHeight,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemBuilder: (context, index) {
                          return _rowBox(
                            index: index,
                            borderColor: borderColor,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _symbolCell(stocks[index]),
                              ),
                            ),
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
                          child: Scrollbar(
                            controller: _verticalBodyController,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: _verticalBodyController,
                              itemCount: stocks.length,
                              itemExtent: ScreenerStockTable.rowHeight,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemBuilder: (context, index) {
                                final stock = stocks[index];
                                return _rowBox(
                                  index: index,
                                  borderColor: borderColor,
                                  child: Row(
                                    children: _scrollableColumns
                                        .map((column) => SizedBox(
                                              width: widthFor(column),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                ),
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: _cell(column, stock),
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
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCardList(BuildContext context) {
    final stocks = _symbolSortedStocks;
    final narrowCard = MediaQuery.sizeOf(context).width <
        ScreenerStockTable.narrowCardBreakpoint;

    return ListView.builder(
      itemCount: stocks.length,
      itemBuilder: (context, index) {
        return _buildStockCard(
          context,
          stocks[index],
          narrowCard: narrowCard,
        );
      },
    );
  }

  Widget _buildStockCard(
    BuildContext context,
    ScreenerStock stock, {
    required bool narrowCard,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final industryLine = _cardIndustryMarketCapLine(stock);
    final headline = stock.newsHeadline.trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _openUrl(stock.googleFinanceUrl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                stock.symbol,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.open_in_new,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                          ],
                        ),
                        if (stock.name.trim().isNotEmpty)
                          Text(
                            stock.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
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
                const SizedBox(width: 8),
                _cardActions(stock),
              ],
            ),
            if (stock.trend.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'Trend',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: _trendBadge(stock.trend)),
                ],
              ),
            ],
            if (widget.onAddLabel != null || widget.onRemoveLabel != null) ...[
              const SizedBox(height: 8),
              _labelsCell(stock),
            ],
            const SizedBox(height: 12),
            _buildCardMetricsGrid(
              narrow: narrowCard,
              children: [
                _compactInfoColumn('LTP', _price(stock.currentPrice)),
                _compactInfoColumn(
                  'Adj ST',
                  _delta(stock.adjustedSTDelta),
                  _deltaColor(stock.adjustedSTDelta),
                ),
                _compactInfoColumn(
                  'Adj MT',
                  _delta(stock.adjustedMTDelta),
                  _deltaColor(stock.adjustedMTDelta),
                ),
                _compactInfoColumn('Target', _price(stock.consensusTarget)),
                _compactInfoColumn(
                  'Upside',
                  _pct(stock.consensusUpside, stock.consensusTarget > 0),
                  _deltaColor(stock.consensusUpside),
                  _isAboveTarget(stock) ? 'Above Target' : null,
                ),
                _compactInfoColumn(
                  'Consensus',
                  ScreenerStockTable.consensusLabel(stock.consensusType),
                ),
              ],
            ),
            if (stock.ma7 > 0 || stock.ma20 > 0 || stock.ma50 > 0) ...[
              const Divider(height: 20),
              _buildCardMetricsGrid(
                narrow: narrowCard,
                children: [
                  if (stock.ma7 > 0)
                    _compactInfoColumn('7-DMA', _price(stock.ma7)),
                  if (stock.ma20 > 0)
                    _compactInfoColumn('20-DMA', _price(stock.ma20)),
                  if (stock.ma50 > 0)
                    _compactInfoColumn('50-DMA', _price(stock.ma50)),
                ],
              ),
            ],
            if (stock.returnYtd != null) ...[
              const Divider(height: 20),
              _compactInfoColumn(
                'FY26 YTD',
                _formatReturn(stock.returnYtd),
                _returnColor(stock.returnYtd),
              ),
            ],
            if (headline.isNotEmpty) ...[
              const Divider(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'News',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  const SizedBox(height: 2),
                  _newsCell(stock),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardActions(ScreenerStock stock) {
    final busy = widget.busyStockId == stock.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FilledButton(
          onPressed: () => widget.onBuy(stock),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Text('BUY'),
        ),
        if (widget.onAddWatchlist != null && !stock.inWatchlist) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: busy ? null : () => widget.onAddWatchlist!(stock),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('WatchList'),
          ),
        ],
        if (widget.onRemoveWatchlist != null && stock.inWatchlist) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: busy ? null : () => widget.onRemoveWatchlist!(stock),
            child: const Text('Remove'),
          ),
        ],
      ],
    );
  }

  String? _cardIndustryMarketCapLine(ScreenerStock stock) {
    final industry = stock.industry.trim();
    final marketCap = stock.marketCap.trim();
    if (industry.isEmpty && marketCap.isEmpty) return null;
    if (industry.isEmpty) return marketCap;
    if (marketCap.isEmpty) return industry;
    return '$industry ($marketCap)';
  }

  Widget _trendBadge(String trend) {
    Color color;
    IconData icon;

    switch (trend) {
      case 'bullish':
        color = Colors.green;
        icon = Icons.trending_up;
        break;
      case 'moderately bullish':
        color = Colors.lightGreen;
        icon = Icons.trending_up;
        break;
      case 'bearish_st':
        color = Colors.red;
        icon = Icons.trending_down;
        break;
      case 'moderately bearish_st':
        color = Colors.orange;
        icon = Icons.trending_down;
        break;
      case 'bearish_lt':
        color = Colors.red;
        icon = Icons.trending_down;
        break;
      case 'moderately bearish_lt':
        color = Colors.deepOrange;
        icon = Icons.trending_down;
        break;
      default:
        color = Colors.grey;
        icon = Icons.trending_flat;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              ScreenerStockTable.trendLabel(trend),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactInfoColumn(
    String label,
    String value, [
    Color? valueColor,
    String? caption,
  ]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        if (caption != null && caption.isNotEmpty)
          Text(
            caption,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade700,
            ),
          ),
      ],
    );
  }

  Color? _deltaColor(double value) {
    if (value == 0) return null;
    return value >= 0 ? Colors.green : Colors.red;
  }

  Widget _buildCardMetricsGrid({
    required bool narrow,
    required List<Widget> children,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    Widget rowOf(List<Widget> rowChildren) {
      return Row(
        children: [
          for (var i = 0; i < rowChildren.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: rowChildren[i]),
          ],
        ],
      );
    }

    if (!narrow || children.length <= 3) {
      return rowOf(children);
    }

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 3) {
      final end = (i + 3).clamp(0, children.length);
      final chunk = children.sublist(i, end);
      rows.add(rowOf(chunk));
      if (end < children.length) {
        rows.add(const SizedBox(height: 10));
      }
    }
    return Column(children: rows);
  }

  Widget _rowBox({
    required int index,
    required Color borderColor,
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: index.isEven
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: borderColor.withValues(alpha: 0.5)),
        ),
      ),
      child: child,
    );
  }

  Widget _headerCell(
    String column, {
    required double width,
    bool frozen = false,
    Color? headerColor,
    required Color borderColor,
  }) {
    final canSort = column != 'Actions';
    final isSorted = _sortColumn == column;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: frozen ? headerColor : Colors.transparent,
      child: InkWell(
        onTap: canSort ? () => _onSort(column) : null,
        child: Container(
          width: width,
          height: ScreenerStockTable.headerHeight,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: borderColor.withValues(alpha: 0.4)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  column,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isSorted ? colorScheme.primary : null,
                  ),
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
                  color: isSorted ? colorScheme.primary : Colors.grey,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(String column, ScreenerStock stock) {
    switch (column) {
      case 'Name':
        return _text(stock.name);
      case 'Industry':
        return _text(stock.industry);
      case 'Labels':
        return _labelsCell(stock);
      case 'Market Cap':
        return _text(stock.marketCap);
      case 'Trend':
        return _text(ScreenerStockTable.trendLabel(stock.trend));
      case 'Adj ST':
        return Text(_delta(stock.adjustedSTDelta));
      case 'Adj MT':
        return Text(_delta(stock.adjustedMTDelta));
      case 'LTP':
        return Text(_price(stock.currentPrice));
      case 'DMA-7':
        return Text(_price(stock.ma7));
      case 'DMA-20':
        return Text(_price(stock.ma20));
      case 'DMA-50':
        return Text(_price(stock.ma50));
      case 'Target':
        return Text(_price(stock.consensusTarget));
      case 'Upside':
        return _upsideCell(stock);
      case 'FY21':
      case 'FY22':
      case 'FY23':
      case 'FY24':
      case 'FY25':
        final year = _yearFromFyColumn(column);
        final v = stock.returnForYear(year);
        return Text(
          _formatReturn(v),
          style: TextStyle(color: _returnColor(v)),
        );
      case 'FY26 YTD':
        return Text(
          _formatReturn(stock.returnYtd),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _returnColor(stock.returnYtd),
          ),
        );
      case 'Type':
      case 'Consensus':
        return _text(ScreenerStockTable.consensusLabel(stock.consensusType));
      case 'News':
        return _newsCell(stock);
      case 'Actions':
        return _actions(stock);
      default:
        return _text('');
    }
  }

  Widget _labelsCell(ScreenerStock stock) {
    final busy = widget.busyStockId == stock.id;
    final canEdit = widget.onAddLabel != null || widget.onRemoveLabel != null;
    if (!canEdit && stock.labels.isEmpty) {
      return _text('');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final label in stock.labels)
              InputChip(
                label: Text(label, style: const TextStyle(fontSize: 11)),
                onDeleted: widget.onRemoveLabel == null || busy
                    ? null
                    : () => widget.onRemoveLabel!(stock, label),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            if (widget.onAddLabel != null)
              ActionChip(
                label: busy
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('+', style: TextStyle(fontSize: 14)),
                onPressed: busy ? null : () => _showAddLabelDialog(stock),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _showAddLabelDialog(ScreenerStock stock) async {
    final controller = TextEditingController();
    final existing = stock.labels.toSet();
    final options = <String>{
      ...ScreenerStock.defaultLabels,
      ...widget.labelOptions,
    };

    String? selected;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final query = controller.text.trim().toLowerCase();
            final suggestions = options.where((label) {
              if (existing.contains(label)) return false;
              if (query.isEmpty) return true;
              return label.toLowerCase().contains(query);
            }).toList()
              ..sort();
            if (query.isNotEmpty &&
                !existing.contains(controller.text.trim()) &&
                !suggestions
                    .any((l) => l.toLowerCase() == query)) {
              suggestions.insert(0, controller.text.trim());
            }

            return AlertDialog(
              title: Text('Add label to ${stock.symbol}'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: 'Type to search or create',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (value) {
                        final label = value.trim();
                        if (label.isNotEmpty) selected = label;
                        Navigator.pop(dialogContext);
                      },
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        itemBuilder: (context, index) {
                          final label = suggestions[index];
                          return ListTile(
                            dense: true,
                            title: Text(label),
                            onTap: () {
                              selected = label;
                              Navigator.pop(dialogContext);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final label = controller.text.trim();
                    if (label.isEmpty) return;
                    selected = label;
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();

    final label = selected?.trim();
    if (label == null || label.isEmpty || widget.onAddLabel == null) return;
    widget.onAddLabel!(stock, label);
  }

  Widget _symbolCell(ScreenerStock stock) {
    return InkWell(
      onTap: () => _openUrl(stock.googleFinanceUrl),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              stock.symbol,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.open_in_new,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _newsCell(ScreenerStock stock) {
    final headline = stock.newsHeadline.trim();
    if (headline.isEmpty) return const Text('-');
    final url = stock.newsUrl.trim();
    final text = Text(
      headline,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: url.isEmpty
          ? null
          : const TextStyle(
              decoration: TextDecoration.underline,
              color: Colors.blue,
            ),
    );
    return url.isEmpty
        ? text
        : InkWell(
            onTap: () => _openUrl(url),
            child: text,
          );
  }

  Widget _actions(ScreenerStock stock) {
    final busy = widget.busyStockId == stock.id;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (widget.onAddWatchlist != null && !stock.inWatchlist)
          TextButton(
            onPressed: busy ? null : () => widget.onAddWatchlist!(stock),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add to WatchList'),
          ),
        if (widget.onRemoveWatchlist != null && stock.inWatchlist)
          TextButton(
            onPressed: busy ? null : () => widget.onRemoveWatchlist!(stock),
            child: const Text('Remove'),
          ),
        FilledButton(
          onPressed: () => widget.onBuy(stock),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Text('BUY'),
        ),
      ],
    );
  }

  Widget _upsideCell(ScreenerStock stock) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_pct(stock.consensusUpside, stock.consensusTarget > 0)),
        if (_isAboveTarget(stock))
          Text(
            'Above Target',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade700,
            ),
          ),
      ],
    );
  }

  static bool _isAboveTarget(ScreenerStock stock) =>
      stock.consensusTarget > 0 && stock.currentPrice > stock.consensusTarget;

  Widget _text(String value) => Text(value.trim().isEmpty ? '-' : value);

  static String _price(double value) {
    if (value == 0) return '-';
    return value.toStringAsFixed(2);
  }

  static String _delta(double value) => value.toStringAsFixed(2);

  static String _pct(double value, bool meaningful) {
    if (!meaningful && value == 0) return '-';
    return '${value.toStringAsFixed(2)}%';
  }

  static bool _openUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return false;
    }
    web.window.open(url, '_blank');
    return true;
  }
}
