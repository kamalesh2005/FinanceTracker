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

	// DefaultBuyCondition is the built-in BUY formula.
	DefaultBuyCondition = `(curr_price < set_buy_price) OR (trend == "bullish" AND curr_price > avg_buy_price * 1.1)`

	// DefaultBookProfitCondition is the built-in Book Profit formula.
	DefaultBookProfitCondition = `(curr_price > set_profit_booking_price) OR (highest_price > 0 AND curr_price >= highest_price * 0.95 AND curr_price > avg_buy_price)`

	// DefaultSellCondition is the built-in SELL formula.
	DefaultSellCondition = `(curr_price < set_stop_loss_price) OR (trend == "moderately bearish_st" AND curr_price < avg_buy_price * 0.9) OR (trend == "bearish_st" OR trend == "bearish_lt" OR trend == "moderately bearish_lt")`

	// LegacyBookProfitCondition is the prior default (before requiring curr_price > avg_buy_price).
	LegacyBookProfitCondition = `(set_profit_booking_price > 0 AND curr_price > set_profit_booking_price) OR (sixth_highest_price > 0 AND curr_price >= sixth_highest_price * 0.95)`
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
	"last_trade_trend":         {},
	"trend_matches_last_action": {},
	"abs_pct_from_last_trade":  {},
	"highest_price":            {},
	"lowest_price":             {},
	"sixth_highest_price":      {},
	"sixth_lowest_price":       {},
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
			{Name: "last_trade_rule_validity_days", Value: 30},
		},
		Rules: []Rule{
			{
				Order:          1,
				Recommendation: "AT BUY PRICE",
				Condition:      "abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_buy AND trend_matches_last_action",
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          2,
				Recommendation: "AT SELL PRICE",
				Condition:      "abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_sale AND trend_matches_last_action",
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          3,
				Recommendation: "AT HOLD PRICE",
				Condition:      "abs_pct_from_last_trade < fluctuation_pct AND last_trade_is_hold AND trend_matches_last_action",
				OnMatch:        OnMatchExit,
				Enabled:        true,
			},
			{
				Order:          4,
				Recommendation: "BUY",
				Condition:      DefaultBuyCondition,
				OnMatch:        OnMatchContinue,
				Enabled:        true,
			},
			{
				Order:          5,
				Recommendation: "Book Profit",
				Condition:      DefaultBookProfitCondition,
				OnMatch:        OnMatchContinue,
				Enabled:        true,
			},
			{
				Order:          6,
				Recommendation: "SELL",
				Condition:      DefaultSellCondition,
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

const (
	namedFluctuationPct              = "fluctuation_pct"
	namedLastTradeRuleValidityDays   = "last_trade_rule_validity_days"
	defaultLastTradeRuleValidityDays = 30
)

// EnsureNamedValueAfter inserts name=value after the named value `after` when
// `name` is missing. Does not overwrite an existing value. Returns true if inserted.
func EnsureNamedValueAfter(r *Ruleset, name string, value float64, after string) bool {
	if r == nil {
		return false
	}
	for _, nv := range r.NamedValues {
		if nv.Name == name {
			return false
		}
	}
	insert := NamedValue{Name: name, Value: value}
	if after != "" {
		for i, nv := range r.NamedValues {
			if nv.Name == after {
				r.NamedValues = append(r.NamedValues[:i+1], append([]NamedValue{insert}, r.NamedValues[i+1:]...)...)
				return true
			}
		}
	}
	r.NamedValues = append(r.NamedValues, insert)
	return true
}

// EnsureLastTradeRuleValidityDays adds last_trade_rule_validity_days=30 after
// fluctuation_pct when missing. Existing values are left unchanged.
func EnsureLastTradeRuleValidityDays(r *Ruleset) bool {
	return EnsureNamedValueAfter(r, namedLastTradeRuleValidityDays, defaultLastTradeRuleValidityDays, namedFluctuationPct)
}

var unsetThresholdGuardRes []*regexp.Regexp

func init() {
	for _, field := range []string{
		"set_buy_price",
		"set_stop_loss_price",
		"set_profit_booking_price",
	} {
		unsetThresholdGuardRes = append(unsetThresholdGuardRes,
			regexp.MustCompile(`(?i)\b`+field+`\s*>\s*0(?:\.0+)?\s+AND\s+`),
			regexp.MustCompile(`(?i)\s+AND\s+`+field+`\s*>\s*0(?:\.0+)?\b`),
		)
	}
}

// PatchUnsetThresholdGuards removes explicit "field > 0 AND" / "AND field > 0"
// guards for set_buy_price, set_stop_loss_price, and set_profit_booking_price.
// Those checks are now applied implicitly when the column is still the default 0.
// Returns true when any rule was changed.
func PatchUnsetThresholdGuards(r *Ruleset) bool {
	if r == nil {
		return false
	}
	changed := false
	for i := range r.Rules {
		next := stripUnsetThresholdGuards(r.Rules[i].Condition)
		if next != r.Rules[i].Condition {
			r.Rules[i].Condition = next
			changed = true
		}
	}
	return changed
}

func stripUnsetThresholdGuards(cond string) string {
	next := cond
	for _, re := range unsetThresholdGuardRes {
		next = re.ReplaceAllString(next, "")
	}
	return strings.TrimSpace(next)
}

// PatchSixthHighLowFieldNames rewrites sixth_highest_price / sixth_lowest_price
// identifiers in stored formulas to highest_price / lowest_price.
// Returns true when any rule was changed.
func PatchSixthHighLowFieldNames(r *Ruleset) bool {
	if r == nil {
		return false
	}
	changed := false
	for i := range r.Rules {
		cond := r.Rules[i].Condition
		next := strings.ReplaceAll(cond, "sixth_highest_price", "highest_price")
		next = strings.ReplaceAll(next, "sixth_lowest_price", "lowest_price")
		if next != cond {
			r.Rules[i].Condition = next
			changed = true
		}
	}
	return changed
}

// PatchAtPriceTrendMatch appends AND trend_matches_last_action to AT BUY/SELL/HOLD
// PRICE rules that do not already reference it. Returns true when any rule changed.
func PatchAtPriceTrendMatch(r *Ruleset) bool {
	if r == nil {
		return false
	}
	changed := false
	for i := range r.Rules {
		rec := strings.ToUpper(strings.TrimSpace(r.Rules[i].Recommendation))
		if rec != "AT BUY PRICE" && rec != "AT SELL PRICE" && rec != "AT HOLD PRICE" {
			continue
		}
		cond := strings.TrimSpace(r.Rules[i].Condition)
		if cond == "" {
			continue
		}
		lower := strings.ToLower(cond)
		if strings.Contains(lower, "trend_matches_last_action") {
			continue
		}
		r.Rules[i].Condition = cond + " AND trend_matches_last_action"
		changed = true
	}
	return changed
}

// PatchLegacyBookProfitConditions upgrades Book Profit rows that still use the
// prior default formula (missing curr_price > avg_buy_price on the sixth-high branch).
// Returns true when any rule was changed.
func PatchLegacyBookProfitConditions(r *Ruleset) bool {
	if r == nil {
		return false
	}
	changed := false
	for i := range r.Rules {
		if r.Rules[i].Recommendation != "Book Profit" {
			continue
		}
		cond := strings.TrimSpace(r.Rules[i].Condition)
		if cond == DefaultBookProfitCondition {
			continue
		}
		if cond == LegacyBookProfitCondition || isLegacySixthHighBookProfit(cond) {
			r.Rules[i].Condition = DefaultBookProfitCondition
			changed = true
		}
	}
	return changed
}

func isLegacySixthHighBookProfit(cond string) bool {
	c := strings.ToLower(strings.ReplaceAll(cond, " ", ""))
	if (!strings.Contains(c, "sixth_highest_price") && !strings.Contains(c, "highest_price")) ||
		!strings.Contains(c, "0.95") {
		return false
	}
	// Already has the avg_buy_price guard on the sixth-high path.
	if strings.Contains(c, "curr_price>avg_buy_price") {
		return false
	}
	// Only rewrite formulas that still look like the prior default shape.
	return strings.Contains(c, "set_profit_booking_price>0") &&
		strings.Contains(c, "curr_price>set_profit_booking_price")
}
