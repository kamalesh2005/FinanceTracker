package trendrules

import (
	"fmt"
	"strconv"
	"strings"
	"unicode"
)

// Inputs are the market values used to classify a trend.
type Inputs struct {
	CurrPrice        float64
	MA7              float64
	MA20             float64
	MA50             float64
	AdjustedSTDelta  float64
	AdjustedMTDelta  float64
}

// ClassifyBearishStrength matches the historical classifyBearishStrength helper.
// threshold is the absolute magnitude (e.g. 10 means adjustedDelta < -10).
func ClassifyBearishStrength(currentPrice, fastMA, slowMA, adjustedDelta, threshold float64) int {
	if fastMA <= 0 || slowMA <= 0 {
		return 0
	}
	negThresh := -threshold
	if currentPrice < fastMA && fastMA < slowMA {
		if adjustedDelta < negThresh {
			return 2
		}
		return 1
	}
	if adjustedDelta < negThresh && fastMA <= slowMA {
		return 1
	}
	return 0
}

// Evaluate walks enabled rules in order and returns the first matching trend
// label (exit). Continues may accumulate but trends use exit; if nothing
// matches, returns TrendNeutral.
func Evaluate(rs Ruleset, in Inputs) string {
	rs.normalize()
	threshold := BearishDeltaThreshold(rs)
	ctx := map[string]any{
		"curr_price":          in.CurrPrice,
		"ma7":                 in.MA7,
		"ma20":                in.MA20,
		"ma50":                in.MA50,
		"adjusted_st_delta":   in.AdjustedSTDelta,
		"adjusted_mt_delta":   in.AdjustedMTDelta,
		"st_bearish_strength": float64(ClassifyBearishStrength(in.CurrPrice, in.MA7, in.MA20, in.AdjustedSTDelta, threshold)),
		"lt_bearish_strength": float64(ClassifyBearishStrength(in.CurrPrice, in.MA20, in.MA50, in.AdjustedMTDelta, threshold)),
	}
	for _, nv := range rs.NamedValues {
		ctx[nv.Name] = nv.Value
	}

	var continued []string
	for _, rule := range rs.Rules {
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
		continued = append(continued, rule.Recommendation)
	}
	if len(continued) > 0 {
		return continued[0]
	}
	return TrendNeutral
}

func evalBool(expr string, ctx map[string]any) (bool, error) {
	p := &parser{src: expr, ctx: ctx}
	v, err := p.parseOr()
	if err != nil {
		return false, err
	}
	p.skip()
	if p.i < len(p.src) {
		return false, fmt.Errorf("unexpected input near %q", p.src[p.i:])
	}
	return asBool(v), nil
}

type parser struct {
	src string
	ctx map[string]any
	i   int
}

