package casimport

import (
	"regexp"
	"strconv"
	"strings"

	"financetracker/models"
)

type parseMode int

const (
	modeNone parseMode = iota
	modeEquities
	modeDematMF
	modeFolioMF
	modeSkip
)

var (
	// Glued form when PDF extraction concatenates ISIN + ticker: INE117A01022ABB.NSE
	reStockSymbolGlued = regexp.MustCompile(`(?i)^(IN[A-Z0-9]{10})([A-Z0-9][A-Z0-9.&/-]{0,20})\.(NSE|BSE)$`)
	reStockSymbol      = regexp.MustCompile(`(?i)^([A-Z0-9][A-Z0-9.&/-]{0,20})\.(NSE|BSE)$`)
	reISIN             = regexp.MustCompile(`\b(IN[A-Z0-9]{10})\b`)
	rePctLine          = regexp.MustCompile(`%`)
)

// ParseNSDLText parses extracted plain text from an NSDL e-CAS holdings statement.
func ParseNSDLText(text string) (Result, error) {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	text = strings.ReplaceAll(text, "\r", "\n")
	if !looksLikeNSDLCAS(text) {
		return Result{}, ErrNotCAS
	}

	lines := splitLines(text)
	var accounts []AccountHoldings
	var folio *AccountHoldings
	var current *AccountHoldings
	mode := modeNone
	pendingISIN := ""
	pendingSymbol := ""
	var pendingNameParts []string

	ensureFolio := func() *AccountHoldings {
		if folio == nil {
			folio = &AccountHoldings{Source: models.SourceNSDLMFFolios}
		}
		return folio
	}

	for i := 0; i < len(lines); i++ {
		line := lines[i]
		upper := strings.ToUpper(line)

		if strings.Contains(upper, "SUMMARY OF TRANSACTIONS") ||
			strings.Contains(upper, "ABOUT NSDL") ||
			(strings.Contains(upper, "KNOW MORE ABOUT YOUR ACCOUNT") && !strings.Contains(upper, "HOLDING")) {
			mode = modeSkip
			pendingISIN = ""
			pendingSymbol = ""
			pendingNameParts = nil
			continue
		}

		if strings.Contains(upper, "NSDL DEMAT ACCOUNT") {
			mode = modeNone
			pendingISIN = ""
			pendingSymbol = ""
			pendingNameParts = nil
			dp := extractDPName(line, lines, i)
			if dp == "" {
				continue
			}
			src := MapDPNameToSource(dp)
			// Reuse the same CAS source when the PDF repeats demat headers
			// (summary + holdings + transactions).
			current = findOrCreateAccount(&accounts, src)
			continue
		}

		if isSectionHeader(upper, "EQUITIES (E)") {
			if current != nil {
				mode = modeEquities
			} else {
				mode = modeSkip
			}
			pendingISIN, pendingSymbol, pendingNameParts = "", "", nil
			continue
		}
		if isSectionHeader(upper, "MUTUAL FUNDS (M)") {
			if current != nil {
				mode = modeDematMF
			} else {
				mode = modeSkip
			}
			pendingISIN, pendingSymbol, pendingNameParts = "", "", nil
			continue
		}
		if isSectionHeader(upper, "MUTUAL FUND FOLIOS (F)") {
			mode = modeFolioMF
			current = nil // folios are not demat-sourced
			pendingISIN, pendingSymbol, pendingNameParts = "", "", nil
			continue
		}
		if isSectionHeader(upper, "PREFERENCE SHARES") ||
			isSectionHeader(upper, "SPECIALIZED INVESTMENT") ||
			isSectionHeader(upper, "GOVERNMENT SECURITIES") ||
			isSectionHeader(upper, "BONDS") ||
			isSectionHeader(upper, "DEBENTURES") {
			mode = modeSkip
			pendingISIN, pendingSymbol, pendingNameParts = "", "", nil
			continue
		}

		if mode == modeSkip || mode == modeNone {
			continue
		}
		if isTableNoise(line) {
			continue
		}

		switch mode {
		case modeEquities:
			if sym, isin, ok := parseStockSymbolLine(line); ok {
				pendingSymbol = sym
				pendingNameParts = nil
				if isin != "" {
					pendingISIN = isin
				} else if pendingISIN == "" {
					if found := firstISIN(line); found != "" && strings.HasPrefix(found, "INE") {
						pendingISIN = found
					}
				}
				continue
			}
			if isin := firstISIN(line); isin != "" && pendingSymbol == "" {
				pendingISIN = isin
				continue
			}
			if pendingSymbol == "" {
				continue
			}
			qty, name, ok := parseEquityDetail(line)
			if !ok {
				// Company name may wrap without numbers yet.
				if !hasDigit(line) && !reStockSymbol.MatchString(line) && !reStockSymbolGlued.MatchString(line) {
					pendingNameParts = append(pendingNameParts, line)
				}
				continue
			}
			if name == "" && len(pendingNameParts) > 0 {
				name = strings.Join(pendingNameParts, " ")
			}
			if current != nil && qty > 0 {
				current.Equities = append(current.Equities, EquityHolding{
					Symbol:   pendingSymbol,
					ISIN:     pendingISIN,
					Name:     cleanName(name),
					Quantity: qty,
				})
			}
			pendingISIN, pendingSymbol, pendingNameParts = "", "", nil

		case modeDematMF:
			h, consumed, restName := parseMFLine(line, pendingISIN, pendingNameParts)
			if consumed == "isin" {
				pendingISIN = firstISIN(line)
				pendingNameParts = nil
				continue
			}
			if consumed == "name" {
				pendingNameParts = append(pendingNameParts, restName)
				continue
			}
			if consumed == "row" && h.Units > 0 {
				if current != nil {
					current.MutualFunds = append(current.MutualFunds, h)
				}
				pendingISIN, pendingNameParts = "", nil
			}

		case modeFolioMF:
			h, consumed, restName := parseFolioMFLine(line, pendingISIN, pendingNameParts)
			if consumed == "isin" {
				pendingISIN = firstISIN(line)
				pendingNameParts = nil
				continue
			}
			if consumed == "name" {
				pendingNameParts = append(pendingNameParts, restName)
				continue
			}
			if consumed == "row" && h.Units > 0 {
				acc := ensureFolio()
				acc.MutualFunds = append(acc.MutualFunds, h)
				pendingISIN, pendingNameParts = "", nil
			}
		}
	}

	disambiguateSources(accounts)
	// Drop demat accounts that never received holdings (summary-only headers).
	filtered := make([]AccountHoldings, 0, len(accounts))
	for _, a := range accounts {
		if len(a.Equities) == 0 && len(a.MutualFunds) == 0 {
			continue
		}
		filtered = append(filtered, a)
	}
	out := Result{Accounts: filtered}
	if folio != nil && len(folio.MutualFunds) > 0 {
		out.Accounts = append(out.Accounts, *folio)
	}
	if totalHoldings(out) == 0 {
		return Result{}, ErrNotCAS
	}
	return out, nil
}

