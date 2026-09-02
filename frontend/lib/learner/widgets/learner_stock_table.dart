import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/stock.dart';
import '../../models/stock_trend.dart';
import '../../providers/auth_provider.dart';
import '../../utils/currency_format.dart';
import '../learner_provider.dart';
import '../../utils/screen_tracker.dart';
import '../screens/learner_holding_detail_screen.dart';
import 'learner_stock_actions.dart';
import 'learner_stock_display.dart';

class LearnerStockTable extends StatefulWidget {
  final List<Stock> stocks;
  final int challengeId;
  final bool tradingOpen;
  final String Function(Stock stock, StockTrend? trend) recommendationFor;

  const LearnerStockTable({
    super.key,
    required this.stocks,
    required this.challengeId,
    required this.tradingOpen,
    required this.recommendationFor,
  });

  @override
  State<LearnerStockTable> createState() => _LearnerStockTableState();
}

class _LearnerStockTableState extends State<LearnerStockTable> {
  static const _headerHeight = 58.0;
  static const _rowHeight = 90.0;
  static const _symbolWidth = 120.0;

  static const _columns = [
    'Qty',
    'Current Value',
    'P/L %',
    'XIRR',
    'Price Range',
    'Trend',
    'Signal',
    'Actions',
    'News',
    'Notes',
  ];

  static const _columnWidths = {
    'Qty': 72.0,
    'Current Value': 110.0,
    'P/L %': 72.0,
    'XIRR': 72.0,
    'Price Range': 152.0,
    'Trend': 120.0,
    'Signal': 140.0,
    'Actions': 168.0,
    'News': 180.0,
    'Notes': 160.0,
  };

  late final ScrollController _horizontalHeaderController;
  late final ScrollController _horizontalBodyController;
  late final ScrollController _verticalFrozenController;
  late final ScrollController _verticalBodyController;
  bool _syncingHorizontal = false;
  bool _syncingVertical = false;

  @override
  void initState() {
    super.initState();
    _horizontalHeaderController = ScrollController();
    _horizontalBodyController = ScrollController();
    _verticalFrozenController = ScrollController();
    _verticalBodyController = ScrollController();

    _horizontalHeaderController.addListener(_syncHeaderToBody);
    _horizontalBodyController.addListener(_syncBodyToHeader);
    _verticalFrozenController.addListener(_syncFrozenToBody);
    _verticalBodyController.addListener(_syncBodyToFrozen);
  }

  @override
  void dispose() {
    _horizontalHeaderController.removeListener(_syncHeaderToBody);
    _horizontalBodyController.removeListener(_syncBodyToHeader);
    _verticalFrozenController.removeListener(_syncFrozenToBody);
    _verticalBodyController.removeListener(_syncBodyToFrozen);
    _horizontalHeaderController.dispose();
    _horizontalBodyController.dispose();
    _verticalFrozenController.dispose();
    _verticalBodyController.dispose();
    super.dispose();
  }

  void _syncHeaderToBody() {
    if (_syncingHorizontal) return;
    _syncingHorizontal = true;
    _horizontalBodyController.jumpTo(_horizontalHeaderController.offset);
    _syncingHorizontal = false;
  }

  void _syncBodyToHeader() {
    if (_syncingHorizontal) return;
    _syncingHorizontal = true;
    _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
    _syncingHorizontal = false;
  }

  void _syncFrozenToBody() {
    if (_syncingVertical) return;
    _syncingVertical = true;
    _verticalBodyController.jumpTo(_verticalFrozenController.offset);
    _syncingVertical = false;
  }

  void _syncBodyToFrozen() {
    if (_syncingVertical) return;
    _syncingVertical = true;
    _verticalFrozenController.jumpTo(_verticalBodyController.offset);
    _syncingVertical = false;
  }

