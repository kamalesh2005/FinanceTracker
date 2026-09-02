import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../../models/stock.dart';
import '../../models/stock_trend.dart';
import '../../utils/currency_format.dart';

/// Shared stock display helpers for Learner Portal holdings UI,
/// matching the main portal Stocks screen visuals.
class LearnerStockDisplay {
  static const narrowCardBreakpoint = 400.0;

  static String? industryMarketCapLine(Stock stock) {
    final industry = stock.industry.trim();
    final marketCap = stock.marketCap.trim();
    if (industry.isEmpty && marketCap.isEmpty) return null;
    if (industry.isEmpty) return '($marketCap)';
    if (marketCap.isEmpty) return industry;
    return '$industry ($marketCap)';
  }

  static String trendDisplayLabel(String trend) {
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

  static Color recommendationColor(String recommendation) {
    if (recommendation.contains('SELL') &&
        recommendation != 'AT SELL PRICE') {
      return Colors.red;
    }
    if (recommendation.contains('Book Profit')) return Colors.orange;
    if (recommendation.contains('BUY') && recommendation != 'AT BUY PRICE') {
      return Colors.green;
    }
    return Colors.grey;
  }

  static Widget recommendationBadge(String recommendation) {
    final color = recommendationColor(recommendation);
    final isDefault = recommendation == 'NO ACTION REQD' ||
        recommendation == 'AT BUY PRICE' ||
        recommendation == 'AT SELL PRICE' ||
        recommendation == 'AT HOLD PRICE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
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
  }

  static Widget trendBadge(String trend) {
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
          Text(
            trendDisplayLabel(trend),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static Widget signalTrendRow({
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
        Flexible(child: recommendationBadge(recommendation)),
        const SizedBox(width: 8),
        if (trend != null)
          trendBadge(trend.trend)
        else
          Text('-',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  static Widget compact(String label, String value, [Color? valueColor]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
      ],
    );
  }

  static Widget labeled(String label, Widget value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          child: value,
        ),
      ],
    );
  }

  static Widget cardMetricsBlock({
    required bool narrow,
    required List<Widget> children,
  }) {
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

  static Widget metricsBlock({
    required bool narrow,
    required List<Widget> children,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    Widget rowOf(List<Widget> items) {
      final padded = [...items];
      while (padded.length < 3) {
        padded.add(const SizedBox.shrink());
      }
      return Row(
        children: [
          for (var i = 0; i < padded.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: padded[i]),
          ],
        ],
      );
    }

    if (!narrow) {
      return Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: children[i]),
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 3) {
      final end = (i + 3).clamp(0, children.length);
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(rowOf(children.sublist(i, end)));
    }
    return Column(children: rows);
  }

  static Widget priceRangeSection(Stock stock) {
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
        compactPriceRangeBar(stock),
      ],
    );
  }

  static Widget compactPriceRangeBar(Stock stock) {
    final sixthLow = stock.sixthLowestPrice;
    final sixthHigh = stock.sixthHighestPrice;
    final currentPrice = stock.currentPrice;
    final buyPrice = stock.buyPrice;
    final currentLabel = formatInr(currentPrice);
    final buyLabel = formatInr(buyPrice);

    final range = sixthHigh - sixthLow;
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
        final labelsOverlap = currentLabelLeft < buyLabelLeft + buyLabelWidth &&
            buyLabelLeft < currentLabelLeft + currentLabelWidth;
        const stackedLabelHeight = 26.0;
        const singleLabelHeight = 14.0;
        final labelBandHeight =
            labelsOverlap ? stackedLabelHeight : singleLabelHeight;
        const currentLabelTop = 0.0;
        final buyLabelTop = labelsOverlap ? 12.0 : 0.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: labelBandHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: buyLabelLeft,
                    top: buyLabelTop,
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
                    top: currentLabelTop,
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
          ],
        );
      },
    );
  }

  static Widget newsTeaser(Stock stock) {
    if (!stock.hasNewsContent) {
      return Text('No data',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600));
    }
    final typeColor = _typeColor(stock.consensusType);
    final typeLine = _formatType(stock.consensusType);
    final targetLine = stock.consensusTarget > 0
        ? '1Y @ ${formatInr(stock.consensusTarget)}'
        : '';
    final upsideSign = stock.consensusUpside >= 0 ? '+' : '';
    final showUpside = stock.consensusUpside != 0 || stock.consensusTarget > 0;
    final upsideLine = showUpside
        ? '$upsideSign${stock.consensusUpside.toStringAsFixed(2)}%'
        : '';
    final upsideColor = stock.consensusUpside >= 0 ? Colors.green : Colors.red;
    const teaserStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (targetLine.isNotEmpty ||
            upsideLine.isNotEmpty ||
            typeLine.isNotEmpty)
          Text.rich(
            TextSpan(
              children: [
                if (targetLine.isNotEmpty)
                  TextSpan(
                    text: targetLine,
                    style: teaserStyle.copyWith(color: typeColor),
                  ),
                if (upsideLine.isNotEmpty)
                  TextSpan(
                    text: targetLine.isNotEmpty ? ' ($upsideLine)' : upsideLine,
                    style: teaserStyle.copyWith(color: upsideColor),
                  ),
                if (typeLine.isNotEmpty) ...[
                  if (targetLine.isNotEmpty || upsideLine.isNotEmpty)
                    TextSpan(
                      text: ' - ',
                      style: teaserStyle.copyWith(color: Colors.grey.shade700),
                    ),
                  TextSpan(
                    text: typeLine,
                    style: teaserStyle.copyWith(color: typeColor),
                  ),
                ],
              ],
            ),
          ),
        if (stock.hasNewsHeadline) ...[
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _openUrl(stock.newsUrl),
            child: Text(
              stock.newsHeadline.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade800,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static Color _typeColor(String raw) {
    return switch (raw.trim().toLowerCase().replaceAll(' ', '_')) {
      'buy' ||
      'strong_buy' ||
      'accumulate' ||
      'outperform' =>
        Colors.green.shade700,
      'sell' || 'strong_sell' || 'underperform' => Colors.red.shade700,
      'hold' || 'neutral' => Colors.orange.shade800,
      _ => Colors.teal.shade800,
    };
  }

  static String _formatType(String raw) {
    final label = raw.trim().replaceAll('_', ' ');
    if (label.isEmpty) return '';
    return label.toUpperCase();
  }

  static void _openUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return;
    }
    web.window.open(url, '_blank');
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
