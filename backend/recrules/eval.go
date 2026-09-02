package recrules

import (
	"fmt"
	"math"
	"sort"
	"strings"
	"time"
)

const (
	noActionRequired = "NO ACTION REQD"
)

var unsetThresholdFields = map[string]struct{}{
	"set_buy_price":            {},
	"set_stop_loss_price":      {},
	"set_profit_booking_price": {},
}

// EvaluateContext holds field values for rule expression evaluation.
type EvaluateContext struct {
	CurrPrice              float64
	AvgBuyPrice            float64
	LastTradePrice         float64
	LastTradeIsBuy         bool
	LastTradeIsSale        bool
	LastTradeIsHold        bool
	LastTradeTrend         string
	TrendMatchesLastAction bool
	AbsPctFromLastTrade    float64
	HighestPrice           float64
	LowestPrice            float64
	SixthHighestPrice      float64
	SixthLowestPrice       float64
	Trend                  string
	SetBuyPrice            float64
	SetProfitBookingPrice  float64
	SetStopLossPrice       float64
	NamedValues            map[string]float64
}

// HoldingInput is raw holding data for building EvaluateContext.
type HoldingInput struct {
	CurrPrice             float64
	AvgBuyPrice           float64
	LastBuyPrice          float64
	LastBuyDate           *time.Time
	LastBuyTrend          string
	LastSalePrice         float64
	LastSaleDate          *time.Time
	LastSaleTrend         string
	LastHoldPrice         float64
	LastHoldDate          *time.Time
	LastHoldTrend         string
	BSHClearDate          *time.Time
	SixthHighestPrice     float64
	SixthLowestPrice      float64
	Trend                 string
	SetBuyPrice           float64
	SetProfitBookingPrice float64
	SetStopLossPrice      float64
	Now                   time.Time
}

// BuildEvaluateContext mirrors Dart RecommendationEngine._buildContext.
func BuildEvaluateContext(h HoldingInput, ruleset Ruleset) EvaluateContext {
	validityDays := LastTradeRuleValidityDays(ruleset)
	cutoff := h.Now.Add(-time.Duration(validityDays) * 24 * time.Hour)

	actionType, actionDate, actionPrice, actionTrend := lastAction(h)
	lastTradeValid := actionDate != nil &&
		!actionDate.Before(cutoff) &&
		!lastTradeClearedForRules(h.BSHClearDate, actionDate)

	var absPct float64
	if lastTradeValid && actionPrice > 0 && h.CurrPrice > 0 {
		absPct = math.Abs(h.CurrPrice-actionPrice) / actionPrice * 100.0
	}

	currentTrend := strings.TrimSpace(h.Trend)
	trendMatches := !lastTradeValid || actionTrend == "" || actionTrend == currentTrend

	ctx := EvaluateContext{
		CurrPrice:              h.CurrPrice,
		AvgBuyPrice:            h.AvgBuyPrice,
		LastTradePrice:         0,
		LastTradeIsBuy:         false,
		LastTradeIsSale:        false,
		LastTradeIsHold:        false,
		LastTradeTrend:         "",
		TrendMatchesLastAction: trendMatches,
		AbsPctFromLastTrade:    absPct,
		HighestPrice:          h.SixthHighestPrice,
		LowestPrice:           h.SixthLowestPrice,
		SixthHighestPrice:     h.SixthHighestPrice,
		SixthLowestPrice:      h.SixthLowestPrice,
		Trend:                 h.Trend,
		SetBuyPrice:           h.SetBuyPrice,
		SetProfitBookingPrice: h.SetProfitBookingPrice,
		SetStopLossPrice:      h.SetStopLossPrice,
		NamedValues:           make(map[string]float64),
	}
	if lastTradeValid {
		ctx.LastTradePrice = actionPrice
		ctx.LastTradeTrend = actionTrend
		switch actionType {
		case "buy":
			ctx.LastTradeIsBuy = true
		case "sell":
			ctx.LastTradeIsSale = true
		case "hold":
			ctx.LastTradeIsHold = true
		}
	}
	for _, nv := range ruleset.NamedValues {
		ctx.NamedValues[nv.Name] = nv.Value
	}
	return ctx
}

// LastTradeRuleValidityDays returns the named value or 30.
func LastTradeRuleValidityDays(ruleset Ruleset) float64 {
	for _, nv := range ruleset.NamedValues {
		if nv.Name == namedLastTradeRuleValidityDays && nv.Value > 0 {
			return nv.Value
		}
	}
	return defaultLastTradeRuleValidityDays
}

