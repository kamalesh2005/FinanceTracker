// Package casimport parses password-protected NSDL e-CAS PDFs into holdings
// keyed by broker-named sources (no demat/client/folio identifiers).
package casimport

import "fmt"

// EquityHolding is a demat equity/ETF share line from the holdings section.
type EquityHolding struct {
	Symbol   string
	ISIN     string
	Name     string
	Quantity float64
}

// MFHolding is a mutual fund line (demat or SOA folio). AvgCost is 0 when the
// statement does not provide cost basis.
type MFHolding struct {
	ISIN       string
	Name       string
	Units      float64
	AvgCost    float64
	CurrentNAV float64
}

// AccountHoldings groups equities and MFs under one portfolio source.
type AccountHoldings struct {
	Source       string
	Equities     []EquityHolding
	MutualFunds  []MFHolding
}

// Result is the full parsed CAS holdings snapshot (transactions ignored).
type Result struct {
	Accounts []AccountHoldings
}

// ErrInvalidPassword is returned when the PDF open password is wrong.
var ErrInvalidPassword = fmt.Errorf("invalid CAS password")

// ErrNotCAS is returned when the decrypted PDF does not look like an NSDL e-CAS.
var ErrNotCAS = fmt.Errorf("file does not look like an NSDL e-CAS")
