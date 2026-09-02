package recrules

import "testing"

func TestPatchSixthHighLowFieldNames(t *testing.T) {
	rs := Ruleset{
		Rules: []Rule{
			{
				Order:          5,
				Recommendation: "Book Profit",
				Condition:      `(set_profit_booking_price > 0 AND curr_price > set_profit_booking_price) OR (sixth_highest_price > 0 AND curr_price >= sixth_highest_price * 0.95 AND curr_price > avg_buy_price)`,
			},
			{
				Order:          7,
				Recommendation: "BUY",
				Condition:      `curr_price < sixth_lowest_price * 1.02`,
			},
			{
				Order:          8,
				Recommendation: "HOLD",
				Condition:      `curr_price > avg_buy_price`,
			},
		},
	}
	if !PatchSixthHighLowFieldNames(&rs) {
		t.Fatal("expected identifiers to be rewritten")
	}
	if got := rs.Rules[0].Condition; got != `(set_profit_booking_price > 0 AND curr_price > set_profit_booking_price) OR (highest_price > 0 AND curr_price >= highest_price * 0.95 AND curr_price > avg_buy_price)` {
		t.Fatalf("highest rewrite: %s", got)
	}
	if got := rs.Rules[1].Condition; got != `curr_price < lowest_price * 1.02` {
		t.Fatalf("lowest rewrite: %s", got)
	}
	if got := rs.Rules[2].Condition; got != `curr_price > avg_buy_price` {
		t.Fatalf("unrelated condition changed: %s", got)
	}
	if PatchSixthHighLowFieldNames(&rs) {
		t.Fatal("expected second pass to be a no-op")
	}
}

func TestPatchUnsetThresholdGuards(t *testing.T) {
	rs := Ruleset{
		Rules: []Rule{
			{
				Recommendation: "BUY",
				Condition:      `(set_buy_price > 0 AND curr_price < set_buy_price) OR (trend == "bullish" AND curr_price > avg_buy_price * 1.1)`,
			},
			{
				Recommendation: "SELL",
				Condition:      `(set_stop_loss_price > 0 AND curr_price < set_stop_loss_price) OR (trend == "bearish_st")`,
			},
			{
				Recommendation: "Book Profit",
				Condition:      `(set_profit_booking_price > 0 AND curr_price > set_profit_booking_price) OR (highest_price > 0 AND curr_price >= highest_price * 0.95 AND curr_price > avg_buy_price)`,
			},
			{
				Recommendation: "HOLD",
				Condition:      `curr_price > avg_buy_price AND set_buy_price > 0`,
			},
			{
				Recommendation: "KEEP",
				Condition:      `curr_price < avg_buy_price * 0.9`,
			},
		},
	}
	if !PatchUnsetThresholdGuards(&rs) {
		t.Fatal("expected > 0 guards to be stripped")
	}
	if got := rs.Rules[0].Condition; got != `(curr_price < set_buy_price) OR (trend == "bullish" AND curr_price > avg_buy_price * 1.1)` {
		t.Fatalf("BUY: %s", got)
	}
	if got := rs.Rules[1].Condition; got != `(curr_price < set_stop_loss_price) OR (trend == "bearish_st")` {
		t.Fatalf("SELL: %s", got)
	}
	if got := rs.Rules[2].Condition; got != `(curr_price > set_profit_booking_price) OR (highest_price > 0 AND curr_price >= highest_price * 0.95 AND curr_price > avg_buy_price)` {
		t.Fatalf("Book Profit: %s", got)
	}
	if got := rs.Rules[3].Condition; got != `curr_price > avg_buy_price` {
		t.Fatalf("trailing guard: %s", got)
	}
	if got := rs.Rules[4].Condition; got != `curr_price < avg_buy_price * 0.9` {
		t.Fatalf("unrelated condition changed: %s", got)
	}
	if PatchUnsetThresholdGuards(&rs) {
		t.Fatal("expected second pass to be a no-op")
	}
}

func TestPatchUnsetThresholdGuards_Nil(t *testing.T) {
	if PatchUnsetThresholdGuards(nil) {
		t.Fatal("nil ruleset should be a no-op")
	}
}

func TestDefaultRuleset_LastTradeRuleValidityDays(t *testing.T) {
	rs := DefaultRuleset(5)
	found := false
	for i, nv := range rs.NamedValues {
		if nv.Name != namedLastTradeRuleValidityDays {
			continue
		}
		found = true
		if nv.Value != defaultLastTradeRuleValidityDays {
			t.Fatalf("value=%v want %v", nv.Value, defaultLastTradeRuleValidityDays)
		}
		if i == 0 || rs.NamedValues[i-1].Name != namedFluctuationPct {
			t.Fatalf("expected %s immediately after %s", namedLastTradeRuleValidityDays, namedFluctuationPct)
		}
	}
	if !found {
		t.Fatal("missing last_trade_rule_validity_days")
	}
}

func TestEnsureLastTradeRuleValidityDays_InsertAndNoop(t *testing.T) {
	rs := Ruleset{
		NamedValues: []NamedValue{{Name: namedFluctuationPct, Value: 5}},
	}
	if !EnsureLastTradeRuleValidityDays(&rs) {
		t.Fatal("expected insert")
	}
	if len(rs.NamedValues) != 2 || rs.NamedValues[1].Name != namedLastTradeRuleValidityDays || rs.NamedValues[1].Value != 30 {
		t.Fatalf("after insert: %+v", rs.NamedValues)
	}
	rs.NamedValues[1].Value = 14
	if EnsureLastTradeRuleValidityDays(&rs) {
		t.Fatal("expected no-op when already set")
	}
	if rs.NamedValues[1].Value != 14 {
		t.Fatalf("existing value overwritten: %v", rs.NamedValues[1].Value)
	}
}

func TestPatchAtPriceTrendMatch_AppendsAndNoops(t *testing.T) {
	rs := Ruleset{
		Rules: []Rule{{
			Order:          1,
			Recommendation: "AT BUY PRICE",
			Condition:      "abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_buy",
			OnMatch:        OnMatchExit,
			Enabled:        true,
		}},
	}
	if !PatchAtPriceTrendMatch(&rs) {
		t.Fatal("expected patch")
	}
	want := "abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_buy AND trend_matches_last_action"
	if rs.Rules[0].Condition != want {
		t.Fatalf("condition=%q want %q", rs.Rules[0].Condition, want)
	}
	if PatchAtPriceTrendMatch(&rs) {
		t.Fatal("expected no-op on second patch")
	}
}
