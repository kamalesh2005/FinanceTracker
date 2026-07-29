package trendlyne

import (
	"strings"
	"testing"
)

func TestParseConsensusHTML_TCS(t *testing.T) {
	html := `<!doctype html><html><body>
<table>
<thead><tr>
<th>Summary</th><th>Date</th><th>Stock</th><th>Author</th><th>LTP</th><th>Target</th>
<th>Price at reco(Change since reco%)</th><th>Upside(%)</th><th>Type</th><th>Report</th>
</tr></thead>
<tbody>
<tr>
<td></td>
<td>29 Jul 2026</td>
<td>TCS</td>
<td><a href="/equity/consensus-estimates/1372/TCS/tata-consultancy-services-ltd/">Consensus Share Price Target</a></td>
<td>2449.60</td>
<td>2481.05</td>
<td>-</td>
<td>1.28</td>
<td><a href="#">buy</a></td>
<td>pdf</td>
</tr>
<tr>
<td></td>
<td>10 Jul 2026</td>
<td>TCS</td>
<td>Deven Choksey</td>
<td>2449.60</td>
<td>2525.00</td>
<td>2049.50 (19.52%)</td>
<td>3.08</td>
<td>Buy</td>
<td>pdf</td>
</tr>
</tbody>
</table>
</body></html>`

	got, err := ParseConsensusHTML("TCS", []byte(html))
	if err != nil {
		t.Fatal(err)
	}
	if got.Target != 2481.05 {
		t.Fatalf("target=%v", got.Target)
	}
	if got.LTP != 2449.60 {
		t.Fatalf("ltp=%v", got.LTP)
	}
	if got.Upside != 1.28 {
		t.Fatalf("upside=%v", got.Upside)
	}
	if got.Type != "buy" {
		t.Fatalf("type=%q", got.Type)
	}
	if !got.HasDate || got.Date.Format("2006-01-02") != "2026-07-29" {
		t.Fatalf("date=%v has=%v", got.Date, got.HasDate)
	}
}

func TestParseConsensusHTML_FirstRowFallback(t *testing.T) {
	html := `<table>
<tr><th>Date</th><th>Stock</th><th>Author</th><th>LTP</th><th>Target</th><th>Upside(%)</th><th>Type</th></tr>
<tr>
<td>10 Jul 2026</td>
<td>TCS</td>
<td>Motilal Oswal</td>
<td>2449.60</td>
<td>2525.00</td>
<td>3.08</td>
<td>Buy</td>
</tr>
<tr>
<td>01 Jun 2026</td>
<td>TCS</td>
<td>ICICI Direct</td>
<td>2449.60</td>
<td>2600.00</td>
<td>6.14</td>
<td>Buy</td>
</tr>
</table>`

	got, err := ParseConsensusHTML("TCS", []byte(html))
	if err != nil {
		t.Fatal(err)
	}
	if got.Target != 2525.00 {
		t.Fatalf("expected first-row target 2525, got %v", got.Target)
	}
	if got.LTP != 2449.60 {
		t.Fatalf("ltp=%v", got.LTP)
	}
	if got.Upside != 3.08 {
		t.Fatalf("upside=%v", got.Upside)
	}
	if got.Type != "buy" {
		t.Fatalf("type=%q", got.Type)
	}
	if !got.HasDate || got.Date.Format("2006-01-02") != "2026-07-10" {
		t.Fatalf("date=%v has=%v", got.Date, got.HasDate)
	}
}

func TestParseConsensusHTML_HeaderOnly(t *testing.T) {
	html := `<table><tr><th>Author</th><th>Target</th><th>Upside</th></tr></table>`
	_, err := ParseConsensusHTML("TCS", []byte(html))
	if err == nil || !strings.Contains(err.Error(), "PARSE_FAIL") {
		t.Fatalf("expected PARSE_FAIL, got %v", err)
	}
}