func parseStockSymbolLine(line string) (symbol, isin string, ok bool) {
	line = strings.TrimSpace(line)
	if m := reStockSymbolGlued.FindStringSubmatch(line); m != nil {
		return strings.ToUpper(m[2]), strings.ToUpper(m[1]), true
	}
	if m := reStockSymbol.FindStringSubmatch(line); m != nil {
		sym := strings.ToUpper(m[1])
		// Defensive: if capture still starts with a 12-char ISIN, split it.
		if len(sym) > 12 && reISIN.MatchString(sym[:12]) {
			return sym[12:], sym[:12], true
		}
		return sym, "", true
	}
	return "", "", false
}

func looksLikeNSDLCAS(text string) bool {
	u := strings.ToUpper(text)
	return strings.Contains(u, "NSDL") &&
		(strings.Contains(u, "CONSOLIDATED ACCOUNT STATEMENT") ||
			strings.Contains(u, "NSDL DEMAT ACCOUNT") ||
			strings.Contains(u, "MUTUAL FUND FOLIOS"))
}

func splitLines(text string) []string {
	raw := strings.Split(text, "\n")
	out := make([]string, 0, len(raw))
	for _, ln := range raw {
		ln = strings.TrimSpace(ln)
		if ln == "" {
			continue
		}
		out = append(out, ln)
	}
	return out
}

func isSectionHeader(upper, key string) bool {
	if !strings.Contains(upper, key) {
		return false
	}
	// Portfolio composition summary lines include % — skip those.
	if rePctLine.MatchString(upper) {
		return false
	}
	return true
}

