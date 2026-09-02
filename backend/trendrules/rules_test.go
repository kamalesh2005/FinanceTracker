package trendrules

import (
	"testing"
)

func TestDefaultRulesetValidate(t *testing.T) {
	rs := DefaultRuleset()
	if err := rs.Validate(); err != nil {
		t.Fatalf("DefaultRuleset invalid: %v", err)
	}
}

func TestParseRejectsUnknownLabel(t *testing.T) {
	raw, err := DefaultRuleset().Marshal()
	if err != nil {
		t.Fatal(err)
	}
	// Corrupt one label
	rs, err := Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	rs.Rules[0].Recommendation = "super bullish"
	_, err = rs.Marshal()
	if err != nil {
		t.Fatal(err)
	}
	b, _ := rs.Marshal()
	if _, err := Parse(b); err == nil {
		t.Fatal("expected error for unknown trend label")
	}
}

func TestParseRejectsMissingLabel(t *testing.T) {
	rs := DefaultRuleset()
	rs.Rules = rs.Rules[:len(rs.Rules)-1]
	b, err := jsonMarshalUnchecked(rs)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Parse(b); err == nil {
		t.Fatal("expected error for missing trend label")
	}
}

func jsonMarshalUnchecked(rs Ruleset) (string, error) {
	// Bypass Validate by marshaling directly
	type alias Ruleset
	return (Ruleset)(rs).Marshal()
}

func TestEvalExpressions(t *testing.T) {
	ctx := map[string]any{
		"curr_price":          100.0,
		"ma7":                 90.0,
		"ma20":                80.0,
		"ma50":                70.0,
		"adjusted_st_delta":   1.0,
		"adjusted_mt_delta":   0.0,
		"st_bearish_strength": 0.0,
		"lt_bearish_strength": 0.0,
	}
	ok, err := evalBool(`curr_price > ma7 AND ma7 > ma20`, ctx)
	if err != nil || !ok {
		t.Fatalf("expected true, got %v err=%v", ok, err)
	}
	ok, err = evalBool(`TRUE`, ctx)
	if err != nil || !ok {
		t.Fatalf("TRUE: got %v err=%v", ok, err)
	}
	ok, err = evalBool(`st_bearish_strength == 2 OR lt_bearish_strength > 0`, ctx)
	if err != nil || ok {
		t.Fatalf("expected false, got %v err=%v", ok, err)
	}
}

func TestClassifyBearishStrength(t *testing.T) {
	cases := []struct {
		name                     string
		price, fast, slow, adj   float64
		want                     int
	}{
		{"strong", 50, 60, 70, -15, 2},
		{"weak_aligned", 50, 60, 70, -5, 1},
		{"weak_delta_only", 80, 60, 70, -15, 1},
		{"none", 80, 60, 70, -5, 0},
		{"zero_ma", 50, 0, 70, -15, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := ClassifyBearishStrength(tc.price, tc.fast, tc.slow, tc.adj, 10)
			if got != tc.want {
				t.Fatalf("got %d want %d", got, tc.want)
			}
		})
	}
}

// legacyClassify mirrors the previous handlers.classifyTrend for parity tests.
func legacyClassify(currentPrice, ma7, ma20, ma50, adjustedSTDelta, adjustedMTDelta float64) string {
	trend := "neutral"
	if ma7 > 0 && ma20 > 0 {
		if currentPrice > ma7 && ma7 > ma20 {
			if adjustedSTDelta > 0 {
				trend = "bullish"
			} else {
				trend = "moderately bullish"
			}
		} else if ma7 > ma20 {
			if adjustedSTDelta > 0 {
				trend = "moderately bullish"
			} else {
				trend = "neutral"
			}
		} else {
			stBearish := ClassifyBearishStrength(currentPrice, ma7, ma20, adjustedSTDelta, 10)
			ltBearish := ClassifyBearishStrength(currentPrice, ma20, ma50, adjustedMTDelta, 10)
			if stBearish > 0 {
				if ltBearish > 0 {
					if stBearish == 2 && ltBearish == 2 {
						trend = "bearish_lt"
					} else {
						trend = "moderately bearish_lt"
					}
				} else if stBearish == 2 {
					trend = "bearish_st"
				} else {
					trend = "moderately bearish_st"
				}
			}
		}
	}
	return trend
}

func TestDefaultRulesetMatchesLegacy(t *testing.T) {
	rs := DefaultRuleset()
	cases := []Inputs{
		{CurrPrice: 110, MA7: 100, MA20: 90, MA50: 80, AdjustedSTDelta: 2, AdjustedMTDelta: 1},   // bullish
		{CurrPrice: 110, MA7: 100, MA20: 90, MA50: 80, AdjustedSTDelta: -1, AdjustedMTDelta: 1},  // mod bullish aligned
		{CurrPrice: 95, MA7: 100, MA20: 90, MA50: 80, AdjustedSTDelta: 2, AdjustedMTDelta: 1},    // mod bullish ma7>ma20
		{CurrPrice: 95, MA7: 100, MA20: 90, MA50: 80, AdjustedSTDelta: -1, AdjustedMTDelta: 1},   // neutral
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 80, AdjustedSTDelta: -15, AdjustedMTDelta: -15}, // bearish_lt
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 80, AdjustedSTDelta: -15, AdjustedMTDelta: -5},  // mod bearish_lt (st2 lt1)
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 80, AdjustedSTDelta: -5, AdjustedMTDelta: -15},  // mod bearish_lt (st1 lt2)
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 80, AdjustedSTDelta: -5, AdjustedMTDelta: -5},   // mod bearish_lt (st1 lt1)
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 65, AdjustedSTDelta: -15, AdjustedMTDelta: 0},   // bearish_st
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 65, AdjustedSTDelta: -5, AdjustedMTDelta: 0},    // mod bearish_st
		{CurrPrice: 75, MA7: 60, MA20: 70, MA50: 80, AdjustedSTDelta: -5, AdjustedMTDelta: -5},   // neutral (no st bearish)
		{CurrPrice: 100, MA7: 0, MA20: 90, MA50: 80, AdjustedSTDelta: 1, AdjustedMTDelta: 1},     // neutral (ma7=0)
		{CurrPrice: 100, MA7: 100, MA20: 100, MA50: 80, AdjustedSTDelta: 1, AdjustedMTDelta: 1},  // ma7==ma20 bearish path
	}
	for i, in := range cases {
		want := legacyClassify(in.CurrPrice, in.MA7, in.MA20, in.MA50, in.AdjustedSTDelta, in.AdjustedMTDelta)
		got := Evaluate(rs, in)
		if got != want {
			t.Errorf("case %d: got %q want %q (in=%+v)", i, got, want, in)
		}
	}
}

func TestMarshalParseRoundTrip(t *testing.T) {
	raw, err := DefaultRuleset().Marshal()
	if err != nil {
		t.Fatal(err)
	}
	rs, err := Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	in := Inputs{CurrPrice: 110, MA7: 100, MA20: 90, MA50: 80, AdjustedSTDelta: 2}
	if got := Evaluate(rs, in); got != TrendBullish {
		t.Fatalf("got %q", got)
	}
}
