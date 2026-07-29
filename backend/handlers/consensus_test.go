package handlers

import (
	"errors"
	"fmt"
	"reflect"
	"testing"
)

func TestConsensusLookupCandidates_SourceOnly(t *testing.T) {
	got := consensusLookupCandidates("TCS", "TCS", "")
	want := []string{"TCS"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}

	got = consensusLookupCandidates("TCS", "", "")
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("empty mapped: got %v want %v", got, want)
	}
}

func TestConsensusLookupCandidates_SourceThenMapped(t *testing.T) {
	got := consensusLookupCandidates("AXIBAN", "AXISBANK", "")
	want := []string{"AXIBAN", "AXISBANK"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}

func TestConsensusLookupCandidates_CachedMappedURL(t *testing.T) {
	url := "https://trendlyne.com/research-reports/stock/140/AXISBANK/axis-bank-ltd/"
	got := consensusLookupCandidates("AXIBAN", "AXISBANK", url)
	want := []string{"AXISBANK"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}

	// Cached URL for source symbol still tries source first, then mapped.
	sourceURL := "https://trendlyne.com/research-reports/stock/1/AXIBAN/axiban-ltd/"
	got = consensusLookupCandidates("AXIBAN", "AXISBANK", sourceURL)
	want = []string{"AXIBAN", "AXISBANK"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("source-owned URL: got %v want %v", got, want)
	}
}

func TestShouldRetryConsensusWithMappedSymbol(t *testing.T) {
	cases := []struct {
		err  error
		want bool
	}{
		{nil, false},
		{fmt.Errorf("URL_NOT_FOUND: no Trendlyne research-reports URL for AXIBAN"), true},
		{fmt.Errorf("PARSE_FAIL: no consensus or report data row found (url=...)"), true},
		{fmt.Errorf("FETCH_FAIL: http 503 for ..."), false},
		{errors.New("network timeout"), false},
	}
	for _, tc := range cases {
		got := shouldRetryConsensusWithMappedSymbol(tc.err)
		if got != tc.want {
			t.Fatalf("err=%v got=%v want=%v", tc.err, got, tc.want)
		}
	}
}

func TestPageURLForConsensusLookup(t *testing.T) {
	url := "https://trendlyne.com/research-reports/stock/140/AXISBANK/axis-bank-ltd/"
	if got := pageURLForConsensusLookup("AXISBANK", url); got != url {
		t.Fatalf("matching symbol: got %q", got)
	}
	if got := pageURLForConsensusLookup("AXIBAN", url); got != "" {
		t.Fatalf("mismatched symbol should clear URL, got %q", got)
	}
	if got := pageURLForConsensusLookup("AXISBANK", ""); got != "" {
		t.Fatalf("empty URL: got %q", got)
	}
}
