package trendrules

import (
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"unicode"
)

const (
	OnMatchExit     = "exit"
	OnMatchContinue = "continue"

	TrendBullish             = "bullish"
	TrendModeratelyBullish   = "moderately bullish"
	TrendBearishST           = "bearish_st"
	TrendModeratelyBearishST = "moderately bearish_st"
	TrendBearishLT           = "bearish_lt"
	TrendModeratelyBearishLT = "moderately bearish_lt"
	TrendNeutral             = "neutral"

	NamedBearishDeltaThreshold   = "bearish_delta_threshold"
	DefaultBearishDeltaThreshold = 10
)

// CanonicalTrends is the fixed ordered set of trend labels (excluding the
// catch-all neutral which is also required).
var CanonicalTrends = []string{
	TrendBullish,
	TrendModeratelyBullish,
	TrendBearishLT,
	TrendModeratelyBearishLT,
	TrendBearishST,
	TrendModeratelyBearishST,
	TrendNeutral,
}

var canonicalSet = func() map[string]struct{} {
	m := make(map[string]struct{}, len(CanonicalTrends))
	for _, t := range CanonicalTrends {
		m[t] = struct{}{}
	}
	return m
}()

// NamedValue is a reusable constant referenced in rule formulas.
type NamedValue struct {
	Name  string  `json:"name"`
	Value float64 `json:"value"`
}

// Rule is one trend classification row in evaluation order.
type Rule struct {
	Order          int    `json:"order"`
	Recommendation string `json:"recommendation"` // trend label
	Condition      string `json:"condition"`
	OnMatch        string `json:"on_match"` // exit | continue
	Enabled        bool   `json:"enabled"`
}

// Ruleset is admin-managed global trend configuration.
type Ruleset struct {
	NamedValues []NamedValue `json:"named_values"`
	Rules       []Rule       `json:"rules"`
}

// BuiltinFields are identifiers allowed in trend conditions.
var BuiltinFields = map[string]struct{}{
	"curr_price":           {},
	"ma7":                  {},
	"ma20":                 {},
	"ma50":                 {},
	"adjusted_st_delta":    {},
	"adjusted_mt_delta":    {},
	"st_bearish_strength":  {},
	"lt_bearish_strength":  {},
}

var identRe = regexp.MustCompile(`[A-Za-z_][A-Za-z0-9_]*`)

