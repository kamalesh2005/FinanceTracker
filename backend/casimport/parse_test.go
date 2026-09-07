package casimport

import (
	"strings"
	"testing"

	"financetracker/models"
)

func TestMapDPNameToSource(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"ICICI BANK LIMITED", "NSDL ICICI Bank"},
		{"ICICI Securities Limited", "NSDL ICICI Securities"},
		{"HDFC BANK LIMITED", "NSDL HDFC Bank"},
		{"HDFC SECURITIES LTD", "NSDL HDFC Securities"},
		{"ZERODHA BROKING LIMITED", "NSDL Zerodha Broking"},
		{"KOTAK SECURITIES LIMITED", "NSDL Kotak Securities"},
		{"", "NSDL Demat"},
	}
	for _, tc := range cases {
		got := MapDPNameToSource(tc.in)
		if got != tc.want {
			t.Fatalf("MapDPNameToSource(%q)=%q want %q", tc.in, got, tc.want)
		}
		if got == models.SourceICICIDirect || got == models.SourceHDFCSec || got == models.SourceZerodha {
			t.Fatalf("CAS source must not collide with upload source %q", got)
		}
	}
}

func TestFindOrCreateAccountMerges(t *testing.T) {
	var accounts []AccountHoldings
	a := findOrCreateAccount(&accounts, "NSDL ICICI Bank")
	a.Equities = append(a.Equities, EquityHolding{Symbol: "TCS", Quantity: 1})
	b := findOrCreateAccount(&accounts, "NSDL ICICI Bank")
	b.Equities = append(b.Equities, EquityHolding{Symbol: "INFY", Quantity: 2})
	if len(accounts) != 1 {
		t.Fatalf("accounts=%d", len(accounts))
	}
	if len(accounts[0].Equities) != 2 {
		t.Fatalf("equities=%d", len(accounts[0].Equities))
	}
}

func TestParseStockSymbolLineGluedISIN(t *testing.T) {
	sym, isin, ok := parseStockSymbolLine("INE117A01022ABB.NSE")
	if !ok || sym != "ABB" || isin != "INE117A01022" {
		t.Fatalf("got sym=%q isin=%q ok=%v", sym, isin, ok)
	}
	sym, isin, ok = parseStockSymbolLine("RELIANCE.NSE")
	if !ok || sym != "RELIANCE" || isin != "" {
		t.Fatalf("got sym=%q isin=%q ok=%v", sym, isin, ok)
	}
}

func TestParseNSDLTextSynthetic(t *testing.T) {
	text := `
Consolidated Account Statement for the month of July 2026
NSDL Demat Account
ICICI BANK LIMITED
Your Demat Account and Mutual Fund Folios
NSDL Demat Account ICICI BANK LIMITED
DP ID: IN000000 Client ID: 00000000
ACCOUNT HOLDERS
Equities (E)
Equity Shares
ISIN
Stock Symbol
Company Name Face Value
INE002A01018RELIANCE.NSE
RELIANCE INDUSTRIES LIMITED 10.00 50 2800.00 140000.00
TCS.NSE
TATA CONSULTANCY SERVICES LIMITED 1.00 10 3500.50 35005.00
Mutual Funds (M)
ISIN ISIN Description No. of Units NAV Value
INF204K01XI3 HDFC GOLD EXCHANGE TRADED FUND 100.000 65.12 6512.00
INF109KC1O33 ICICI PRUDENTIAL BLUECHIP FUND 250.500 80.00 20040.00

NSDL Demat Account
HDFC BANK LIMITED
DP ID: IN111111 Client ID: 11111111
Equities (E)
SUZLON.NSE
SUZLON ENERGY LIMITED 2.00 1000 45.00 45000.00
Mutual Funds (M)
INF179KB1YZ6 HDFC HYBRID EQUITY FUND-REGULAR 500.00 90.25 45125.00
Mutual Fund Folios (F)
ISIN Description Folio No. No. of Units Cost Per Units Current NAV Current Value
INF846K01DP8 Axis Large Cap Fund MFAXIS0001 12345678 150.000 45.00 60.00 9000.00
INF090I01239 SBI Contra Fund - Regular Plan MFSBIM0025 87654321 200.25 110.50 150.75 30187.69
NSDL Demat Account
ICICI BANK LIMITED
Summary of Transactions of
ISIN : INE012A01025 - ACC LIMITED
About NSDL
`
	res, err := ParseNSDLText(text)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Accounts) != 3 {
		t.Fatalf("accounts=%d want 3: %+v", len(res.Accounts), sourcesOf(res))
	}

	icici := res.Accounts[0]
	if icici.Source != "NSDL ICICI Bank" {
		t.Fatalf("icici source=%q", icici.Source)
	}
	if len(icici.Equities) != 2 {
		t.Fatalf("icici equities=%d %+v", len(icici.Equities), icici.Equities)
	}
	if icici.Equities[0].Symbol != "RELIANCE" || icici.Equities[0].Quantity != 50 {
		t.Fatalf("equity0=%+v", icici.Equities[0])
	}
	if icici.Equities[0].ISIN != "INE002A01018" {
		t.Fatalf("equity0 isin=%q", icici.Equities[0].ISIN)
	}
	if len(icici.MutualFunds) != 2 {
		t.Fatalf("icici mfs=%d %+v", len(icici.MutualFunds), icici.MutualFunds)
	}
	if icici.MutualFunds[0].ISIN != "INF204K01XI3" || icici.MutualFunds[0].Units != 100 {
		t.Fatalf("mf0=%+v", icici.MutualFunds[0])
	}

	hdfc := res.Accounts[1]
	if hdfc.Source != "NSDL HDFC Bank" {
		t.Fatalf("hdfc source=%q", hdfc.Source)
	}
	if len(hdfc.Equities) != 1 || hdfc.Equities[0].Symbol != "SUZLON" {
		t.Fatalf("hdfc eq=%+v", hdfc.Equities)
	}
	if len(hdfc.MutualFunds) != 1 {
		t.Fatalf("hdfc mf=%+v", hdfc.MutualFunds)
	}

	folios := res.Accounts[2]
	if folios.Source != models.SourceNSDLMFFolios {
		t.Fatalf("folios source=%q", folios.Source)
	}
	if len(folios.MutualFunds) != 2 {
		t.Fatalf("folios=%+v", folios.MutualFunds)
	}
	if folios.MutualFunds[0].AvgCost != 45 || folios.MutualFunds[0].CurrentNAV != 60 {
		t.Fatalf("folio0=%+v", folios.MutualFunds[0])
	}
	if strings.Contains(folios.MutualFunds[0].Name, "MFAXIS") {
		t.Fatalf("folio name should not include RTA code: %q", folios.MutualFunds[0].Name)
	}
}

func TestParseNSDLTextRejectsNonCAS(t *testing.T) {
	_, err := ParseNSDLText("hello world invoice")
	if err != ErrNotCAS {
		t.Fatalf("err=%v", err)
	}
}

func sourcesOf(r Result) []string {
	out := make([]string, len(r.Accounts))
	for i, a := range r.Accounts {
		out[i] = a.Source
	}
	return out
}