func lastAction(h HoldingInput) (actionType string, actionDate *time.Time, actionPrice float64, actionTrend string) {
	type candidate struct {
		typ      string
		date     *time.Time
		price    float64
		trend    string
		valid    bool
		priority int
	}
	var candidates []candidate
	if h.LastBuyDate != nil && h.LastBuyPrice > 0 {
		candidates = append(candidates, candidate{"buy", h.LastBuyDate, h.LastBuyPrice, strings.TrimSpace(h.LastBuyTrend), true, 1})
	}
	if h.LastSaleDate != nil && h.LastSalePrice > 0 {
		candidates = append(candidates, candidate{"sell", h.LastSaleDate, h.LastSalePrice, strings.TrimSpace(h.LastSaleTrend), true, 2})
	}
	if h.LastHoldDate != nil && h.LastHoldPrice > 0 {
		candidates = append(candidates, candidate{"hold", h.LastHoldDate, h.LastHoldPrice, strings.TrimSpace(h.LastHoldTrend), true, 3})
	}
	var best *candidate
	for i := range candidates {
		c := &candidates[i]
		if !c.valid || c.date == nil {
			continue
		}
		if best == nil ||
			c.date.After(*best.date) ||
			(c.date.Equal(*best.date) && c.priority > best.priority) {
			best = c
		}
	}
	if best == nil {
		return "", nil, 0, ""
	}
	return best.typ, best.date, best.price, best.trend
}

func lastTradeClearedForRules(bshClear *time.Time, lastAction *time.Time) bool {
	if bshClear == nil || lastAction == nil {
		return bshClear != nil && lastAction == nil
	}
	return !lastAction.After(*bshClear)
}

// Evaluate runs recommendation rules in order and returns the signal label.
func Evaluate(ruleset Ruleset, ctx EvaluateContext) string {
	rules := append([]Rule(nil), ruleset.Rules...)
	sort.Slice(rules, func(i, j int) bool { return rules[i].Order < rules[j].Order })

	var parts []string
	for _, rule := range rules {
		if !rule.Enabled {
			continue
		}
		cond := strings.TrimSpace(rule.Condition)
		if cond == "" {
			continue
		}
		matched, err := evalBool(cond, ctx)
		if err != nil || !matched {
			continue
		}
		if rule.OnMatch == OnMatchExit {
			return rule.Recommendation
		}
		parts = append(parts, rule.Recommendation)
	}
	if len(parts) == 0 {
		return noActionRequired
	}
	return strings.Join(parts, " OR ")
}

// IsActionableSignal reports whether a signal should appear in review emails.
func IsActionableSignal(signal string) bool {
	switch signal {
	case noActionRequired, "AT BUY PRICE", "AT SELL PRICE", "AT HOLD PRICE":
		return false
	}
	if strings.Contains(signal, "Book Profit") {
		return true
	}
	if strings.Contains(signal, "BUY") && signal != "AT BUY PRICE" {
		return true
	}
	if strings.Contains(signal, "SELL") && signal != "AT SELL PRICE" {
		return true
	}
	return false
}

type unsetMarker struct{}

var unsetVal = unsetMarker{}

func evalBool(expr string, ctx EvaluateContext) (bool, error) {
	p := &parser{src: expr, ctx: ctx}
	v, err := p.parseOr()
	if err != nil {
		return false, err
	}
	if err := p.expectEnd(); err != nil {
		return false, err
	}
	switch t := v.(type) {
	case bool:
		return t, nil
	case float64:
		return t != 0, nil
	case string:
		return t != "", nil
	default:
		return false, nil
	}
}

type parser struct {
	src string
	ctx EvaluateContext
	i   int
}

func (p *parser) expectEnd() error {
	p.skip()
	if p.i < len(p.src) {
		return fmt.Errorf("unexpected input near %q", p.src[p.i:])
	}
	return nil
}

func (p *parser) parseOr() (any, error) {
	left, err := p.parseAnd()
	if err != nil {
		return nil, err
	}
	for {
		p.skip()
		if p.matchWord("OR") {
			right, err := p.parseAnd()
			if err != nil {
				return nil, err
			}
			left = asBool(left) || asBool(right)
		} else {
			break
		}
	}
	return left, nil
}

