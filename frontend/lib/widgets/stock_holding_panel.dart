import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import '../models/stock.dart';
import '../models/stock_trend.dart';
import '../providers/auth_provider.dart';
import '../providers/finance_provider.dart';
import '../services/recommendation_engine.dart';
import '../utils/currency_format.dart';
import 'stock_actions.dart';

/// Header + metrics for a single holding, matching Stocks card order.
/// Pass [afterSignal] to insert the 1-year chart between Signal and Qty metrics.
class StockHoldingPanel extends StatelessWidget {
  final Stock stock;
  final VoidCallback? onDeleted;
  final Widget? afterSignal;

  const StockHoldingPanel({
    super.key,
    required this.stock,
    this.onDeleted,
    this.afterSignal,
  });

  static const double _narrowBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    return Consumer2<FinanceProvider, AuthProvider>(
      builder: (context, provider, auth, _) {
        final invested = stock.buyPrice * stock.quantity;
        final current = stock.currentPrice * stock.quantity;
        final profitLoss = current - invested;
        final profitLossPct =
            invested > 0 ? (profitLoss / invested) * 100 : 0.0;
        final narrow = MediaQuery.sizeOf(context).width < _narrowBreakpoint;
        StockTrend? trend;
        try {
          trend = provider.stockTrends.firstWhere((t) => t.stockId == stock.id);
        } catch (_) {
          trend = null;
        }
        final recommendation = RecommendationEngine.evaluate(
          stock,
          trend,
          auth.effectiveRecommendationRules,
        );
        final industryLine = _industryMarketCapLine(stock);

        return Card(
          clipBehavior: Clip.none,
          child: Padding(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < _narrowBreakpoint ? 12 : 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stock.displaySymbol,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
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
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: StockActions.cardBar(
                            context: context,
                            stock: stock,
                            provider: provider,
                            onDeleted: onDeleted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _signalTrendRow(recommendation, trend),
                if (afterSignal != null) ...[
                  const SizedBox(height: 16),
                  afterSignal!,
                ],
                const SizedBox(height: 12),
                _metricsBlock(
                  narrow: narrow,
                  children: [
                    _compact('Quantity', formatQty(stock.quantity)),
                    _compact('Buy Price', formatInr(stock.buyPrice)),
                    _compact('Current', formatInr(stock.currentPrice)),
                    _compact(
                      'Current Value',
                      formatInr(current),
                      null,
                      '@${formatInr(stock.currentPrice)}*${formatQty(stock.quantity)}',
                    ),
                    _compact(
                      'P/L',
                      formatInr(profitLoss),
                      profitLoss >= 0 ? Colors.green : Colors.red,
                    ),
                    _compact(
                      'P/L %',
                      '${profitLossPct.toStringAsFixed(2)}%',
                      profitLoss >= 0 ? Colors.green : Colors.red,
                    ),
                    if (auth.showXirr)
                      _compact(
                        'XIRR',
                        stock.xirr == null
                            ? '-'
                            : '${(stock.xirr! * 100).toStringAsFixed(2)}%',
                        stock.xirr == null
                            ? null
                            : (stock.xirr! >= 0 ? Colors.green : Colors.red),
                      ),
                  ],
                ),
                if (trend != null &&
                    (trend.ma7 > 0 || trend.ma20 > 0 || trend.ma50 > 0)) ...[
                  const Divider(height: 20),
                  if (trend.ma20 > 0 && trend.ma50 > 0)
                    _metricsBlock(
                      narrow: narrow,
                      children: [
                        _compact(
                          'Stock ST Δ',
                          '${trend.stockSTDelta.toStringAsFixed(2)}%',
                          trend.stockSTDelta >= 0 ? Colors.green : Colors.red,
                        ),
                        _compact(
                          'Sensex ST Δ',
                          '${trend.marketSTDelta.toStringAsFixed(2)}%',
                          trend.marketSTDelta >= 0 ? Colors.green : Colors.red,
                        ),
                        _compact(
                          'Adj ST Δ',
                          '${trend.adjustedSTDelta.toStringAsFixed(2)}%',
                          trend.adjustedSTDelta >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                        _compact(
                          'Stock MT Δ',
                          '${trend.stockMTDelta.toStringAsFixed(2)}%',
                          trend.stockMTDelta >= 0 ? Colors.green : Colors.red,
                        ),
                        _compact(
                          'Sensex MT Δ',
                          '${trend.marketMTDelta.toStringAsFixed(2)}%',
                          trend.marketMTDelta >= 0 ? Colors.green : Colors.red,
                        ),
                        _compact(
                          'Adj MT Δ',
                          '${trend.adjustedMTDelta.toStringAsFixed(2)}%',
                          trend.adjustedMTDelta >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _compact(
                            'Stock ST Δ',
                            '${trend.stockSTDelta.toStringAsFixed(2)}%',
                            trend.stockSTDelta >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _compact(
                            'Sensex ST Δ',
                            '${trend.marketSTDelta.toStringAsFixed(2)}%',
                            trend.marketSTDelta >= 0
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _compact(
                            'Adj ST Δ',
                            '${trend.adjustedSTDelta.toStringAsFixed(2)}%',
                            trend.adjustedSTDelta >= 0
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ],
                    ),
                ],
                const Divider(height: 20),
                _labeled('News', _NewsTeaser(stock: stock)),
                const Divider(height: 20),
                _labeled(
                  'Notes',
                  StockActions.notesCell(
                    context: context,
                    stock: stock,
                    provider: provider,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _industryMarketCapLine(Stock stock) {
    final industry = stock.industry.trim();
    final marketCap = stock.marketCap.trim();
    if (industry.isEmpty && marketCap.isEmpty) return null;
    if (industry.isEmpty) return '($marketCap)';
    if (marketCap.isEmpty) return industry;
    return '$industry ($marketCap)';
  }

  Widget _signalTrendRow(String recommendation, StockTrend? trend) {
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
        Flexible(child: _signalBadge(recommendation)),
        const SizedBox(width: 8),
        if (trend != null)
          _trendBadge(trend.trend)
        else
          Text('-',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _signalBadge(String recommendation) {
    Color color = Colors.grey;
    if (recommendation.contains('SELL') && recommendation != 'AT SELL PRICE') {
      color = Colors.red;
    } else if (recommendation.contains('Book Profit')) {
      color = Colors.orange;
    } else if (recommendation.contains('BUY') &&
        recommendation != 'AT BUY PRICE') {
      color = Colors.green;
    } else if (recommendation == 'Review') {
      color = Colors.blue;
    }
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

  Widget _trendBadge(String trend) {
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
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compact(
    String label,
    String value, [
    Color? valueColor,
    String? subtitle,
  ]) {
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
        if (subtitle != null && subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _metricsBlock({
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

  Widget _labeled(String label, Widget value) {
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
}

class _NewsTeaser extends StatelessWidget {
  final Stock stock;

  const _NewsTeaser({required this.stock});

  Color _typeColor(String raw) {
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

  String _formatType(String raw) {
    final label = raw.trim().replaceAll('_', ' ');
    if (label.isEmpty) return '';
    return label.toUpperCase();
  }

  bool _openUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return false;
    }
    web.window.open(url, '_blank');
    return true;
  }

  @override
  Widget build(BuildContext context) {
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
                      style: teaserStyle.copyWith(color: typeColor)),
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
}
