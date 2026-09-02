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

class LearnerStockCard extends StatelessWidget {
  final Stock stock;
  final int challengeId;
  final bool tradingOpen;
  final StockTrend? trend;
  final String recommendation;

  const LearnerStockCard({
    super.key,
    required this.stock,
    required this.challengeId,
    required this.tradingOpen,
    required this.trend,
    required this.recommendation,
  });

  void _openDetail(BuildContext context) {
    Navigator.push(
      context,
      appPageRoute(
        LearnerHoldingDetailScreen(
          challengeId: challengeId,
          symbol: stock.symbol,
          stockId: stock.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LearnerProvider>();
    final showXirr = context.watch<AuthProvider>().showXirr;
    final invested = stock.buyPrice * stock.quantity;
    final current = stock.currentPrice * stock.quantity;
    final profitLoss = current - invested;
    final profitLossPct = invested > 0 ? (profitLoss / invested) * 100 : 0.0;
    final narrowCard = MediaQuery.sizeOf(context).width <
        LearnerStockDisplay.narrowCardBreakpoint;
    final industryLine = LearnerStockDisplay.industryMarketCapLine(stock);

    final metrics = <Widget>[
      LearnerStockDisplay.compact(
        'Quantity',
        stock.quantity.toStringAsFixed(2),
      ),
      LearnerStockDisplay.compact('Buy Price', formatInr(stock.buyPrice)),
      LearnerStockDisplay.compact('Current', formatInr(stock.currentPrice)),
      LearnerStockDisplay.compact('Current Value', formatInr(current)),
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
    ];
    if (showXirr) {
      metrics.add(
        LearnerStockDisplay.compact(
          'XIRR',
          stock.xirr == null
              ? '-'
              : '${(stock.xirr! * 100).toStringAsFixed(2)}%',
          stock.xirr == null
              ? null
              : (stock.xirr! >= 0 ? Colors.green : Colors.red),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openDetail(context),
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
              trend: trend,
            ),
            if (stock.sixthHighestPrice > 0 && stock.sixthLowestPrice > 0) ...[
              const Divider(height: 16),
              LearnerStockDisplay.priceRangeSection(stock),
            ],
            const SizedBox(height: 12),
            if (metrics.length == 6)
              LearnerStockDisplay.cardMetricsBlock(
                narrow: narrowCard,
                children: metrics,
              )
            else
              LearnerStockDisplay.metricsBlock(
                narrow: narrowCard,
                children: metrics,
              ),
            if (trend != null &&
                (trend!.ma7 > 0 || trend!.ma20 > 0 || trend!.ma50 > 0)) ...[
              const Divider(height: 20),
              Row(
                children: [
                  if (trend!.ma7 > 0)
                    Expanded(
                      child: LearnerStockDisplay.compact(
                        '7-DMA',
                        formatInr(trend!.ma7),
                      ),
                    ),
                  if (trend!.ma7 > 0 && trend!.ma20 > 0)
                    const SizedBox(width: 8),
                  if (trend!.ma20 > 0)
                    Expanded(
                      child: LearnerStockDisplay.compact(
                        '20-DMA',
                        formatInr(trend!.ma20),
                      ),
                    ),
                  if (trend!.ma20 > 0 && trend!.ma50 > 0)
                    const SizedBox(width: 8),
                  if (trend!.ma50 > 0)
                    Expanded(
                      child: LearnerStockDisplay.compact(
                        '50-DMA',
                        formatInr(trend!.ma50),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (trend!.ma20 > 0 && trend!.ma50 > 0)
                LearnerStockDisplay.metricsBlock(
                  narrow: narrowCard,
                  children: [
                    LearnerStockDisplay.compact(
                      'Stock ST Δ',
                      '${trend!.stockSTDelta.toStringAsFixed(2)}%',
                      trend!.stockSTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    LearnerStockDisplay.compact(
                      'Sensex ST Δ',
                      '${trend!.marketSTDelta.toStringAsFixed(2)}%',
                      trend!.marketSTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    LearnerStockDisplay.compact(
                      'Adj ST Δ',
                      '${trend!.adjustedSTDelta.toStringAsFixed(2)}%',
                      trend!.adjustedSTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    LearnerStockDisplay.compact(
                      'Stock MT Δ',
                      '${trend!.stockMTDelta.toStringAsFixed(2)}%',
                      trend!.stockMTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    LearnerStockDisplay.compact(
                      'Sensex MT Δ',
                      '${trend!.marketMTDelta.toStringAsFixed(2)}%',
                      trend!.marketMTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    LearnerStockDisplay.compact(
                      'Adj MT Δ',
                      '${trend!.adjustedMTDelta.toStringAsFixed(2)}%',
                      trend!.adjustedMTDelta >= 0 ? Colors.green : Colors.red,
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: LearnerStockDisplay.compact(
                        'Stock ST Δ',
                        '${trend!.stockSTDelta.toStringAsFixed(2)}%',
                        trend!.stockSTDelta >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LearnerStockDisplay.compact(
                        'Sensex ST Δ',
                        '${trend!.marketSTDelta.toStringAsFixed(2)}%',
                        trend!.marketSTDelta >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LearnerStockDisplay.compact(
                        'Adj ST Δ',
                        '${trend!.adjustedSTDelta.toStringAsFixed(2)}%',
                        trend!.adjustedSTDelta >= 0 ? Colors.green : Colors.red,
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
  }
}
