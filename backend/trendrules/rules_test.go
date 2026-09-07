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
	rs, err := Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	rs.Rules[0].Recommendation = "super bullish"
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
	type alias Ruleset
	return (Ruleset)(rs).Marshal()
}

func TestEvalExpressions(t *testing.T) {
	ctx := map[string]any{
		"curr_price":               100.0,
		"ma7":                      90.0,
		"ma20":                     80.0,
		"ma50":                     70.0,
		"adjusted_st_delta":        1.0,
		"adjusted_mt_delta":        0.0,
		"st_bearish_strength":      0.0,
		"lt_bearish_strength":      0.0,
		"price_ma_tolerance_pct":   2.5,
		"ma_ma_tolerance_pct":      1.0,
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
	ok, err = evalBool(`curr_price > ma7 * (1 + price_ma_tolerance_pct / 100)`, ctx)
	if err != nil || !ok {
		t.Fatalf("tolerant price compare: got %v err=%v", ok, err)
	}
}

func TestClearlyAboveBelow(t *testing.T) {
	// Inside / outside the 2.5% band (avoid exact float boundary).
	if ClearlyAbove(102.4, 100, 2.5) {
		t.Fatal("102.4 should be inside 2.5% band above 100")
	}
	if !ClearlyAbove(103, 100, 2.5) {
		t.Fatal("103 should be clearly above 100 at 2.5%")
	}
	if ClearlyBelow(97.6, 100, 2.5) {
		t.Fatal("97.6 should be inside 2.5% band below 100")
	}
	if !ClearlyBelow(97, 100, 2.5) {
		t.Fatal("97 should be clearly below 100 at 2.5%")
	}
	// Zero tol = strict
	if !ClearlyAbove(101, 100, 0) {
		t.Fatal("strict above")
	}
	if ClearlyAbove(100, 100, 0) {
		t.Fatal("equal is not above")
	}
	if !ClearlyBelow(99, 100, 0) {
		t.Fatal("strict below")
	}
}

func TestClassifyBearishStrength(t *testing.T) {
	cases := []struct {
		name                   string
		price, fast, slow, adj float64
		priceTol, maTol        float64
		want                   int
	}{
		{"strong", 50, 60, 70, -15, 0, 0, 2},
		{"weak_aligned", 50, 60, 70, -5, 0, 0, 1},
		{"weak_delta_only", 80, 60, 70, -15, 0, 0, 1},
		{"none", 80, 60, 70, -5, 0, 0, 0},
		{"zero_ma", 50, 0, 70, -15, 0, 0, 0},
		// Noise: price slightly under fast, fast slightly under slow — within bands → 0
		{"noise_flat", 435, 440, 442, 0.61, 2.5, 1.0, 0},
		// Beyond price band but MA flat → still 0 (stack needs clear MA gap)
		{"price_down_ma_flat", 420, 440, 442, 0.61, 2.5, 1.0, 0},
		// Clear stack with defaults still bearish
		{"clear_stack_default_tol", 50, 60, 70, -5, 2.5, 1.0, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := ClassifyBearishStrength(tc.price, tc.fast, tc.slow, tc.adj, 10, tc.priceTol, tc.maTol)
			if got != tc.want {
				t.Fatalf("got %d want %d", got, tc.want)
			}
		})
	}
}

// tolerantClassify mirrors DefaultRuleset semantics for parity tests.
func tolerantClassify(currentPrice, ma7, ma20, ma50, adjustedSTDelta, adjustedMTDelta float64) string {
	priceTol := DefaultPriceMATolerancePct
	maTol := DefaultMAMATolerancePct
	trend := TrendNeutral
	if ma7 > 0 && ma20 > 0 {
		if ClearlyAbove(currentPrice, ma7, priceTol) && ClearlyAbove(ma7, ma20, maTol) {
			if adjustedSTDelta > 0 {
				trend = TrendBullish
			} else {
				trend = TrendModeratelyBullish
			}
		} else if ClearlyAbove(ma7, ma20, maTol) {
			if adjustedSTDelta > 0 && !ClearlyAbove(currentPrice, ma7, priceTol) {
				trend = TrendModeratelyBullish
			}
		} else {
			stBearish := ClassifyBearishStrength(currentPrice, ma7, ma20, adjustedSTDelta, 10, priceTol, maTol)
			ltBearish := ClassifyBearishStrength(currentPrice, ma20, ma50, adjustedMTDelta, 10, priceTol, maTol)
			if stBearish > 0 {
				if ltBearish > 0 {
					if stBearish == 2 && ltBearish == 2 {
						trend = TrendBearishLT
					} else {
						trend = TrendModeratelyBearishLT
					}
				} else if stBearish == 2 {
					trend = TrendBearishST
				} else {
					trend = TrendModeratelyBearishST
				}
			}
		}
	}
	return trend
}

