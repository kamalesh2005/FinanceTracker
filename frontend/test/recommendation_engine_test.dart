import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/stock.dart';
import 'package:finance_tracker/models/stock_trend.dart';
import 'package:finance_tracker/services/recommendation_engine.dart';

Stock _stock({
  double currentPrice = 90,
  double buyPrice = 100,
  double setBuyPrice = 0,
  double setStopLossPrice = 0,
  double setProfitBookingPrice = 0,
  double lastBuyPrice = 0,
  DateTime? lastBuyDate,
  String lastBuyTrend = '',
  DateTime? bshClearDate,
}) {
  final now = DateTime.now();
  return Stock(
    id: 1,
    symbol: 'TEST',
    name: 'Test',
    quantity: 1,
    buyPrice: buyPrice,
    currentPrice: currentPrice,
    createdAt: now,
    updatedAt: now,
    setBuyPrice: setBuyPrice,
    setStopLossPrice: setStopLossPrice,
    setProfitBookingPrice: setProfitBookingPrice,
    lastBuyPrice: lastBuyPrice,
    lastBuyDate: lastBuyDate,
    lastBuyTrend: lastBuyTrend,
    bshClearDate: bshClearDate,
  );
}

StockTrend _trend(String label) {
  return StockTrend(
    stockId: 1,
    symbol: 'TEST',
    currentPrice: 100,
    ma7: 0,
    ma20: 0,
    ma50: 0,
    stockSTDelta: 0,
    marketSTDelta: 0,
    adjustedSTDelta: 0,
    stockMTDelta: 0,
    marketMTDelta: 0,
    adjustedMTDelta: 0,
    trend: label,
  );
}

RecommendationRuleset _rules(String condition) {
  return RecommendationRuleset(
    rules: [
      RecommendationRule(
        order: 1,
        recommendation: 'MATCH',
        condition: condition,
        onMatch: 'exit',
      ),
    ],
  );
}

