package handlers

import (
	"testing"

	"financetracker/models"
)

func TestNormalizeSchemeName_HyphenAndWhitespace(t *testing.T) {
	a := normalizeSchemeName("SBI Contra Fund - Regular Plan - Growth")
	b := normalizeSchemeName("SBI Contra Fund Regular Plan Growth")
	if a == "" || a != b {
		t.Fatalf("hyphen/whitespace mismatch: %q vs %q", a, b)
	}
}

func TestNormalizeSchemeName_IDCWPhrase(t *testing.T) {
	short := normalizeSchemeName("Franklin India Flexi Cap Fund - IDCW")
	long := normalizeSchemeName(
		"Franklin India Flexi Cap Fund - Income Distribution cum Capital Withdrawal Option (IDCW)",
	)
	if short == "" || short != long {
		t.Fatalf("IDCW phrase mismatch: %q vs %q", short, long)
	}
	if !containsToken(short, "idcw") {
		t.Fatalf("expected idcw token in %q", short)
	}
	if containsToken(short, "income") {
		t.Fatalf("expected long IDCW phrase collapsed in %q", short)
	}
}

func TestNormalizeSchemeName_PunctuationNoise(t *testing.T) {
	a := normalizeSchemeName("Axis Midcap Fund / Growth")
	b := normalizeSchemeName("Axis Midcap Fund Growth")
	if a != b {
		t.Fatalf("punctuation mismatch: %q vs %q", a, b)
	}
}

func TestNormalizeSchemeName_Empty(t *testing.T) {
	if got := normalizeSchemeName("   "); got != "" {
		t.Fatalf("expected empty, got %q", got)
	}
}

func TestMFSchemeCatalogIndex_FindByNormalizedName(t *testing.T) {
	rows := []models.GlobalMutualFund{
		{ID: 1, ISIN: "INF000000001", Symbol: "1001", SchemeName: "SBI Contra Fund Regular Plan Growth"},
		{ID: 2, ISIN: "INF000000002", Symbol: "1002", SchemeName: "Franklin India Flexi Cap Fund - Income Distribution cum Capital Withdrawal Option (IDCW)"},
	}
	idx := &mfSchemeCatalogIndex{
		byNorm: make(map[string]*models.GlobalMutualFund),
		byISIN: make(map[string]*models.GlobalMutualFund),
		rows:   rows,
	}
	for i := range rows {
		row := &idx.rows[i]
		idx.byISIN[row.ISIN] = row
		idx.byNorm[normalizeSchemeName(row.SchemeName)] = row
	}

	got, err := idx.findBySchemeName("SBI Contra Fund - Regular Plan - Growth")
	if err != nil || got == nil || got.ISIN != "INF000000001" {
		t.Fatalf("hyphen match failed: got=%v err=%v", got, err)
	}

	got, err = idx.findBySchemeName("Franklin India Flexi Cap Fund - IDCW")
	if err != nil || got == nil || got.ISIN != "INF000000002" {
		t.Fatalf("IDCW match failed: got=%v err=%v", got, err)
	}

	_, err = idx.findBySchemeName("Completely Unknown Fund XYZ")
	if err == nil {
		t.Fatal("expected non-match to fail")
	}
}

func TestMFSchemeCatalogIndex_ISINFallback(t *testing.T) {
	rows := []models.GlobalMutualFund{
		{ID: 1, ISIN: "INF846K01164", Symbol: "2001", SchemeName: "AXIS LARGE CAP FUND - REGULAR GROWTH"},
	}
	idx := &mfSchemeCatalogIndex{
		byNorm: make(map[string]*models.GlobalMutualFund),
		byISIN: map[string]*models.GlobalMutualFund{
			"INF846K01164": &rows[0],
		},
		rows: rows,
	}
	idx.byNorm[normalizeSchemeName(rows[0].SchemeName)] = &rows[0]

	got, err := idx.resolveImport("Some Totally Different Name", "INF846K01164")
	if err != nil || got == nil || got.ISIN != "INF846K01164" {
		t.Fatalf("ISIN fallback failed: got=%v err=%v", got, err)
	}
}

func containsToken(s, token string) bool {
	for _, part := range splitSpaces(s) {
		if part == token {
			return true
		}
	}
	return false
}

func splitSpaces(s string) []string {
	out := []string{}
	cur := ""
	for _, r := range s {
		if r == ' ' {
			if cur != "" {
				out = append(out, cur)
				cur = ""
			}
			continue
		}
		cur += string(r)
	}
	if cur != "" {
		out = append(out, cur)
	}
	return out
}
