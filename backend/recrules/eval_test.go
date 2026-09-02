package recrules

import (
	"testing"
	"time"
)

func rulesWithCondition(condition string) Ruleset {
	return Ruleset{
		Rules: []Rule{{
			Order:          1,
			Recommendation: "MATCH",
			Condition:      condition,
			OnMatch:        OnMatchExit,
			Enabled:        true,
		}},
	}
}

func holding(currentPrice, buyPrice, setBuy, setStop, setProfit float64) HoldingInput {
	return HoldingInput{
		CurrPrice:             currentPrice,
		AvgBuyPrice:           buyPrice,
		SetBuyPrice:           setBuy,
		SetStopLossPrice:      setStop,
		SetProfitBookingPrice: setProfit,
		Now:                   time.Now(),
	}
}

func TestUnsetSetBuyPriceDoesNotMatch(t *testing.T) {
	ctx := BuildEvaluateContext(holding(90, 100, 0, 0, 0), rulesWithCondition("curr_price < set_buy_price"))
	got := Evaluate(rulesWithCondition("curr_price < set_buy_price"), ctx)
	if got != noActionRequired {
		t.Fatalf("got %q want %q", got, noActionRequired)
	}
}

func TestSetBuyPriceMatches(t *testing.T) {
	h := holding(90, 100, 100, 0, 0)
	rs := rulesWithCondition("curr_price < set_buy_price")
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got != "MATCH" {
		t.Fatalf("got %q want MATCH", got)
	}
}

func TestUnsetSetStopLossPriceDoesNotMatch(t *testing.T) {
	h := holding(90, 100, 0, 0, 0)
	rs := rulesWithCondition("curr_price < set_stop_loss_price")
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got != noActionRequired {
		t.Fatalf("got %q want %q", got, noActionRequired)
	}
}

func TestORBranchStillMatchesWhenThresholdUnset(t *testing.T) {
	h := holding(90, 100, 0, 0, 0)
	rs := rulesWithCondition("(curr_price < set_buy_price) OR (curr_price < avg_buy_price)")
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got != "MATCH" {
		t.Fatalf("got %q want MATCH", got)
	}
}

func TestUnsetProfitBookingDoesNotMatch(t *testing.T) {
	h := holding(90, 100, 0, 0, 0)
	rs := rulesWithCondition("curr_price > set_profit_booking_price")
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got != noActionRequired {
		t.Fatalf("got %q want %q", got, noActionRequired)
	}
}

func TestLastBuyWithinValidityMatchesAtBuyPrice(t *testing.T) {
	now := time.Now()
	h := HoldingInput{
		CurrPrice:    100,
		LastBuyPrice: 100,
		LastBuyDate:  ptrTime(now.Add(-10 * 24 * time.Hour)),
		Now:          now,
	}
	rs := DefaultRuleset(5)
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got != "AT BUY PRICE" {
		t.Fatalf("got %q want AT BUY PRICE", got)
	}
}

func TestLastBuyOlderThanValidityIgnored(t *testing.T) {
	now := time.Now()
	h := HoldingInput{
		CurrPrice:    100,
		LastBuyPrice: 100,
		LastBuyDate:  ptrTime(now.Add(-31 * 24 * time.Hour)),
		Now:          now,
	}
	rs := DefaultRuleset(5)
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got != noActionRequired {
		t.Fatalf("got %q want %q", got, noActionRequired)
	}
}

func TestLastBuyBeforeBSHClearIgnored(t *testing.T) {
	now := time.Now()
	buyDate := now.Add(-10 * 24 * time.Hour)
	h := HoldingInput{
		CurrPrice:    100,
		LastBuyPrice: 100,
		LastBuyDate:  &buyDate,
		BSHClearDate: &now,
		Now:          now,
	}
	rs := DefaultRuleset(5)
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got != noActionRequired {
		t.Fatalf("got %q want %q", got, noActionRequired)
	}
}

func TestLastBuyAfterBSHClearMatches(t *testing.T) {
	now := time.Now()
	clearDate := now.Add(-24 * time.Hour)
	h := HoldingInput{
		CurrPrice:    100,
		LastBuyPrice: 100,
		LastBuyDate:  &now,
		BSHClearDate: &clearDate,
		Now:          now,
	}
	rs := DefaultRuleset(5)
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got != "AT BUY PRICE" {
		t.Fatalf("got %q want AT BUY PRICE", got)
	}
}

func TestLastBuyAtPriceWhenTrendMatches(t *testing.T) {
	now := time.Now()
	buyDate := now.Add(-10 * 24 * time.Hour)
	h := HoldingInput{
		CurrPrice:    100,
		LastBuyPrice: 100,
		LastBuyDate:  &buyDate,
		LastBuyTrend: "bullish",
		Trend:        "bullish",
		Now:          now,
	}
	rs := DefaultRuleset(5)
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got != "AT BUY PRICE" {
		t.Fatalf("got %q want AT BUY PRICE", got)
	}
}

func TestLastBuyAtPriceBlockedWhenTrendChanged(t *testing.T) {
	now := time.Now()
	buyDate := now.Add(-10 * 24 * time.Hour)
	h := HoldingInput{
		CurrPrice:    100,
		AvgBuyPrice:  100,
		LastBuyPrice: 100,
		LastBuyDate:  &buyDate,
		LastBuyTrend: "bullish",
		Trend:        "bearish_st",
		Now:          now,
	}
	rs := DefaultRuleset(5)
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got == "AT BUY PRICE" {
		t.Fatalf("got %q want something other than AT BUY PRICE", got)
	}
}

func TestLastBuyAtPriceLegacyNoCapturedTrend(t *testing.T) {
	now := time.Now()
	buyDate := now.Add(-10 * 24 * time.Hour)
	h := HoldingInput{
		CurrPrice:    100,
		LastBuyPrice: 100,
		LastBuyDate:  &buyDate,
		Trend:        "bearish_st",
		Now:          now,
	}
	rs := DefaultRuleset(5)
	ctx := BuildEvaluateContext(h, rs)
	got := Evaluate(rs, ctx)
	if got != "AT BUY PRICE" {
		t.Fatalf("got %q want AT BUY PRICE", got)
	}
}

func TestIsActionableSignal(t *testing.T) {
	cases := []struct {
		signal string
		want   bool
	}{
		{"BUY", true},
		{"SELL", true},
		{"Book Profit", true},
		{"BUY OR Book Profit", true},
		{"AT BUY PRICE", false},
		{"AT SELL PRICE", false},
		{"NO ACTION REQD", false},
	}
	for _, tc := range cases {
		if got := IsActionableSignal(tc.signal); got != tc.want {
			t.Fatalf("IsActionableSignal(%q)=%v want %v", tc.signal, got, tc.want)
		}
	}
}

func ptrTime(t time.Time) *time.Time { return &t }