void main() {
  test('unset set_buy_price does not match curr_price comparison', () {
    expect(
      RecommendationEngine.evaluate(
        _stock(currentPrice: 90, setBuyPrice: 0),
        null,
        _rules('curr_price < set_buy_price'),
      ),
      'NO ACTION REQD',
    );
  });

  test('set set_buy_price matches curr_price comparison', () {
    expect(
      RecommendationEngine.evaluate(
        _stock(currentPrice: 90, setBuyPrice: 100),
        null,
        _rules('curr_price < set_buy_price'),
      ),
      'MATCH',
    );
  });

  test('unset set_stop_loss_price does not match', () {
    expect(
      RecommendationEngine.evaluate(
        _stock(currentPrice: 90, setStopLossPrice: 0),
        null,
        _rules('curr_price < set_stop_loss_price'),
      ),
      'NO ACTION REQD',
    );
  });

  test('OR branch still matches when threshold is unset', () {
    expect(
      RecommendationEngine.evaluate(
        _stock(currentPrice: 90, buyPrice: 100, setBuyPrice: 0),
        null,
        _rules('(curr_price < set_buy_price) OR (curr_price < avg_buy_price)'),
      ),
      'MATCH',
    );
  });

  test('unset set_profit_booking_price does not match greater-than', () {
    expect(
      RecommendationEngine.evaluate(
        _stock(currentPrice: 90, setProfitBookingPrice: 0),
        null,
        _rules('curr_price > set_profit_booking_price'),
      ),
      'NO ACTION REQD',
    );
  });

  test('last buy within validity days matches last_trade_is_buy', () {
    final now = DateTime.now();
    expect(
      RecommendationEngine.evaluate(
        _stock(
          currentPrice: 100,
          lastBuyPrice: 100,
          lastBuyDate: now.subtract(const Duration(days: 10)),
        ),
        null,
        RecommendationRuleset.defaults(),
      ),
      'AT BUY PRICE',
    );
  });

  test('last buy older than validity days is ignored', () {
    final now = DateTime.now();
    expect(
      RecommendationEngine.evaluate(
        _stock(
          currentPrice: 100,
          lastBuyPrice: 100,
          lastBuyDate: now.subtract(const Duration(days: 31)),
        ),
        null,
        RecommendationRuleset.defaults(),
      ),
      'NO ACTION REQD',
    );
  });

  test('last buy before bsh_clear_date is ignored by rules', () {
    final now = DateTime.now();
    final buyDate = now.subtract(const Duration(days: 10));
    final stock = _stock(
      currentPrice: 100,
      lastBuyPrice: 100,
      lastBuyDate: buyDate,
      bshClearDate: now,
    );
    expect(stock.lastActionLabel, 'Buy');
    expect(stock.lastActionPrice, 100);
    expect(
      RecommendationEngine.evaluate(
        stock,
        null,
        RecommendationRuleset.defaults(),
      ),
      'NO ACTION REQD',
    );
  });

  test('last buy after bsh_clear_date still matches last_trade_is_buy', () {
    final now = DateTime.now();
    expect(
      RecommendationEngine.evaluate(
        _stock(
          currentPrice: 100,
          lastBuyPrice: 100,
          lastBuyDate: now,
          bshClearDate: now.subtract(const Duration(days: 1)),
        ),
        null,
        RecommendationRuleset.defaults(),
      ),
      'AT BUY PRICE',
    );
  });

  test('last buy at price when trend matches captured trend', () {
    final now = DateTime.now();
    expect(
      RecommendationEngine.evaluate(
        _stock(
          currentPrice: 100,
          lastBuyPrice: 100,
          lastBuyDate: now.subtract(const Duration(days: 10)),
          lastBuyTrend: 'bullish',
        ),
        _trend('bullish'),
        RecommendationRuleset.defaults(),
      ),
      'AT BUY PRICE',
    );
  });

  test('last buy at price blocked when trend changed', () {
    final now = DateTime.now();
    expect(
      RecommendationEngine.evaluate(
        _stock(
          currentPrice: 100,
          buyPrice: 100,
          lastBuyPrice: 100,
          lastBuyDate: now.subtract(const Duration(days: 10)),
          lastBuyTrend: 'bullish',
        ),
        _trend('bearish_st'),
        RecommendationRuleset.defaults(),
      ),
      isNot('AT BUY PRICE'),
    );
  });

  test('last buy at price still matches when no captured trend', () {
    final now = DateTime.now();
    expect(
      RecommendationEngine.evaluate(
        _stock(
          currentPrice: 100,
          lastBuyPrice: 100,
          lastBuyDate: now.subtract(const Duration(days: 10)),
        ),
        _trend('bearish_st'),
        RecommendationRuleset.defaults(),
      ),
      'AT BUY PRICE',
    );
  });

  test('Review on adj ST/MT conflict when no other signal', () {
    expect(
      RecommendationEngine.evaluate(
        _stock(currentPrice: 100, buyPrice: 100),
        StockTrend(
          stockId: 1,
          symbol: 'TEST',
          currentPrice: 100,
          ma7: 0,
          ma20: 0,
          ma50: 0,
          stockSTDelta: 0,
          marketSTDelta: 0,
          adjustedSTDelta: 3,
          stockMTDelta: 0,
          marketMTDelta: 0,
          adjustedMTDelta: -3,
          trend: 'neutral',
        ),
        RecommendationRuleset.defaults(),
      ),
      'Review',
    );
  });

  test('BUY wins over Review when both would match', () {
    expect(
      RecommendationEngine.evaluate(
        _stock(currentPrice: 90, buyPrice: 100, setBuyPrice: 95),
        StockTrend(
          stockId: 1,
          symbol: 'TEST',
          currentPrice: 90,
          ma7: 0,
          ma20: 0,
          ma50: 0,
          stockSTDelta: 0,
          marketSTDelta: 0,
          adjustedSTDelta: 3,
          stockMTDelta: 0,
          marketMTDelta: 0,
          adjustedMTDelta: -3,
          trend: 'neutral',
        ),
        RecommendationRuleset.defaults(),
      ),
      'BUY',
    );
  });
}