func (p *parser) parseOr() (any, error) {
	left, err := p.parseAnd()
	if err != nil {
		return nil, err
	}
	for {
		p.skip()
		if !p.matchWord("OR") {
			break
		}
		right, err := p.parseAnd()
		if err != nil {
			return nil, err
		}
		left = asBool(left) || asBool(right)
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
		if !p.matchWord("AND") {
			break
		}
		right, err := p.parseComparison()
		if err != nil {
			return nil, err
		}
		left = asBool(left) && asBool(right)
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
	case p.match("=="):
		op = "=="
	case p.match("!="):
		op = "!="
	case p.match("<="):
		op = "<="
	case p.match(">="):
		op = ">="
	case p.match("<"):
		op = "<"
	case p.match(">"):
		op = ">"
	default:
		return left, nil
	}
	right, err := p.parseAdd()
	if err != nil {
		return nil, err
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
		if p.match("+") {
			right, err := p.parseMul()
			if err != nil {
				return nil, err
			}
			left = toNum(left) + toNum(right)
		} else if p.match("-") {
			right, err := p.parseMul()
			if err != nil {
				return nil, err
			}
			left = toNum(left) - toNum(right)
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
		if p.match("*") {
			right, err := p.parseUnary()
			if err != nil {
				return nil, err
			}
			left = toNum(left) * toNum(right)
		} else if p.match("/") {
			right, err := p.parseUnary()
			if err != nil {
				return nil, err
			}
			den := toNum(right)
			if den == 0 {
				left = 0.0
			} else {
				left = toNum(left) / den
			}
		} else {
			break
		}
	}
	return left, nil
}

func (p *parser) parseUnary() (any, error) {
	p.skip()
	if p.match("-") {
		v, err := p.parseUnary()
		if err != nil {
			return nil, err
		}
		return -toNum(v), nil
	}
	if p.match("+") {
		v, err := p.parseUnary()
		if err != nil {
			return nil, err
		}
		return toNum(v), nil
	}
	return p.parsePrimary()
}

func (p *parser) parsePrimary() (any, error) {
	p.skip()
	if p.match("(") {
		v, err := p.parseOr()
		if err != nil {
			return nil, err
		}
		p.skip()
		if !p.match(")") {
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
	if p.i < len(p.src) && (isDigit(p.src[p.i]) || p.src[p.i] == '.') {
		start := p.i
		for p.i < len(p.src) && (isDigit(p.src[p.i]) || p.src[p.i] == '.') {
			p.i++
		}
		f, err := strconv.ParseFloat(p.src[start:p.i], 64)
		if err != nil {
			return nil, err
		}
		return f, nil
	}
	id := p.readIdent()
	if id == "" {
		if p.i < len(p.src) {
			return nil, fmt.Errorf("expected value near %q", p.src[p.i:])
		}
		return nil, fmt.Errorf("expected value")
	}
	up := strings.ToUpper(id)
	if up == "TRUE" {
		return true, nil
	}
	if up == "FALSE" {
		return false, nil
	}
	v, ok := p.ctx[id]
	if !ok {
		return nil, fmt.Errorf("unknown identifier %q", id)
	}
	return v, nil
}

func (p *parser) readIdent() string {
	p.skip()
	if p.i >= len(p.src) {
		return ""
	}
	c := rune(p.src[p.i])
	if !unicode.IsLetter(c) && c != '_' {
		return ""
	}
	start := p.i
	p.i++
	for p.i < len(p.src) {
		c = rune(p.src[p.i])
		if unicode.IsLetter(c) || unicode.IsDigit(c) || c == '_' {
			p.i++
			continue
		}
		break
	}
	return p.src[start:p.i]
}

func (p *parser) matchWord(word string) bool {
	save := p.i
	id := p.readIdent()
	if id != "" && strings.EqualFold(id, word) {
		return true
	}
	p.i = save
	return false
}

func (p *parser) match(s string) bool {
	p.skip()
	if strings.HasPrefix(p.src[p.i:], s) {
		p.i += len(s)
		return true
	}
	return false
}

func (p *parser) skip() {
	for p.i < len(p.src) {
		c := p.src[p.i]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			p.i++
			continue
		}
		break
	}
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

func asBool(v any) bool {
	switch t := v.(type) {
	case bool:
		return t
	case float64:
		return t != 0
	case int:
		return t != 0
	case string:
		return t != ""
	default:
		return false
	}
}

func toNum(v any) float64 {
	switch t := v.(type) {
	case float64:
		return t
	case int:
		return float64(t)
	case bool:
		if t {
			return 1
		}
		return 0
	case string:
		f, err := strconv.ParseFloat(t, 64)
		if err != nil {
			return 0
		}
		return f
	default:
		return 0
	}
}

func equals(a, b any) bool {
	af, aOk := asFloat(a)
	bf, bOk := asFloat(b)
	if aOk && bOk {
		diff := af - bf
		if diff < 0 {
			diff = -diff
		}
		return diff < 1e-12
	}
	return fmt.Sprint(a) == fmt.Sprint(b)
}

func asFloat(v any) (float64, bool) {
	switch t := v.(type) {
	case float64:
		return t, true
	case int:
		return float64(t), true
	default:
		return 0, false
	}
}
