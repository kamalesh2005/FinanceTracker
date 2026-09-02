import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/stock.dart';
import '../../models/stock_trend.dart';
import '../../providers/auth_provider.dart';
import '../../services/recommendation_engine.dart';
import '../../utils/currency_format.dart';
import '../learner_provider.dart';
import 'learner_stock_actions.dart';
import 'learner_stock_display.dart';

/// Header + metrics for a single learner holding, matching main portal
/// [StockHoldingPanel]. Pass [afterSignal] to insert the chart between Signal
/// and Qty metrics.
class LearnerStockHoldingPanel extends StatelessWidget {
  final Stock stock;
  final int challengeId;
  final bool tradingOpen;
  final StockTrend? trend;
  final Widget? afterSignal;

  const LearnerStockHoldingPanel({
    super.key,
    required this.stock,
    required this.challengeId,
    required this.tradingOpen,
    this.trend,
    this.afterSignal,
  });

  static const double _narrowBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    return Consumer2<LearnerProvider, AuthProvider>(
      builder: (context, provider, auth, _) {
        final invested = stock.buyPrice * stock.quantity;
        final current = stock.currentPrice * stock.quantity;
        final profitLoss = current - invested;
        final profitLossPct =
            invested > 0 ? (profitLoss / invested) * 100 : 0.0;
        final narrow = MediaQuery.sizeOf(context).width < _narrowBreakpoint;
        final resolvedTrend = trend ?? provider.trendFor(stock.id);
        final recommendation = RecommendationEngine.evaluate(
          stock,
          resolvedTrend,
          auth.effectiveRecommendationRules,
        );
        final industryLine = LearnerStockDisplay.industryMarketCapLine(stock);

        return Card(
          clipBehavior: Clip.none,
          child: Padding(
            padding: EdgeInsets.all(narrow ? 12 : 16),
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
                            stock.symbol,
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
                                fontSize: 12,
                                color: Colors.grey,
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
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: LearnerStockActions.cardBar(
                            context: context,
                            stock: stock,
                            challengeId: challengeId,
                            tradingOpen: tradingOpen,
                            provider: provider,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LearnerStockDisplay.signalTrendRow(
                  recommendation: recommendation,
                  trend: resolvedTrend,
                ),
                if (afterSignal != null) ...[
                  const SizedBox(height: 16),
                  afterSignal!,
                ],
                const SizedBox(height: 12),
                LearnerStockDisplay.metricsBlock(
                  narrow: narrow,
                  children: [
                    LearnerStockDisplay.compact(
                      'Quantity',
                      stock.quantity.toStringAsFixed(2),
                    ),
                    LearnerStockDisplay.compact(
                      'Buy Price',
                      formatInr(stock.buyPrice),
                    ),
                    LearnerStockDisplay.compact(
                      'Current',
                      formatInr(stock.currentPrice),
                    ),
                    LearnerStockDisplay.compact(
                      'Current Value',
                      formatInr(current),
                    ),
                    LearnerStockDisplay.compact(
                      'P/L',
                      formatInr(profitLoss),
                      profitLoss >= 0 ? Colors.green : Colors.red,
                    ),
                    LearnerStockDisplay.compact(
                      'P/L %',
                      '${profitLossPct.toStringAsFixed(2)}%',
                      profitLoss >= 0 ? Colors.green : Colors.red,
                    ),
                    if (auth.showXirr)
                      LearnerStockDisplay.compact(
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
                if (resolvedTrend != null &&
                    (resolvedTrend.ma7 > 0 ||
                        resolvedTrend.ma20 > 0 ||
                        resolvedTrend.ma50 > 0)) ...[
                  const Divider(height: 20),
                  if (resolvedTrend.ma20 > 0 && resolvedTrend.ma50 > 0)
                    LearnerStockDisplay.metricsBlock(
                      narrow: narrow,
                      children: [
                        LearnerStockDisplay.compact(
                          'Stock ST Δ',
                          '${resolvedTrend.stockSTDelta.toStringAsFixed(2)}%',
                          resolvedTrend.stockSTDelta >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                        LearnerStockDisplay.compact(
                          'Sensex ST Δ',
                          '${resolvedTrend.marketSTDelta.toStringAsFixed(2)}%',
                          resolvedTrend.marketSTDelta >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                        LearnerStockDisplay.compact(
                          'Adj ST Δ',
                          '${resolvedTrend.adjustedSTDelta.toStringAsFixed(2)}%',
                          resolvedTrend.adjustedSTDelta >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                        LearnerStockDisplay.compact(
                          'Stock MT Δ',
                          '${resolvedTrend.stockMTDelta.toStringAsFixed(2)}%',
                          resolvedTrend.stockMTDelta >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                        LearnerStockDisplay.compact(
                          'Sensex MT Δ',
                          '${resolvedTrend.marketMTDelta.toStringAsFixed(2)}%',
                          resolvedTrend.marketMTDelta >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                        LearnerStockDisplay.compact(
                          'Adj MT Δ',
                          '${resolvedTrend.adjustedMTDelta.toStringAsFixed(2)}%',
                          resolvedTrend.adjustedMTDelta >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: LearnerStockDisplay.compact(
                            'Stock ST Δ',
                            '${resolvedTrend.stockSTDelta.toStringAsFixed(2)}%',
                            resolvedTrend.stockSTDelta >= 0
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LearnerStockDisplay.compact(
                            'Sensex ST Δ',
                            '${resolvedTrend.marketSTDelta.toStringAsFixed(2)}%',
                            resolvedTrend.marketSTDelta >= 0
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LearnerStockDisplay.compact(
                            'Adj ST Δ',
                            '${resolvedTrend.adjustedSTDelta.toStringAsFixed(2)}%',
                            resolvedTrend.adjustedSTDelta >= 0
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ],
                    ),
                ],
                const Divider(height: 20),
                LearnerStockDisplay.labeled(
                  'News',
                  LearnerStockDisplay.newsTeaser(stock),
                ),
                const Divider(height: 20),
                LearnerStockDisplay.labeled(
                  'Notes',
                  LearnerStockActions.notesCell(
                    context: context,
                    stock: stock,
                    challengeId: challengeId,
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
}