func extractDPName(line string, lines []string, idx int) string {
	upper := strings.ToUpper(line)
	if rest := strings.TrimSpace(line[strings.Index(upper, "NSDL DEMAT ACCOUNT")+len("NSDL DEMAT ACCOUNT"):]); rest != "" {
		if !strings.HasPrefix(strings.ToUpper(rest), "DP ID") {
			return stripDPNoise(rest)
		}
	}
	for j := idx + 1; j < len(lines) && j <= idx+3; j++ {
		cand := strings.TrimSpace(lines[j])
		cu := strings.ToUpper(cand)
		if cu == "" || strings.HasPrefix(cu, "DP ID") || strings.HasPrefix(cu, "CLIENT ID") {
			continue
		}
		if strings.Contains(cu, "ACCOUNT HOLDER") || strings.Contains(cu, "EQUITIES") {
			break
		}
		return stripDPNoise(cand)
	}
	return ""
}

func stripDPNoise(s string) string {
	s = reISIN.ReplaceAllString(s, "")
	// Drop trailing DP/Client fragments if present on same line.
	if i := strings.Index(strings.ToUpper(s), "DP ID"); i >= 0 {
		s = s[:i]
	}
	if i := strings.Index(strings.ToUpper(s), "CLIENT ID"); i >= 0 {
		s = s[:i]
	}
	return strings.TrimSpace(s)
}

func isTableNoise(line string) bool {
	u := strings.ToUpper(line)
	noise := []string{
		"STOCK SYMBOL", "COMPANY NAME", "FACE VALUE", "NO. OF", "SHARES",
		"VALUE IN", "ISIN DESCRIPTION", "CURRENT NAV", "CURRENT VALUE",
		"COST PER", "AVERAGE COST", "FOLIO NO", "UCC", "NAV",
		"CONSOLIDATED ACCOUNT STATEMENT", "SUMMARY HOLDINGS TRANSACTIONS",
		"PORTFOLIO COMPOSITION", "ASSET CLASS", "ACCOUNT HOLDERS", "ACCOUNT HOLDER",
		"EQUITY SHARES", "HOLDINGS AS ON", "SUMMARY OF VALUE",
	}
	for _, n := range noise {
		if u == n || u == n+":" {
			return true
		}
	}
	// Lone column headers
	if u == "ISIN" || u == "UNITS" || u == "AVERAGE" {
		return true
	}
	return false
}

func firstISIN(line string) string {
	m := reISIN.FindStringSubmatch(line)
	if m == nil {
		return ""
	}
	return strings.ToUpper(m[1])
}

func parseEquityDetail(line string) (qty float64, name string, ok bool) {
	nums := parseNumbers(line)
	if len(nums) == 0 {
		return 0, "", false
	}
	switch {
	case len(nums) >= 4:
		qty = nums[1]
	case len(nums) == 3:
		qty = nums[0]
	case len(nums) == 2:
		qty = nums[0]
	default:
		qty = nums[0]
	}
	if qty <= 0 {
		return 0, "", false
	}
	name = trimTrailingNumbers(line)
	return qty, name, true
}

func parseMFLine(line, pendingISIN string, pendingName []string) (MFHolding, string, string) {
	isin := firstISIN(line)
	stripped := reISIN.ReplaceAllString(line, " ")
	nums := parseNumbers(stripped)
	if isin != "" && len(nums) == 0 {
		return MFHolding{}, "isin", ""
	}
	if len(nums) == 0 {
		if pendingISIN != "" && !isTableNoise(line) && !hasOnlyNoiseTokens(line) {
			return MFHolding{}, "name", cleanName(line)
		}
		return MFHolding{}, "", ""
	}
	if len(nums) < 2 {
		return MFHolding{}, "", ""
	}
	h := MFHolding{
		ISIN:       firstNonEmpty(isin, pendingISIN),
		Units:      nums[0],
		CurrentNAV: nums[1],
	}
	if h.ISIN == "" {
		return MFHolding{}, "", ""
	}
	name := trimTrailingNumbers(stripped)
	if name == "" && len(pendingName) > 0 {
		name = strings.Join(pendingName, " ")
	}
	h.Name = cleanName(name)
	return h, "row", ""
}

