package casimport

import (
	"os"
	"strings"
	"testing"

	"financetracker/models"
)

// Optional: set CAS_TEST_PDF and CAS_TEST_PASSWORD to validate a real NSDL e-CAS.
// Logs only source names and counts — never holdings rows or personal fields.
func TestParsePDFLiveOptional(t *testing.T) {
	path := strings.TrimSpace(os.Getenv("CAS_TEST_PDF"))
	pw := strings.TrimSpace(os.Getenv("CAS_TEST_PASSWORD"))
	if path == "" || pw == "" {
		t.Skip("set CAS_TEST_PDF and CAS_TEST_PASSWORD to run")
	}
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	res, err := ParsePDF(b, pw)
	if err != nil {
		t.Fatal(err)
	}
	stocks, mfs := 0, 0
	for _, a := range res.Accounts {
		t.Logf("source=%s equities=%d mfs=%d", a.Source, len(a.Equities), len(a.MutualFunds))
		stocks += len(a.Equities)
		mfs += len(a.MutualFunds)
		if a.Source == models.SourceNSDLMFFolios && len(a.Equities) != 0 {
			t.Fatalf("folio source should not have equities")
		}
	}
	if stocks == 0 && mfs == 0 {
		t.Fatal("no holdings parsed")
	}
}
