package casimport

import (
	"strings"
	"unicode"

	"financetracker/models"
)

// reservedUploadSources must never be used as CAS demat sources so broker
// Excel/CSV uploads (ICICIDirect, HDFCSec, etc.) stay separate.
var reservedUploadSources = map[string]struct{}{
	models.SourceManualAdd:        {},
	models.SourceManualBulkUpload: {},
	models.SourceICICIDirect:      {},
	models.SourceHDFCSec:          {},
	models.SourceZerodha:          {},
	models.SourceNSDLMFFolios:     {},
}

// MapDPNameToSource maps an NSDL depository participant name to a CAS-only
// portfolio source label (prefixed with "NSDL "). Never uses broker upload
// source names, DP ID, client ID, or other account numbers.
func MapDPNameToSource(dpName string) string {
	label := sanitizeBrokerLabel(dpName)
	if label == "" || label == "NSDL Demat" {
		return "NSDL Demat"
	}
	src := "NSDL " + label
	if _, reserved := reservedUploadSources[src]; reserved {
		src = "NSDL Demat " + label
	}
	// Guard against accidental collision if sanitize ever yields a reserved name.
	if _, reserved := reservedUploadSources[src]; reserved {
		return "NSDL Demat"
	}
	return src
}

func sanitizeBrokerLabel(raw string) string {
	words := strings.Fields(strings.TrimSpace(raw))
	out := make([]string, 0, len(words))
	for _, w := range words {
		u := strings.ToUpper(strings.Trim(w, ".,"))
		switch u {
		case "LIMITED", "LTD", "LTD.", "PVT", "PRIVATE", "THE":
			continue
		}
		out = append(out, titleWord(w))
	}
	if len(out) == 0 {
		return "NSDL Demat"
	}
	label := strings.Join(out, " ")
	if len(label) > 40 {
		label = strings.TrimSpace(label[:40])
	}
	return label
}

func titleWord(w string) string {
	w = strings.Trim(w, ".,")
	if w == "" {
		return w
	}
	upper := strings.ToUpper(w)
	switch upper {
	case "ICICI", "HDFC", "SBI", "UTI", "NSE", "BSE", "NSDL", "CDSL",
		"AXIS", "IDFC", "PNB", "BOI", "YES", "IIFL", "NJ":
		return upper
	}
	runes := []rune(strings.ToLower(w))
	runes[0] = unicode.ToUpper(runes[0])
	return string(runes)
}

// findOrCreateAccount returns the account for source, appending if needed.
func findOrCreateAccount(accounts *[]AccountHoldings, source string) *AccountHoldings {
	for i := range *accounts {
		if (*accounts)[i].Source == source {
			return &(*accounts)[i]
		}
	}
	*accounts = append(*accounts, AccountHoldings{Source: source})
	return &(*accounts)[len(*accounts)-1]
}

// disambiguateSources ensures duplicate mapped names get opaque numeric suffixes
// without using account numbers. Prefer findOrCreateAccount so this is rarely needed.
func disambiguateSources(accounts []AccountHoldings) {
	seen := map[string]int{}
	for i := range accounts {
		base := accounts[i].Source
		n := seen[base]
		seen[base] = n + 1
		if n == 0 {
			continue
		}
		accounts[i].Source = base + " " + itoa(n+1)
	}
}

func itoa(n int) string {
	if n <= 0 {
		return "0"
	}
	var b [16]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
