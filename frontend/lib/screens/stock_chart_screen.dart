import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../providers/finance_provider.dart';
import '../services/api_service.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import '../widgets/stock_holding_panel.dart';

class StockChartScreen extends StatefulWidget {
  final String symbol;
  final String? name;
  final int stockId;
  final String source;

  const StockChartScreen({
    super.key,
    required this.symbol,
    this.name,
    required this.stockId,
    required this.source,
  });

  @override
  State<StockChartScreen> createState() => _StockChartScreenState();
}

class _StockChartScreenState extends State<StockChartScreen> {
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  String? _error;
  FinanceProvider? _provider;
  final _chartTransform = TransformationController();
  static const _minZoom = 1.0;
  static const _maxZoom = 4.0;
  Size _chartViewport = Size.zero;
  bool _chartPinnedRight = true;
  bool _chartInteracting = false;
  int? _hoverSpotIndex;
  Offset? _hoverAnchor;
  List<_ChartHoverLine> _hoverLines = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<FinanceProvider>();
    if (_provider != provider) {
      _provider?.removeListener(_onHoldingsChanged);
      _provider = provider;
      _provider!.addListener(_onHoldingsChanged);
    }
  }

  @override
  void dispose() {
    _chartTransform.dispose();
    _provider?.removeListener(_onHoldingsChanged);
    super.dispose();
  }

  void _zoomChart(double factor, Size viewport) {
    _chartViewport = viewport;
    final current = _chartTransform.value.getMaxScaleOnAxis();
    _applyChartTransform(
      scale: current * factor,
      tx: _chartTransform.value.getTranslation().x,
      ty: _chartTransform.value.getTranslation().y,
      pinRight: true,
    );
    _clearChartHover();
    setState(() {});
  }

  void _resetChartZoom() {
    _chartPinnedRight = true;
    _chartTransform.value = Matrix4.identity();
    _clearChartHover();
    setState(() {});
  }

  void _clearChartHover() {
    if (_hoverSpotIndex == null && _hoverLines.isEmpty) return;
    _hoverSpotIndex = null;
    _hoverAnchor = null;
    _hoverLines = const [];
  }

  void _applyChartTransform({
    required double scale,
    required double tx,
    required double ty,
    required bool pinRight,
  }) {
    final w = _chartViewport.width;
    final h = _chartViewport.height;
    if (w <= 0 || h <= 0) return;
    scale = scale.clamp(_minZoom, _maxZoom);
    if (scale <= _minZoom + 0.01) {
      _chartPinnedRight = true;
      _chartTransform.value = Matrix4.identity();
      return;
    }
    if (pinRight) {
      _chartPinnedRight = true;
    }
    final minTx = w * (1 - scale);
    final minTy = h * (1 - scale);
    if (_chartPinnedRight) {
      tx = minTx;
    } else {
      tx = tx.clamp(minTx, 0.0);
    }
    ty = ty.clamp(minTy, 0.0);
    _chartTransform.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _onChartInteractionUpdate(ScaleUpdateDetails details) {
    final scale = _chartTransform.value.getMaxScaleOnAxis();
    final t = _chartTransform.value.getTranslation();
    final panning =
        details.scale == 1.0 && details.focalPointDelta.distanceSquared > 0.8;
    if (panning) {
      _chartPinnedRight = false;
    }
    _applyChartTransform(
      scale: scale,
      tx: t.x,
      ty: t.y,
      pinRight: !panning && _chartPinnedRight,
    );
  }

  void _onHoldingsChanged() {
    if (!mounted) return;
    _reloadTransactions();
  }

  Future<void> _reloadTransactions() async {
    try {
      final txs = await ApiService.getStockTransactions(widget.symbol);
      if (!mounted) return;
      setState(() => _transactions = txs);
    } catch (_) {}
  }

  Stock? _holding(FinanceProvider provider) {
    for (final s in provider.stocks) {
      if (s.id == widget.stockId && s.source == widget.source) return s;
    }
    return null;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    List<Map<String, dynamic>> history = [];
    List<Map<String, dynamic>> transactions = [];
    String? error;

    try {
      history = await ApiService.getStockHistory(widget.symbol);
    } catch (e) {
      error = e.toString();
    }
    try {
      transactions = await ApiService.getStockTransactions(widget.symbol);
    } catch (e) {
      error ??= e.toString();
    }

    if (!mounted) return;
    setState(() {
      _history = history;
      _transactions = transactions;
      _error = history.isEmpty ? error : null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBrandTitle(widget.symbol),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 700;
                  return SingleChildScrollView(
                    padding: EdgeInsets.all(compact ? 8.0 : 16.0),
                    child: Consumer<FinanceProvider>(
                      builder: (context, provider, _) {
                        final holding = _holding(provider);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (holding != null)
                              StockHoldingPanel(
                                stock: holding,
                                onDeleted: () {
                                  if (Navigator.of(context).canPop()) {
                                    Navigator.of(context).pop();
                                  }
                                },
                                afterSignal: _buildChartSection(
                                  holding,
                                  compact: compact,
                                ),
                              )
                            else ...[
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
                              _buildChartSection(null, compact: compact),
                            ],
                            const SizedBox(height: 24),
                            _buildTransactionsTable(),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  static const _buyColor = Color(0xFF2E7D32);
  static const _sellColor = Color(0xFFEF6C00);
  static const _holdColor = Color(0xFF303F9F);
  static const _avgBuyColor = Color(0xFF2E7D32);
  static const _ma7Color = Color(0xFF00838F);
  static const _ma20Color = Color(0xFF6D4C41);
  static const _ma50Color = Color(0xFF8E24AA);
  static const _avgBuyDashArray = [10, 6];
  static const _dmaDashArray = [2, 3];
  static const double _rightPriceReserve = 108;
  static const double _rightPriceReserveCompact = 80;
  static const double _rightLabelGap = 16;

  Widget _buildChartSection(Stock? holding, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '1-Year Price',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_error != null && _history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text('Error: $_error'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _loadData,
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No historical data available')),
          )
        else
          _buildChart(holding, compact: compact),
      ],
    );
  }

  Widget _buildChart(Stock? holding, {required bool compact}) {
    final prices = _history.map((e) => (e['price'] as num).toDouble()).toList();
    final avgBuyPrice = holding?.buyPrice ?? 0;
    final trend = _trendFor(holding);
    final ma7 = _dmaLevel(prices, 7, trend?.ma7);
    final ma20 = _dmaLevel(prices, 20, trend?.ma20);
    final ma50 = _dmaLevel(prices, 50, trend?.ma50);
    final markers = _actionMarkers(holding);
    final priceColor = Theme.of(context).colorScheme.primary;

    var minPrice = prices.reduce(math.min);
    var maxPrice = prices.reduce(math.max);
    void include(double value) {
      if (value <= 0) return;
      minPrice = math.min(minPrice, value);
      maxPrice = math.max(maxPrice, value);
    }

    include(avgBuyPrice);
    include(ma7?.value ?? 0);
    include(ma20?.value ?? 0);
    include(ma50?.value ?? 0);
    for (final marker in markers) {
      include(marker.price);
    }
    final priceRange = maxPrice - minPrice <= 0 ? 1.0 : maxPrice - minPrice;
    final chartMinY = minPrice - (priceRange * 0.1);
    final chartMaxY = maxPrice + (priceRange * 0.1);
    final plotHeight =
        (compact ? 280.0 : 400.0) - (compact ? 16.0 : 32.0) - 30.0;
    final maxX = (_history.length - 1).toDouble();

    final rightLabels = <_RightLabel>[
      if (avgBuyPrice > 0)
        _RightLabel(
          y: avgBuyPrice,
          text: 'Avg Buy (${formatInr(avgBuyPrice)})',
          color: _avgBuyColor,
        ),
      if (ma7 != null)
        _RightLabel(
          y: ma7.value,
          text: '7-DMA (${formatInr(ma7.value)})',
          color: _ma7Color,
        ),
      if (ma20 != null)
        _RightLabel(
          y: ma20.value,
          text: '20-DMA (${formatInr(ma20.value)})',
          color: _ma20Color,
        ),
      if (ma50 != null)
        _RightLabel(
          y: ma50.value,
          text: '50-DMA (${formatInr(ma50.value)})',
          color: _ma50Color,
        ),
    ];
    _nudgeRightLabels(
      rightLabels,
      minY: chartMinY,
      maxY: chartMaxY,
      plotHeight: plotHeight,
    );
    _RightLabel? labelFor(Color color) {
      for (final label in rightLabels) {
        if (label.color == color) return label;
      }
      return null;
    }

    final lineBars = <LineChartBarData>[
      LineChartBarData(
        spots: List.generate(
          _history.length,
          (index) => FlSpot(index.toDouble(), prices[index]),
        ),
        isCurved: true,
        preventCurveOverShooting: true,
        color: priceColor,
        barWidth: compact ? 1.6 : 2,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: priceColor.withValues(alpha: 0.1),
        ),
      ),
      if (ma7 != null)
        _dmaLevelBar(
          ma7,
          _ma7Color,
          labelFor(_ma7Color),
          compact: compact,
        ),
      if (ma20 != null)
        _dmaLevelBar(
          ma20,
          _ma20Color,
          labelFor(_ma20Color),
          compact: compact,
        ),
      if (ma50 != null)
        _dmaLevelBar(
          ma50,
          _ma50Color,
          labelFor(_ma50Color),
          compact: compact,
        ),
      if (avgBuyPrice > 0)
        LineChartBarData(
          spots: [FlSpot(maxX, avgBuyPrice)],
          color: _avgBuyColor,
          barWidth: 0,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) =>
                _RightEdgeLabelPainter(
              color: _avgBuyColor,
              label: labelFor(_avgBuyColor)?.text ??
                  'Avg Buy (${formatInr(avgBuyPrice)})',
              dy: labelFor(_avgBuyColor)?.dy ?? 0,
            ),
          ),
        ),
      for (final marker in markers) _markerBar(marker),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: compact ? 280 : 400,
          padding: EdgeInsets.fromLTRB(
            compact ? 4 : 16,
            compact ? 8 : 16,
            compact ? 4 : 16,
            compact ? 8 : 16,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 4,
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              _chartViewport = constraints.biggest;
              final zoomed =
                  _chartTransform.value.getMaxScaleOnAxis() > _minZoom + 0.01;
              return Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      transformationController: _chartTransform,
                      minScale: _minZoom,
                      maxScale: _maxZoom,
                      panEnabled: true,
                      scaleEnabled: true,
                      trackpadScrollCausesScale: true,
                      clipBehavior: Clip.hardEdge,
                      onInteractionStart: (_) {
                        if (!_chartInteracting) {
                          setState(() {
                            _chartInteracting = true;
                            _clearChartHover();
                          });
                        }
                      },
                      onInteractionUpdate: _onChartInteractionUpdate,
                      onInteractionEnd: (_) {
                        if (_chartInteracting) {
                          setState(() => _chartInteracting = false);
                        }
                      },
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: priceRange / 5,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: Colors.grey.withValues(alpha: 0.2),
                                strokeWidth: 1,
                              );
                            },
                          ),
                          extraLinesData: ExtraLinesData(
                            extraLinesOnTop: true,
                            horizontalLines: [
                              if (avgBuyPrice > 0)
                                HorizontalLine(
                                  y: avgBuyPrice,
                                  color: _avgBuyColor,
                                  strokeWidth: 1.5,
                                  dashArray: _avgBuyDashArray,
                                  label: HorizontalLineLabel(show: false),
                                ),
                            ],
                          ),
                          lineTouchData: LineTouchData(
                            enabled: !zoomed && !_chartInteracting,
                            handleBuiltInTouches: true,
                            touchCallback: (event, response) {
                              _onChartHover(
                                event: event,
                                response: response,
                                enabled: !zoomed && !_chartInteracting,
                                chartSize: constraints.biggest,
                                compact: compact,
                                minY: chartMinY,
                                maxY: chartMaxY,
                                maxX: maxX,
                                hasRightLabels: rightLabels.isNotEmpty,
                                priceColor: priceColor,
                                markers: markers,
                              );
                            },
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipItems: (touchedSpots) =>
                                  List<LineTooltipItem?>.filled(
                                touchedSpots.length,
                                null,
                              ),
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: rightLabels.isNotEmpty,
                                reservedSize: rightLabels.isEmpty
                                    ? 0
                                    : (compact
                                        ? _rightPriceReserveCompact
                                        : _rightPriceReserve),
                                getTitlesWidget: (value, meta) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                interval:
                                    (_history.length / 6).ceil().toDouble(),
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index >= 0 && index < _history.length) {
                                    final dateStr =
                                        _history[index]['date'] as String;
                                    final date = DateTime.parse(dateStr);
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        DateFormat('MMM yy').format(date),
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
                                reservedSize: compact ? 44 : 60,
                                interval: priceRange / 5,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    formatInr(value),
                                    style:
                                        TextStyle(fontSize: compact ? 9 : 10),
                                  );
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: lineBars,
                          minX: 0,
                          maxX: maxX,
                          minY: chartMinY,
                          maxY: chartMaxY,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    left: compact ? 2 : 4,
                    child: _chartZoomBar(constraints.biggest),
                  ),
                  if (_hoverLines.isNotEmpty && _hoverAnchor != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomSingleChildLayout(
                          delegate: _HoverTooltipLayoutDelegate(
                            anchor: _hoverAnchor!,
                            bounds: constraints.biggest,
                          ),
                          child: Material(
                            color: const Color(0xFFF7F7F7),
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                              side: const BorderSide(
                                color: Color(0xFF212121),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final line in _hoverLines)
                                    Text(
                                      '${line.name} ${formatInr(line.price)}',
                                      style: const TextStyle(
                                        color: Color(0xFF212121),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                ],
                              ),
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

  void _onChartHover({
    required FlTouchEvent event,
    required LineTouchResponse? response,
    required bool enabled,
    required Size chartSize,
    required bool compact,
    required double minY,
    required double maxY,
    required double maxX,
    required bool hasRightLabels,
    required Color priceColor,
    required List<_ActionMarker> markers,
  }) {
    if (!enabled ||
        !event.isInterestedForInteractions ||
        response?.lineBarSpots == null ||
        response!.lineBarSpots!.isEmpty) {
      if (_hoverSpotIndex != null || _hoverLines.isNotEmpty) {
        setState(_clearChartHover);
      }
      return;
    }

    LineBarSpot? topSpot;
    final lines = <_ChartHoverLine>[];
    for (final spot in response.lineBarSpots!) {
      final name = _hoverLabelForSpot(spot, priceColor, markers);
      if (name == null) continue;
      lines.add(_ChartHoverLine(name: name, price: spot.y));
      if (topSpot == null || spot.y > topSpot.y) {
        topSpot = spot;
      }
    }
    if (lines.isEmpty || topSpot == null) {
      if (_hoverSpotIndex != null || _hoverLines.isNotEmpty) {
        setState(_clearChartHover);
      }
      return;
    }

    const order = ['Price', '7-DMA', '20-DMA', '50-DMA'];
    lines.sort((a, b) {
      final ai = order.indexOf(a.name);
      final bi = order.indexOf(b.name);
      final av = ai < 0 ? order.length : ai;
      final bv = bi < 0 ? order.length : bi;
      if (av != bv) return av.compareTo(bv);
      return a.name.compareTo(b.name);
    });

    final anchor = _chartSpotToPixel(
      spot: topSpot,
      size: chartSize,
      compact: compact,
      minY: minY,
      maxY: maxY,
      maxX: maxX,
      hasRightLabels: hasRightLabels,
    );
    final hoverIndex = topSpot.spotIndex;
    if (_hoverSpotIndex == hoverIndex &&
        _hoverAnchor == anchor &&
        _hoverLines.length == lines.length) {
      return;
    }
    setState(() {
      _hoverSpotIndex = hoverIndex;
      _hoverAnchor = anchor;
      _hoverLines = lines;
    });
  }

  String? _hoverLabelForSpot(
    LineBarSpot spot,
    Color priceColor,
    List<_ActionMarker> markers,
  ) {
    final color = spot.bar.color ?? Colors.blueGrey;
    if (color == priceColor) return 'Price';
    if (color == _ma7Color) return '7-DMA';
    if (color == _ma20Color) return '20-DMA';
    if (color == _ma50Color) return '50-DMA';
    for (final marker in markers) {
      if (color == marker.color) return marker.label;
    }
    return null;
  }

  Offset _chartSpotToPixel({
    required FlSpot spot,
    required Size size,
    required bool compact,
    required double minY,
    required double maxY,
    required double maxX,
    required bool hasRightLabels,
  }) {
    final left = compact ? 44.0 : 60.0;
    final right = hasRightLabels
        ? (compact ? _rightPriceReserveCompact : _rightPriceReserve)
        : 0.0;
    const top = 0.0;
    const bottom = 30.0;
    final plotW = (size.width - left - right).clamp(1.0, size.width);
    final plotH = (size.height - top - bottom).clamp(1.0, size.height);
    final dx = left + (maxX <= 0 ? 0.0 : (spot.x / maxX) * plotW);
    final range = maxY - minY;
    final dy = range == 0
        ? top + plotH
        : top + plotH - ((spot.y - minY) / range) * plotH;
    return Offset(dx, dy);
  }

  Widget _chartZoomBar(Size viewport) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      elevation: 1,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom out',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.remove, size: 18),
            onPressed: () => _zoomChart(0.8, viewport),
          ),
          IconButton(
            tooltip: 'Zoom in',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => _zoomChart(1.25, viewport),
          ),
          IconButton(
            tooltip: 'Reset zoom',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.fit_screen, size: 18),
            onPressed: _resetChartZoom,
          ),
        ],
      ),
    );
  }

  LineChartBarData _dmaLevelBar(
    _DmaLevel level,
    Color color,
    _RightLabel? rightLabel, {
    required bool compact,
  }) {
    return LineChartBarData(
      spots: level.spots,
      isCurved: false,
      color: color,
      barWidth: compact ? 2.4 : 1.6,
      dashArray: _dmaDashArray,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, bar) =>
            spot.x == bar.spots.first.x || spot.x == bar.spots.last.x,
        getDotPainter: (spot, percent, bar, index) {
          if (spot.x == bar.spots.last.x && rightLabel != null) {
            return _RightEdgeLabelPainter(
              color: color,
              label: rightLabel.text,
              dy: rightLabel.dy,
              showDot: true,
            );
          }
          return FlDotCirclePainter(
            radius: compact ? 3 : 2.5,
            color: color,
            strokeWidth: 1,
            strokeColor: Colors.white,
          );
        },
      ),
      belowBarData: BarAreaData(show: false),
    );
  }

  void _nudgeRightLabels(
    List<_RightLabel> labels, {
    required double minY,
    required double maxY,
    required double plotHeight,
  }) {
    if (labels.length < 2 || plotHeight <= 0) return;
    final range = maxY - minY;
    if (range <= 0) return;

    double toPixel(double price) {
      final t = ((price - minY) / range).clamp(0.0, 1.0);
      return (1 - t) * plotHeight;
    }

    final order = List<int>.generate(labels.length, (i) => i)
      ..sort((a, b) => toPixel(labels[a].y).compareTo(toPixel(labels[b].y)));

    final pixelY = [for (final i in order) toPixel(labels[i].y)];
    for (var k = 1; k < pixelY.length; k++) {
      if (pixelY[k] - pixelY[k - 1] < _rightLabelGap) {
        pixelY[k] = pixelY[k - 1] + _rightLabelGap;
      }
    }
    if (pixelY.last > plotHeight - 4) {
      final overflow = pixelY.last - (plotHeight - 4);
      for (var k = 0; k < pixelY.length; k++) {
        pixelY[k] -= overflow;
      }
    }
    if (pixelY.first < 4) {
      final overflow = 4 - pixelY.first;
      for (var k = 0; k < pixelY.length; k++) {
        pixelY[k] += overflow;
      }
    }
    for (var k = 0; k < order.length; k++) {
      labels[order[k]].dy = pixelY[k] - toPixel(labels[order[k]].y);
    }
  }

  LineChartBarData _markerBar(_ActionMarker marker) {
    return LineChartBarData(
      spots: [FlSpot(marker.index.toDouble(), marker.price)],
      color: marker.color,
      barWidth: 0,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) => _LabeledDotPainter(
          color: marker.color,
          label: marker.label,
          price: formatInr(marker.price),
        ),
      ),
    );
  }

  List<_ActionMarker> _actionMarkers(Stock? holding) {
    if (holding == null || _history.isEmpty) return [];
    final raw = <_ActionMarkerDraft>[
      _ActionMarkerDraft(
        label: 'Buy',
        color: _buyColor,
        price: holding.lastBuyPrice,
        date: holding.lastBuyDate,
      ),
      _ActionMarkerDraft(
        label: 'Sell',
        color: _sellColor,
        price: holding.lastSalePrice,
        date: holding.lastSaleDate,
      ),
      _ActionMarkerDraft(
        label: 'Hold',
        color: _holdColor,
        price: holding.lastHoldPrice,
        date: holding.lastHoldDate,
      ),
    ];

    final markers = <_ActionMarker>[];
    for (final item in raw) {
      if (item.price <= 0 || item.date == null) continue;
      final index = _indexForDateInRange(item.date!);
      if (index == null) continue;
      markers.add(
        _ActionMarker(
          label: item.label,
          price: item.price,
          color: item.color,
          index: index,
        ),
      );
    }
    return markers;
  }

  int? _indexForDateInRange(DateTime date) {
    final first = _historyDay(0);
    final last = _historyDay(_history.length - 1);
    if (first == null || last == null) return null;
    final day = _asDay(date);
    if (day.isBefore(first)) return null;
    if (day.isAfter(last.add(const Duration(days: 5)))) return null;

    var best = 0;
    var bestDiff = 1 << 30;
    for (var i = 0; i < _history.length; i++) {
      final historyDay = _historyDay(i);
      if (historyDay == null) continue;
      final diff = (historyDay.difference(day).inDays).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  DateTime? _historyDay(int index) {
    if (index < 0 || index >= _history.length) return null;
    final raw = _history[index]['date']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? null : _asDay(parsed);
  }

  DateTime _asDay(DateTime date) {
    final local = date.isUtc ? date.toLocal() : date;
    return DateTime(local.year, local.month, local.day);
  }

  StockTrend? _trendFor(Stock? holding) {
    if (holding == null) return null;
    try {
      return context
          .read<FinanceProvider>()
          .stockTrends
          .firstWhere((t) => t.stockId == holding.id);
    } catch (_) {
      return null;
    }
  }

  _DmaLevel? _dmaLevel(List<double> prices, int period, double? preferred) {
    if (prices.length < 2 || period <= 0) return null;
    final value = (preferred != null && preferred > 0)
        ? preferred
        : _trailingSma(prices, period);
    if (value == null || value <= 0) return null;
    final start = math.max(0, prices.length - period);
    return _DmaLevel(
      value: value,
      spots: [
        for (var i = start; i < prices.length; i++) FlSpot(i.toDouble(), value),
      ],
    );
  }

  double? _trailingSma(List<double> prices, int period) {
    if (prices.length < period || period <= 0) return null;
    var sum = 0.0;
    for (var i = prices.length - period; i < prices.length; i++) {
      sum += prices[i];
    }
    return sum / period;
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
                DataColumn(label: Text('Sale Price'), numeric: true),
                DataColumn(label: Text('Sale Date')),
                DataColumn(label: Text('Account')),
                DataColumn(label: Text('Brokerage'), numeric: true),
              ],
              rows: _transactions.map((tx) {
                final type = (tx['type'] as String? ?? '').toLowerCase();
                final isBuy = type == 'buy';
                final dateStr = tx['transaction_date'] as String?;
                final date =
                    dateStr != null ? DateTime.parse(dateStr).toLocal() : null;
                final remaining = (tx['quantity'] as num?)?.toDouble() ?? 0;
                final originalQty =
                    (tx['original_quantity'] as num?)?.toDouble() ?? remaining;
                final price = (tx['price'] as num?)?.toDouble() ?? 0;
                final salePrice = (tx['sale_price'] as num?)?.toDouble() ?? 0;
                final saleDateStr = tx['sale_date'] as String?;
                final saleDate = saleDateStr != null && saleDateStr.isNotEmpty
                    ? DateTime.tryParse(saleDateStr)?.toLocal()
                    : null;
                final source = tx['source'] as String? ?? '';
                final qtyDisplay = isBuy ? originalQty : remaining;
                final brokerage = (tx['brokerage'] as num?)?.toDouble() ?? 0;

                String feeText(double value) {
                  if (value <= 0) return '-';
                  return formatInr(value);
                }

                return DataRow(
                  cells: [
                    DataCell(Text(
                      date != null
                          ? DateFormat('dd MMM yyyy').format(date)
                          : '-',
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
                    DataCell(Text(
                      isBuy && salePrice > 0 ? formatInr(salePrice) : '-',
                    )),
                    DataCell(Text(
                      isBuy && saleDate != null
                          ? DateFormat('dd MMM yyyy').format(saleDate)
                          : '-',
                    )),
                    DataCell(Text(source.isNotEmpty ? source : '-')),
                    DataCell(Text(feeText(brokerage))),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

class _ActionMarkerDraft {
  final String label;
  final Color color;
  final double price;
  final DateTime? date;

  const _ActionMarkerDraft({
    required this.label,
    required this.color,
    required this.price,
    required this.date,
  });
}

class _ActionMarker {
  final String label;
  final double price;
  final Color color;
  final int index;

  const _ActionMarker({
    required this.label,
    required this.price,
    required this.color,
    required this.index,
  });
}

class _RightLabel {
  final double y;
  final String text;
  final Color color;
  double dy = 0;

  _RightLabel({
    required this.y,
    required this.text,
    required this.color,
  });
}

class _DmaLevel {
  final double value;
  final List<FlSpot> spots;

  const _DmaLevel({required this.value, required this.spots});
}

class _RightEdgeLabelPainter extends FlDotPainter {
  _RightEdgeLabelPainter({
    required this.color,
    required this.label,
    this.dy = 0,
    this.showDot = false,
  });

  final Color color;
  final String label;
  final double dy;
  final bool showDot;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    if (showDot) {
      canvas.drawCircle(
        offsetInCanvas,
        3,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          shadows: const [
            Shadow(color: Colors.white, blurRadius: 3),
            Shadow(color: Colors.white, blurRadius: 3),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        offsetInCanvas.dx + 6,
        offsetInCanvas.dy - tp.height / 2 + dy,
      ),
    );
  }

  @override
  Size getSize(FlSpot spot) => const Size(6, 6);

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;

  @override
  List<Object?> get props => [color, label, dy, showDot];
}

class _LabeledDotPainter extends FlDotPainter {
  _LabeledDotPainter({
    required this.color,
    required this.label,
    required this.price,
  });

  final Color color;
  final String label;
  final String price;
  static const double _radius = 5.5;
  static const double _strokeWidth = 1.5;
  static const Color _strokeColor = Colors.white;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    canvas.drawCircle(
      offsetInCanvas,
      _radius + (_strokeWidth / 2),
      Paint()
        ..color = _strokeColor
        ..strokeWidth = _strokeWidth
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(
      offsetInCanvas,
      _radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: label),
          TextSpan(text: '\n$price'),
        ],
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.15,
          shadows: const [
            Shadow(color: Colors.white, blurRadius: 3),
            Shadow(color: Colors.white, blurRadius: 3),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        offsetInCanvas.dx - tp.width / 2,
        offsetInCanvas.dy + _radius + _strokeWidth + 2,
      ),
    );
  }

  @override
  Size getSize(FlSpot spot) => const Size(_radius * 2, _radius * 2);

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;

  @override
  List<Object?> get props => [color, label, price];
}

class _ChartHoverLine {
  const _ChartHoverLine({required this.name, required this.price});

  final String name;
  final double price;
}

class _HoverTooltipLayoutDelegate extends SingleChildLayoutDelegate {
  _HoverTooltipLayoutDelegate({
    required this.anchor,
    required this.bounds,
  });

  final Offset anchor;
  final Size bounds;

  static const double _gap = 8;
  static const double _inset = 4;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.min(200, math.max(80, bounds.width - _inset * 2)),
      maxHeight: math.max(40, bounds.height - _inset * 2),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = math.max(_inset, bounds.width - childSize.width - _inset);
    final dx = (anchor.dx - childSize.width / 2).clamp(_inset, maxLeft);
    final above = anchor.dy - _gap - childSize.height;
    final maxTop = math.max(_inset, bounds.height - childSize.height - _inset);
    final dy = above >= _inset
        ? above
        : (anchor.dy + _gap).clamp(_inset, maxTop);
    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_HoverTooltipLayoutDelegate oldDelegate) {
    return anchor != oldDelegate.anchor || bounds != oldDelegate.bounds;
  }
}