func TestDefaultRulesetMatchesTolerantClassify(t *testing.T) {
	rs := DefaultRuleset()
	cases := []Inputs{
		{CurrPrice: 110, MA7: 100, MA20: 90, MA50: 80, AdjustedSTDelta: 2, AdjustedMTDelta: 1},
		{CurrPrice: 110, MA7: 100, MA20: 90, MA50: 80, AdjustedSTDelta: -1, AdjustedMTDelta: 1},
		{CurrPrice: 95, MA7: 100, MA20: 90, MA50: 80, AdjustedSTDelta: 2, AdjustedMTDelta: 1},
		{CurrPrice: 95, MA7: 100, MA20: 90, MA50: 80, AdjustedSTDelta: -1, AdjustedMTDelta: 1},
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 80, AdjustedSTDelta: -15, AdjustedMTDelta: -15},
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 80, AdjustedSTDelta: -15, AdjustedMTDelta: -5},
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 80, AdjustedSTDelta: -5, AdjustedMTDelta: -15},
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 80, AdjustedSTDelta: -5, AdjustedMTDelta: -5},
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 65, AdjustedSTDelta: -15, AdjustedMTDelta: 0},
		{CurrPrice: 50, MA7: 60, MA20: 70, MA50: 65, AdjustedSTDelta: -5, AdjustedMTDelta: 0},
		{CurrPrice: 75, MA7: 60, MA20: 70, MA50: 80, AdjustedSTDelta: -5, AdjustedMTDelta: -5},
		{CurrPrice: 100, MA7: 0, MA20: 90, MA50: 80, AdjustedSTDelta: 1, AdjustedMTDelta: 1},
		{CurrPrice: 100, MA7: 100, MA20: 100, MA50: 80, AdjustedSTDelta: 1, AdjustedMTDelta: 1},
		// Reported noise case: flat MAs, slight dip, positive adj → neutral
		{CurrPrice: 435, MA7: 440, MA20: 442, MA50: 436, AdjustedSTDelta: 0.61, AdjustedMTDelta: 0.65},
	}
	for i, in := range cases {
		want := tolerantClassify(in.CurrPrice, in.MA7, in.MA20, in.MA50, in.AdjustedSTDelta, in.AdjustedMTDelta)
		got := Evaluate(rs, in)
		if got != want {
			t.Errorf("case %d: got %q want %q (in=%+v)", i, got, want, in)
		}
	}
}

func TestNoiseBandNeutralNotModBearishST(t *testing.T) {
	rs := DefaultRuleset()
	in := Inputs{
		CurrPrice: 435, MA7: 440, MA20: 442, MA50: 436,
		AdjustedSTDelta: 0.61, AdjustedMTDelta: 0.65,
	}
	if got := Evaluate(rs, in); got != TrendNeutral {
		t.Fatalf("got %q want neutral", got)
	}
}