// DefaultRuleset reproduces the previous hardcoded classifyTrend logic.
func DefaultRuleset() Ruleset {
	return Ruleset{
		NamedValues: []NamedValue{
			{Name: NamedBearishDeltaThreshold, Value: DefaultBearishDeltaThreshold},
		},
		Rules: []Rule{
			{
				Order:          1,
				Recommendation: TrendBullish,
				Condition:      `ma7 > 0 AND ma20 > 0 AND curr_price > ma7 AND ma7 > ma20 AND adjusted_st_delta > 0`,
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          2,
				Recommendation: TrendModeratelyBullish,
				// After bullish: aligned MAs with non-positive ST, or ma7>ma20 with positive ST but price not above ma7.
				Condition: `ma7 > 0 AND ma20 > 0 AND ((curr_price > ma7 AND ma7 > ma20) OR (ma7 > ma20 AND curr_price <= ma7 AND adjusted_st_delta > 0))`,
				OnMatch:   OnMatchExit,
				Enabled:   true,
			},
			{
				Order:          3,
				Recommendation: TrendBearishLT,
				Condition:      `ma7 > 0 AND ma20 > 0 AND ma7 <= ma20 AND st_bearish_strength == 2 AND lt_bearish_strength == 2`,
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          4,
				Recommendation: TrendModeratelyBearishLT,
				Condition:      `ma7 > 0 AND ma20 > 0 AND ma7 <= ma20 AND st_bearish_strength > 0 AND lt_bearish_strength > 0`,
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          5,
				Recommendation: TrendBearishST,
				Condition:      `ma7 > 0 AND ma20 > 0 AND ma7 <= ma20 AND st_bearish_strength == 2`,
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          6,
				Recommendation: TrendModeratelyBearishST,
				Condition:      `ma7 > 0 AND ma20 > 0 AND ma7 <= ma20 AND st_bearish_strength > 0`,
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          7,
				Recommendation: TrendNeutral,
				Condition:      `TRUE`,
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
		},
	}
}

func (r Ruleset) Marshal() (string, error) {
	r.normalize()
	b, err := json.Marshal(r)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func Parse(raw string) (Ruleset, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return Ruleset{}, fmt.Errorf("trend ruleset is empty")
	}
	var rs Ruleset
	if err := json.Unmarshal([]byte(raw), &rs); err != nil {
		return Ruleset{}, fmt.Errorf("invalid trend ruleset JSON: %w", err)
	}
	if err := rs.Validate(); err != nil {
		return Ruleset{}, err
	}
	rs.normalize()
	return rs, nil
}

func (r *Ruleset) normalize() {
	sort.SliceStable(r.Rules, func(i, j int) bool {
		return r.Rules[i].Order < r.Rules[j].Order
	})
	for i := range r.Rules {
		if r.Rules[i].Order <= 0 {
			r.Rules[i].Order = i + 1
		}
		om := strings.ToLower(strings.TrimSpace(r.Rules[i].OnMatch))
		if om != OnMatchExit {
			om = OnMatchContinue
		}
		r.Rules[i].OnMatch = om
		r.Rules[i].Recommendation = strings.TrimSpace(r.Rules[i].Recommendation)
		r.Rules[i].Condition = strings.TrimSpace(r.Rules[i].Condition)
	}
}

func (r Ruleset) Validate() error {
	names := map[string]struct{}{}
	for _, nv := range r.NamedValues {
		n := strings.TrimSpace(nv.Name)
		if n == "" {
			return fmt.Errorf("named value name is required")
		}
		if !isIdent(n) {
			return fmt.Errorf("invalid named value name %q", n)
		}
		if _, ok := BuiltinFields[n]; ok {
			return fmt.Errorf("named value %q conflicts with a built-in field", n)
		}
		if _, ok := names[n]; ok {
			return fmt.Errorf("duplicate named value %q", n)
		}
		names[n] = struct{}{}
	}
	if len(r.Rules) != len(CanonicalTrends) {
		return fmt.Errorf("trend rules must have exactly %d rules (got %d)", len(CanonicalTrends), len(r.Rules))
	}
	seen := map[string]struct{}{}
	for i, rule := range r.Rules {
		label := strings.TrimSpace(rule.Recommendation)
		if label == "" {
			return fmt.Errorf("rule %d: trend label is required", i+1)
		}
		if _, ok := canonicalSet[label]; !ok {
			return fmt.Errorf("rule %d: unknown trend label %q", i+1, label)
		}
		if _, ok := seen[label]; ok {
			return fmt.Errorf("duplicate trend label %q", label)
		}
		seen[label] = struct{}{}
		om := strings.ToLower(strings.TrimSpace(rule.OnMatch))
		if om != "" && om != OnMatchExit && om != OnMatchContinue {
			return fmt.Errorf("rule %d: on_match must be exit or continue", i+1)
		}
		cond := strings.TrimSpace(rule.Condition)
		if cond == "" {
			continue
		}
		if err := validateExpression(cond, names); err != nil {
			return fmt.Errorf("rule %d (%s): %w", i+1, label, err)
		}
	}
	for _, want := range CanonicalTrends {
		if _, ok := seen[want]; !ok {
			return fmt.Errorf("missing required trend label %q", want)
		}
	}
	return nil
}

func isIdent(s string) bool {
	if s == "" {
		return false
	}
	for i, r := range s {
		if i == 0 {
			if !unicode.IsLetter(r) && r != '_' {
				return false
			}
			continue
		}
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_' {
			return false
		}
	}
	return true
}

func validateExpression(expr string, named map[string]struct{}) error {
	if strings.Count(expr, "(") != strings.Count(expr, ")") {
		return fmt.Errorf("unbalanced parentheses")
	}
	if strings.Count(expr, `"`)%2 != 0 {
		return fmt.Errorf("unbalanced string quotes")
	}
	stripped := regexp.MustCompile(`"[^"]*"`).ReplaceAllString(expr, `""`)
	idents := identRe.FindAllString(stripped, -1)
	for _, id := range idents {
		up := strings.ToUpper(id)
		if up == "AND" || up == "OR" || up == "TRUE" || up == "FALSE" {
			continue
		}
		if _, ok := BuiltinFields[id]; ok {
			continue
		}
		if _, ok := named[id]; ok {
			continue
		}
		return fmt.Errorf("unknown identifier %q", id)
	}
	return nil
}

// ToMap returns a JSON-friendly map for API responses.
func (r Ruleset) ToMap() map[string]any {
	r.normalize()
	b, _ := json.Marshal(r)
	var m map[string]any
	_ = json.Unmarshal(b, &m)
	if m == nil {
		m = map[string]any{"named_values": []any{}, "rules": []any{}}
	}
	return m
}

// BearishDeltaThreshold reads named value or default.
func BearishDeltaThreshold(r Ruleset) float64 {
	for _, nv := range r.NamedValues {
		if nv.Name == NamedBearishDeltaThreshold && nv.Value > 0 {
			return nv.Value
		}
	}
	return DefaultBearishDeltaThreshold
}
