package nsemf

import (
	"testing"
)

func TestLooksLikeMFVarCSV(t *testing.T) {
	ok := []byte("ISIN,SYMBOL,SERIES,TYPE,HAIRCUT,NAV\nINF123,1,DP,OMF,9.00,12.22\n")
	if !looksLikeMFVarCSV(ok) {
		t.Fatal("expected valid MF_VAR header to pass")
	}
	if looksLikeMFVarCSV([]byte("<!DOCTYPE html><html>404</html>")) {
		t.Fatal("HTML must fail")
	}
	if looksLikeMFVarCSV([]byte("SYMBOL,CLOSE\nINFY,100\n")) {
		t.Fatal("non-NAV csv must fail")
	}
}