func (p *parser) parseAnd() (any, error) {
	left, err := p.parseComparison()
	if err != nil {
		return nil, err
	}
	for {
		p.skip()
		if p.matchWord("AND") {
			right, err := p.parseComparison()
			if err != nil {
				return nil, err
			}
			left = asBool(left) && asBool(right)
		} else {
			break
		}
	}
	return left, nil
}

func (p *parser) parseComparison() (any, error) {
	left, err := p.parseAdd()
	if err != nil {
		return nil, err
	}
	p.skip()
	var op string
	switch {
	case p.matchStr("=="):
		op = "=="
	case p.matchStr("!="):
		op = "!="
	case p.matchStr("<="):
		op = "<="
	case p.matchStr(">="):
		op = ">="
	case p.matchStr("<"):
		op = "<"
	case p.matchStr(">"):
		op = ">"
	default:
		return left, nil
	}
	right, err := p.parseAdd()
	if err != nil {
		return nil, err
	}
	if isUnset(left) || isUnset(right) {
		return false, nil
	}
	switch op {
	case "==":
		return equals(left, right), nil
	case "!=":
		return !equals(left, right), nil
	case "<=":
		return toNum(left) <= toNum(right), nil
	case ">=":
		return toNum(left) >= toNum(right), nil
	case "<":
		return toNum(left) < toNum(right), nil
	case ">":
		return toNum(left) > toNum(right), nil
	default:
		return left, nil
	}
}

func (p *parser) parseAdd() (any, error) {
	left, err := p.parseMul()
	if err != nil {
		return nil, err
	}
	for {
		p.skip()
		if p.matchStr("+") {
			right, err := p.parseMul()
			if err != nil {
				return nil, err
			}
			left, err = arith(left, right, func(a, b float64) float64 { return a + b })
			if err != nil {
				return nil, err
			}
		} else if p.matchStr("-") {
			right, err := p.parseMul()
			if err != nil {
				return nil, err
			}
			left, err = arith(left, right, func(a, b float64) float64 { return a - b })
			if err != nil {
				return nil, err
			}
		} else {
			break
		}
	}
	return left, nil
}

func (p *parser) parseMul() (any, error) {
	left, err := p.parseUnary()
	if err != nil {
		return nil, err
	}
	for {
		p.skip()
		if p.matchStr("*") {
			right, err := p.parseUnary()
			if err != nil {
				return nil, err
			}
			left, err = arith(left, right, func(a, b float64) float64 { return a * b })
			if err != nil {
				return nil, err
			}
		} else if p.matchStr("/") {
			right, err := p.parseUnary()
			if err != nil {
				return nil, err
			}
			left, err = arith(left, right, func(a, b float64) float64 {
				if b == 0 {
					return 0
				}
				return a / b
			})
			if err != nil {
				return nil, err
			}
		} else {
			break
		}
	}
	return left, nil
}

func (p *parser) parseUnary() (any, error) {
	p.skip()
	if p.matchStr("-") {
		v, err := p.parseUnary()
		if err != nil {
			return nil, err
		}
		if isUnset(v) {
			return v, nil
		}
		return -toNum(v), nil
	}
	if p.matchStr("+") {
		v, err := p.parseUnary()
		if err != nil {
			return nil, err
		}
		if isUnset(v) {
			return v, nil
		}
		return toNum(v), nil
	}
	return p.parsePrimary()
}

func (p *parser) parsePrimary() (any, error) {
	p.skip()
	if p.matchStr("(") {
		v, err := p.parseOr()
		if err != nil {
			return nil, err
		}
		p.skip()
		if !p.matchStr(")") {
			return nil, fmt.Errorf("expected )")
		}
		return v, nil
	}
	if p.i < len(p.src) && p.src[p.i] == '"' {
		p.i++
		start := p.i
		for p.i < len(p.src) && p.src[p.i] != '"' {
			p.i++
		}
		if p.i >= len(p.src) {
			return nil, fmt.Errorf("unterminated string")
		}
		s := p.src[start:p.i]
		p.i++
		return s, nil
	}
	if p.i < len(p.src) && (p.src[p.i] >= '0' && p.src[p.i] <= '9' || p.src[p.i] == '.') {
		start := p.i
		for p.i < len(p.src) && (p.src[p.i] >= '0' && p.src[p.i] <= '9' || p.src[p.i] == '.') {
			p.i++
		}
		var f float64
		_, err := fmt.Sscanf(p.src[start:p.i], "%f", &f)
		if err != nil {
			return nil, err
		}
		return f, nil
	}
	id, ok := p.readIdent()
	if !ok {
		return nil, fmt.Errorf("expected value near %q", p.src[p.i:])
	}
	up := strings.ToUpper(id)
	switch up {
	case "TRUE":
		return true, nil
	case "FALSE":
		return false, nil
	}
	v, err := p.lookup(id)
	if err != nil {
		return nil, err
	}
	if _, isThreshold := unsetThresholdFields[id]; isThreshold {
		if f, ok := v.(float64); ok && f <= 0 {
			return unsetVal, nil
		}
	}
	return v, nil
}

