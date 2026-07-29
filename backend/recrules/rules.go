package recrules

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
)

// NamedValue is a reusable constant referenced in rule formulas.
type NamedValue struct {
	Name  string  `json:"name"`
	Value float64 `json:"value"`
}

// Rule is one recommendation row in evaluation order.
type Rule struct {
	Order          int    `json:"order"`
	Recommendation string `json:"recommendation"`
	Condition      string `json:"condition"`
	OnMatch        string `json:"on_match"` // exit | continue
	Enabled        bool   `json:"enabled"`
}

// Ruleset is admin/user recommendation configuration.
type Ruleset struct {
	NamedValues []NamedValue `json:"named_values"`
	Rules       []Rule       `json:"rules"`
}

var BuiltinFields = map[string]struct{}{
	"curr_price":               {},
	"avg_buy_price":            {},
	"last_trade_price":         {},
	"last_trade_is_buy":        {},
	"last_trade_is_sale":       {},
	"last_trade_is_hold":       {},
	"abs_pct_from_last_trade":  {},
	"sixth_highest_price":      {},
	"trend":                    {},
	"set_buy_price":            {},
	"set_profit_booking_price": {},
	"set_stop_loss_price":      {},
}

var identRe = regexp.MustCompile(`[A-Za-z_][A-Za-z0-9_]*`)

// DefaultRuleset reproduces the previous hardcoded recommendation logic.
func DefaultRuleset(fluctuationPct float64) Ruleset {
	if fluctuationPct <= 0 {
		fluctuationPct = 5
	}
	return Ruleset{
		NamedValues: []NamedValue{
			{Name: "fluctuation_pct", Value: fluctuationPct},
		},
		Rules: []Rule{
			{
				Order:          1,
				Recommendation: "AT BUY PRICE",
				Condition:      "abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_buy",
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          2,
				Recommendation: "AT SELL PRICE",
				Condition:      "abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_sale",
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          3,
				Recommendation: "AT HOLD PRICE",
				Condition:      "abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_hold",
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          4,
				Recommendation: "BUY",
				Condition:      `(set_buy_price > 0 AND curr_price < set_buy_price) OR (trend == "bullish" AND curr_price > avg_buy_price * 1.1)`,
				OnMatch:        OnMatchContinue,
				Enabled:        true,
			},
			{
				Order:          5,
				Recommendation: "Book Profit",
				Condition:      `(set_profit_booking_price > 0 AND curr_price > set_profit_booking_price) OR (sixth_highest_price > 0 AND curr_price >= sixth_highest_price * 0.95)`,
				OnMatch:        OnMatchContinue,
				Enabled:        true,
			},
			{
				Order:          6,
				Recommendation: "SELL",
				Condition:      `(set_stop_loss_price > 0 AND curr_price < set_stop_loss_price) OR (trend == "moderately bearish_st" AND curr_price < avg_buy_price * 0.9) OR (trend == "bearish_st" OR trend == "bearish_lt" OR trend == "moderately bearish_lt")`,
				OnMatch:        OnMatchContinue,
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
		return Ruleset{}, fmt.Errorf("ruleset is empty")
	}
	var rs Ruleset
	if err := json.Unmarshal([]byte(raw), &rs); err != nil {
		return Ruleset{}, fmt.Errorf("invalid ruleset JSON: %w", err)
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
	if len(r.Rules) == 0 {
		return fmt.Errorf("at least one rule is required")
	}
	for i, rule := range r.Rules {
		if strings.TrimSpace(rule.Recommendation) == "" {
			return fmt.Errorf("rule %d: recommendation is required", i+1)
		}
		om := strings.ToLower(strings.TrimSpace(rule.OnMatch))
		if om != "" && om != OnMatchExit && om != OnMatchContinue {
			return fmt.Errorf("rule %d: on_match must be exit or continue", i+1)
		}
		cond := strings.TrimSpace(rule.Condition)
		if cond == "" {
			continue
		}
		if err := validateExpression(cond, names); err != nil {
			return fmt.Errorf("rule %d (%s): %w", i+1, rule.Recommendation, err)
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

// FluctuationFromRuleset reads named value fluctuation_pct if present.
func FluctuationFromRuleset(r Ruleset, fallback float64) float64 {
	for _, nv := range r.NamedValues {
		if nv.Name == "fluctuation_pct" && nv.Value > 0 {
			return nv.Value
		}
	}
	if fallback > 0 {
		return fallback
	}
	return 5
}

// SetNamedValue updates or inserts a named value.
func (r *Ruleset) SetNamedValue(name string, value float64) {
	for i := range r.NamedValues {
		if r.NamedValues[i].Name == name {
			r.NamedValues[i].Value = value
			return
		}
	}
	r.NamedValues = append(r.NamedValues, NamedValue{Name: name, Value: value})
}