func TestParseConsensusHTML_SymbolMismatch(t *testing.T) {
	html := `<table>
<tr><th>Date</th><th>Stock</th><th>Author</th><th>LTP</th><th>Target</th><th>Upside(%)</th><th>Type</th></tr>
<tr><td>29 Jul 2026</td><td>INFY</td><td>Consensus Share Price Target</td><td>100</td><td>120</td><td>20</td><td>buy</td></tr>
</table>`
	_, err := ParseConsensusHTML("TCS", []byte(html))
	if err == nil || !strings.Contains(err.Error(), "PARSE_FAIL") {
		t.Fatalf("expected symbol mismatch PARSE_FAIL, got %v", err)
	}
}

func TestParseConsensusHTML_DisplayNameInStockCell(t *testing.T) {
	html := `<!doctype html><html><body>
<a href="/equity/about/1723/ADANIENT/adani-enterprises-ltd/">Adani Enterprises Ltd.</a>
<span>NSE: ADANIENT | BSE: 512599</span>
<table>
<tr><th>Date</th><th>Stock</th><th>Author</th><th>LTP</th><th>Target</th><th>Upside(%)</th><th>Type</th></tr>
<tr><td>29 Jul 2026</td><td>Adani Enterpris</td><td>Consensus Share Price Target</td><td>2400.00</td><td>2900.50</td><td>20.85</td><td>buy</td></tr>
</table>
</body></html>`

	got, err := ParseConsensusHTML("ADANIENT", []byte(html))
	if err != nil {
		t.Fatal(err)
	}
	if got.Target != 2900.50 {
		t.Fatalf("target=%v", got.Target)
	}
	if got.Type != "buy" {
		t.Fatalf("type=%q", got.Type)
	}
}

func TestParseConsensusHTML_WrongCompanyPage(t *testing.T) {
	html := `<!doctype html><html><body>
<a href="/equity/about/1723/PRIVISCL/privi-speciality-chemicals-ltd/">Privi Speciality Chemicals Ltd.</a>
<span>NSE: PRIVISCL | BSE: 530117</span>
<table>
<tr><th>Date</th><th>Stock</th><th>Author</th><th>LTP</th><th>Target</th><th>Upside(%)</th><th>Type</th></tr>
<tr><td>29 Jul 2026</td><td>Privi Speciality</td><td>Consensus Share Price Target</td><td>3614.20</td><td>4086.33</td><td>13.06</td><td>buy</td></tr>
</table>
</body></html>`

	_, err := ParseConsensusHTML("ADANIENT", []byte(html))
	if err == nil || !strings.Contains(err.Error(), "page is for PRIVISCL") {
		t.Fatalf("expected wrong-company PARSE_FAIL, got %v", err)
	}
}

func TestParseConsensusHTML_MalformedNumber(t *testing.T) {
	html := `<table>
<tr><th>Date</th><th>Stock</th><th>Author</th><th>LTP</th><th>Target</th><th>Upside(%)</th><th>Type</th></tr>
<tr><td>29 Jul 2026</td><td>TCS</td><td>Consensus Share Price Target</td><td>abc</td><td>xyz</td><td>na</td><td>buy</td></tr>
</table>`
	_, err := ParseConsensusHTML("TCS", []byte(html))
	if err == nil || !strings.Contains(err.Error(), "PARSE_FAIL") {
		t.Fatalf("expected PARSE_FAIL for malformed numbers, got %v", err)
	}
}

func TestValidateReportURL(t *testing.T) {
	ok := ValidateReportURL("TCS", "https://trendlyne.com/research-reports/stock/1372/TCS/tata-consultancy-services-ltd/")
	if !ok {
		t.Fatal("expected valid")
	}
	if ValidateReportURL("TCS", "https://trendlyne.com/research-reports/stock/1372/INFY/foo/") {
		t.Fatal("expected invalid for wrong symbol")
	}
}