func (p *parser) lookup(id string) (any, error) {
	switch id {
	case "curr_price":
		return p.ctx.CurrPrice, nil
	case "avg_buy_price":
		return p.ctx.AvgBuyPrice, nil
	case "last_trade_price":
		return p.ctx.LastTradePrice, nil
	case "last_trade_is_buy":
		return p.ctx.LastTradeIsBuy, nil
	case "last_trade_is_sale":
		return p.ctx.LastTradeIsSale, nil
	case "last_trade_is_hold":
		return p.ctx.LastTradeIsHold, nil
	case "last_trade_trend":
		return p.ctx.LastTradeTrend, nil
	case "trend_matches_last_action":
		return p.ctx.TrendMatchesLastAction, nil
	case "abs_pct_from_last_trade":
		return p.ctx.AbsPctFromLastTrade, nil
	case "highest_price":
		return p.ctx.HighestPrice, nil
	case "lowest_price":
		return p.ctx.LowestPrice, nil
	case "sixth_highest_price":
		return p.ctx.SixthHighestPrice, nil
	case "sixth_lowest_price":
		return p.ctx.SixthLowestPrice, nil
	case "trend":
		return p.ctx.Trend, nil
	case "set_buy_price":
		return p.ctx.SetBuyPrice, nil
	case "set_profit_booking_price":
		return p.ctx.SetProfitBookingPrice, nil
	case "set_stop_loss_price":
		return p.ctx.SetStopLossPrice, nil
	}
	if v, ok := p.ctx.NamedValues[id]; ok {
		return v, nil
	}
	return nil, fmt.Errorf("unknown identifier %q", id)
}

func (p *parser) readIdent() (string, bool) {
	p.skip()
	if p.i >= len(p.src) {
		return "", false
	}
	c := p.src[p.i]
	if !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_') {
		return "", false
	}
	start := p.i
	p.i++
	for p.i < len(p.src) {
		d := p.src[p.i]
		if (d >= 'A' && d <= 'Z') || (d >= 'a' && d <= 'z') || (d >= '0' && d <= '9') || d == '_' {
			p.i++
		} else {
			break
		}
	}
	return p.src[start:p.i], true
}

func (p *parser) matchWord(word string) bool {
	save := p.i
	id, ok := p.readIdent()
	if ok && strings.EqualFold(id, word) {
		return true
	}
	p.i = save
	return false
}

func (p *parser) matchStr(s string) bool {
	p.skip()
	if strings.HasPrefix(p.src[p.i:], s) {
		p.i += len(s)
		return true
	}
	return false
}

func (p *parser) skip() {
	for p.i < len(p.src) && (p.src[p.i] == ' ' || p.src[p.i] == '\t' || p.src[p.i] == '\n' || p.src[p.i] == '\r') {
		p.i++
	}
}

func asBool(v any) bool {
	if isUnset(v) {
		return false
	}
	switch t := v.(type) {
	case bool:
		return t
	case float64:
		return t != 0
	case string:
		return t != ""
	default:
		return false
	}
}

func isUnset(v any) bool {
	_, ok := v.(unsetMarker)
	return ok
}

func arith(a, b any, op func(float64, float64) float64) (any, error) {
	if isUnset(a) || isUnset(b) {
		return unsetVal, nil
	}
	return op(toNum(a), toNum(b)), nil
}

func toNum(v any) float64 {
	switch t := v.(type) {
	case float64:
		return t
	case bool:
		if t {
			return 1
		}
		return 0
	case string:
		var f float64
		fmt.Sscanf(t, "%f", &f)
		return f
	default:
		return 0
	}
}

func equals(a, b any) bool {
	if fa, ok := a.(float64); ok {
		if fb, ok := b.(float64); ok {
			return math.Abs(fa-fb) < 1e-12
		}
	}
	return fmt.Sprint(a) == fmt.Sprint(b)
}