func parseFolioMFLine(line, pendingISIN string, pendingName []string) (MFHolding, string, string) {
	isin := firstISIN(line)
	stripped := reISIN.ReplaceAllString(line, " ")
	stripped = stripFolioTokens(stripped)
	nums := parseNumbers(stripped)
	if isin != "" && len(nums) == 0 {
		return MFHolding{}, "isin", ""
	}
	if len(nums) == 0 {
		if (pendingISIN != "" || isin != "") && !isTableNoise(line) && !hasOnlyNoiseTokens(line) {
			return MFHolding{}, "name", cleanName(stripped)
		}
		return MFHolding{}, "", ""
	}
	if len(nums) < 2 {
		return MFHolding{}, "", ""
	}
	h := MFHolding{
		ISIN: firstNonEmpty(isin, pendingISIN),
	}
	// Folio rows: [folioNo?] units, cost/unit, current NAV, current value [, gain]
	nums = dropLeadingFolioNumber(nums)
	if len(nums) < 2 {
		return MFHolding{}, "", ""
	}
	switch {
	case len(nums) >= 4:
		h.Units = nums[0]
		h.AvgCost = nums[1]
		h.CurrentNAV = nums[2]
	case len(nums) == 3:
		h.Units = nums[0]
		h.AvgCost = nums[1]
		h.CurrentNAV = nums[2]
	default:
		h.Units = nums[0]
		h.CurrentNAV = nums[1]
	}
	if h.ISIN == "" || h.Units <= 0 {
		return MFHolding{}, "", ""
	}
	name := trimTrailingNumbers(stripped)
	if name == "" && len(pendingName) > 0 {
		name = strings.Join(pendingName, " ")
	}
	h.Name = cleanName(name)
	return h, "row", ""
}

// dropLeadingFolioNumber removes a leading integer that looks like a folio id
// (large whole number) when more value fields follow.
func dropLeadingFolioNumber(nums []float64) []float64 {
	if len(nums) < 3 {
		return nums
	}
	n0 := nums[0]
	if n0 >= 100000 && n0 == float64(int64(n0)) {
		return nums[1:]
	}
	return nums
}

func stripFolioTokens(name string) string {
	parts := strings.Fields(name)
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		u := strings.ToUpper(p)
		// Skip RTA-style codes like MFAXIS0001 / folio numbers.
		if matched, _ := regexp.MatchString(`(?i)^MF[A-Z]{2,8}\d{2,6}$`, u); matched {
			continue
		}
		if matched, _ := regexp.MatchString(`^\d{6,}$`, u); matched {
			continue
		}
		out = append(out, p)
	}
	return strings.Join(out, " ")
}

func parseNumbers(line string) []float64 {
	// Prefer comma-grouped Indian numbers.
	re := regexp.MustCompile(`\d{1,3}(?:,\d{2,3})+(?:\.\d+)?|\d+\.\d+|\d+`)
	ms := re.FindAllString(line, -1)
	out := make([]float64, 0, len(ms))
	for _, s := range ms {
		s = strings.ReplaceAll(s, ",", "")
		v, err := strconv.ParseFloat(s, 64)
		if err != nil {
			continue
		}
		out = append(out, v)
	}
	return out
}

func trimTrailingNumbers(line string) string {
	re := regexp.MustCompile(`[\d,]+\.?\d*\s*$`)
	s := line
	for {
		next := strings.TrimSpace(re.ReplaceAllString(s, ""))
		if next == s {
			break
		}
		s = next
	}
	return strings.TrimSpace(s)
}

func cleanName(s string) string {
	s = strings.TrimSpace(s)
	s = strings.Join(strings.Fields(s), " ")
	return s
}

func hasDigit(s string) bool {
	for _, r := range s {
		if r >= '0' && r <= '9' {
			return true
		}
	}
	return false
}

func hasOnlyNoiseTokens(line string) bool {
	u := strings.ToUpper(strings.TrimSpace(line))
	switch u {
	case "REGULAR", "GROWTH", "DIRECT", "PLAN", "FUND", "-":
		return true
	}
	return false
}

func firstNonEmpty(a, b string) string {
	if strings.TrimSpace(a) != "" {
		return a
	}
	return b
}

func totalHoldings(r Result) int {
	n := 0
	for _, a := range r.Accounts {
		n += len(a.Equities) + len(a.MutualFunds)
	}
	return n
}