  List<String> _visibleColumns(bool showXirr) {
    return showXirr
        ? _columns
        : _columns.where((c) => c != 'XIRR').toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LearnerProvider>();
    final showXirr = context.watch<AuthProvider>().showXirr;
    final columns = _visibleColumns(showXirr);
    final headerColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final borderColor = Theme.of(context).dividerColor;
    final minScrollableWidth = columns.fold<double>(
      0,
      (sum, column) => sum + (_columnWidths[column] ?? 100),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableScrollableWidth =
            (constraints.maxWidth - _symbolWidth).clamp(0.0, double.infinity);
        final needsHorizontalScroll =
            minScrollableWidth > availableScrollableWidth + 0.5;
        final contentWidth = needsHorizontalScroll
            ? minScrollableWidth
            : availableScrollableWidth;
        final actionsWidth = _columnWidths['Actions'] ?? 168;
        final flexMinWidth = minScrollableWidth - actionsWidth;
        final stretchFactor = flexMinWidth > 0 && !needsHorizontalScroll
            ? (availableScrollableWidth - actionsWidth) / flexMinWidth
            : 1.0;

        double widthFor(String column) => column == 'Actions'
            ? (_columnWidths[column] ?? 168)
            : (_columnWidths[column] ?? 100) * stretchFactor;

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
                    _headerCell('Symbol', _symbolWidth, headerColor, borderColor,
                        frozen: true),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontalHeaderController,
                        scrollDirection: Axis.horizontal,
                        physics: horizontalPhysics,
                        child: SizedBox(
                          width: contentWidth,
                          child: Row(
                            children: columns
                                .map(
                                  (column) => _headerCell(
                                    column,
                                    widthFor(column),
                                    headerColor,
                                    borderColor,
                                  ),
                                )
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
                      width: _symbolWidth,
                      child: ListView.builder(
                        controller: _verticalFrozenController,
                        itemCount: widget.stocks.length,
                        itemExtent: _rowHeight,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemBuilder: (context, index) {
                          final stock = widget.stocks[index];
                          return _symbolCell(stock, borderColor, index.isEven);
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
                              itemCount: widget.stocks.length,
                              itemExtent: _rowHeight,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemBuilder: (context, index) {
                                final stock = widget.stocks[index];
                                final trend = provider.trendFor(stock.id);
                                final recommendation =
                                    widget.recommendationFor(stock, trend);
                                final invested = stock.buyPrice * stock.quantity;
                                final current =
                                    stock.currentPrice * stock.quantity;
                                final profitLoss = current - invested;
                                final profitLossPct = invested > 0
                                    ? (profitLoss / invested) * 100
                                    : 0.0;

                                return DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: index.isEven
                                        ? Theme.of(context).colorScheme.surface
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLowest,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: borderColor.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: columns
                                        .map(
                                          (column) => SizedBox(
                                            width: widthFor(column),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                              ),
                                              child: Align(
                                                alignment:
                                                    Alignment.centerLeft,
                                                child: _cell(
                                                  context,
                                                  column,
                                                  stock,
                                                  trend,
                                                  recommendation,
                                                  profitLoss,
                                                  profitLossPct,
                                                  provider,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
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

  Widget _headerCell(
    String label,
    double width,
    Color headerColor,
    Color borderColor, {
    bool frozen = false,
  }) {
    return Container(
      width: width,
      height: _headerHeight,
      decoration: BoxDecoration(
        color: headerColor,
        border: frozen
            ? Border(right: BorderSide(color: borderColor))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _symbolCell(Stock stock, Color borderColor, bool even) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: even
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: borderColor.withValues(alpha: 0.5)),
        ),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            appPageRoute(
              LearnerHoldingDetailScreen(
                challengeId: widget.challengeId,
                symbol: stock.symbol,
                stockId: stock.id,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              stock.symbol,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    String column,
    Stock stock,
    StockTrend? trend,
    String recommendation,
    double profitLoss,
    double profitLossPct,
    LearnerProvider provider,
  ) {
    switch (column) {
      case 'Qty':
        return Text(stock.quantity.toStringAsFixed(2));
      case 'Current Value':
        return Text(formatInr(stock.quantity * stock.currentPrice));
      case 'P/L %':
        return Text(
          '${profitLossPct.toStringAsFixed(2)}%',
          style: TextStyle(
            color: profitLoss >= 0 ? Colors.green : Colors.red,
          ),
        );
      case 'XIRR':
        if (stock.xirr == null) return const Text('-');
        return Text(
          '${(stock.xirr! * 100).toStringAsFixed(2)}%',
          style: TextStyle(
            color: stock.xirr! >= 0 ? Colors.green : Colors.red,
          ),
        );
      case 'Trend':
        return trend != null
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: LearnerStockDisplay.trendBadge(trend.trend),
              )
            : const Text('-');
      case 'Signal':
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: LearnerStockDisplay.recommendationBadge(recommendation),
        );
      case 'Price Range':
        return stock.sixthHighestPrice > 0 && stock.sixthLowestPrice > 0
            ? SizedBox(
                width: 144,
                height: 66,
                child: LearnerStockDisplay.compactPriceRangeBar(stock),
              )
            : const Text('-');
      case 'Actions':
        return LearnerStockActions.compactBar(
          context: context,
          stock: stock,
          challengeId: widget.challengeId,
          tradingOpen: widget.tradingOpen,
          provider: provider,
        );
      case 'News':
        return LearnerStockDisplay.newsTeaser(stock);
      case 'Notes':
        return LearnerStockActions.notesCell(
          context: context,
          stock: stock,
          challengeId: widget.challengeId,
          provider: provider,
        );
      default:
        return const Text('-');
    }
  }
}