func TestBeyondToleranceStillBearish(t *testing.T) {
	rs := DefaultRuleset()
	in := Inputs{
		CurrPrice: 50, MA7: 60, MA20: 70, MA50: 65,
		AdjustedSTDelta: -5, AdjustedMTDelta: 0,
	}
	if got := Evaluate(rs, in); got != TrendModeratelyBearishST {
		t.Fatalf("got %q want moderately bearish_st", got)
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

func TestEnsureToleranceNamedValues(t *testing.T) {
	rs := Ruleset{
		NamedValues: []NamedValue{{Name: NamedBearishDeltaThreshold, Value: 10}},
		Rules:       DefaultRuleset().Rules,
	}
	if !EnsureToleranceNamedValues(&rs) {
		t.Fatal("expected insert")
	}
	if EnsureToleranceNamedValues(&rs) {
		t.Fatal("second call should no-op")
	}
	names := map[string]float64{}
	for _, nv := range rs.NamedValues {
		names[nv.Name] = nv.Value
	}
	if names[NamedPriceMATolerancePct] != DefaultPriceMATolerancePct {
		t.Fatalf("price tol=%v", names[NamedPriceMATolerancePct])
	}
	if names[NamedMAMATolerancePct] != DefaultMAMATolerancePct {
		t.Fatalf("ma tol=%v", names[NamedMAMATolerancePct])
	}
	// Order: bearish, price, ma
	if rs.NamedValues[0].Name != NamedBearishDeltaThreshold ||
		rs.NamedValues[1].Name != NamedPriceMATolerancePct ||
		rs.NamedValues[2].Name != NamedMAMATolerancePct {
		t.Fatalf("order=%v", rs.NamedValues)
	}
}

func TestPatchDefaultToleranceConditions(t *testing.T) {
	rs := Ruleset{
		NamedValues: []NamedValue{{Name: NamedBearishDeltaThreshold, Value: 10}},
		Rules: []Rule{
			{Order: 1, Recommendation: TrendBullish, Condition: legacyCondBullish, OnMatch: OnMatchExit, Enabled: true},
			{Order: 2, Recommendation: TrendModeratelyBullish, Condition: legacyCondModeratelyBullish, OnMatch: OnMatchExit, Enabled: true},
			{Order: 3, Recommendation: TrendBearishLT, Condition: legacyCondBearishLT, OnMatch: OnMatchExit, Enabled: true},
			{Order: 4, Recommendation: TrendModeratelyBearishLT, Condition: legacyCondModeratelyBearishLT, OnMatch: OnMatchExit, Enabled: true},
			{Order: 5, Recommendation: TrendBearishST, Condition: legacyCondBearishST, OnMatch: OnMatchExit, Enabled: true},
			{Order: 6, Recommendation: TrendModeratelyBearishST, Condition: legacyCondModeratelyBearishST, OnMatch: OnMatchExit, Enabled: true},
			{Order: 7, Recommendation: TrendNeutral, Condition: condNeutral, OnMatch: OnMatchExit, Enabled: true},
		},
	}
	if !PatchDefaultToleranceConditions(&rs) {
		t.Fatal("expected patch")
	}
	if PatchDefaultToleranceConditions(&rs) {
		t.Fatal("second patch should no-op")
	}
	want := map[string]string{
		TrendBullish:             condBullish,
		TrendModeratelyBullish:   condModeratelyBullish,
		TrendBearishLT:           condBearishLT,
		TrendModeratelyBearishLT: condModeratelyBearishLT,
		TrendBearishST:           condBearishST,
		TrendModeratelyBearishST: condModeratelyBearishST,
	}
	for _, rule := range rs.Rules {
		if w, ok := want[rule.Recommendation]; ok && rule.Condition != w {
			t.Fatalf("%s: got %q want %q", rule.Recommendation, rule.Condition, w)
		}
	}
	// Custom condition untouched
	custom := Ruleset{
		Rules: []Rule{{
			Recommendation: TrendBullish,
			Condition:      `ma7 > 0 AND curr_price > ma7 * 1.1`,
			OnMatch:        OnMatchExit,
			Enabled:        true,
		}},
	}
	if PatchDefaultToleranceConditions(&custom) {
		t.Fatal("custom condition must not patch")
	}
}

func TestApplyToleranceMigration(t *testing.T) {
	rs := Ruleset{
		NamedValues: []NamedValue{{Name: NamedBearishDeltaThreshold, Value: 10}},
		Rules: []Rule{
			{Order: 1, Recommendation: TrendBullish, Condition: legacyCondBullish, OnMatch: OnMatchExit, Enabled: true},
			{Order: 2, Recommendation: TrendModeratelyBullish, Condition: legacyCondModeratelyBullish, OnMatch: OnMatchExit, Enabled: true},
			{Order: 3, Recommendation: TrendBearishLT, Condition: legacyCondBearishLT, OnMatch: OnMatchExit, Enabled: true},
			{Order: 4, Recommendation: TrendModeratelyBearishLT, Condition: legacyCondModeratelyBearishLT, OnMatch: OnMatchExit, Enabled: true},
			{Order: 5, Recommendation: TrendBearishST, Condition: legacyCondBearishST, OnMatch: OnMatchExit, Enabled: true},
			{Order: 6, Recommendation: TrendModeratelyBearishST, Condition: legacyCondModeratelyBearishST, OnMatch: OnMatchExit, Enabled: true},
			{Order: 7, Recommendation: TrendNeutral, Condition: condNeutral, OnMatch: OnMatchExit, Enabled: true},
		},
	}
	if !ApplyToleranceMigration(&rs) {
		t.Fatal("expected migration")
	}
	if ApplyToleranceMigration(&rs) {
		t.Fatal("second migration should no-op")
	}
	if err := rs.Validate(); err != nil {
		t.Fatal(err)
	}
}
