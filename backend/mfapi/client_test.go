package mfapi

import (
	"testing"
)

func TestPickFiscalYearEnds(t *testing.T) {
	points := []navPoint{
		// FY24 ends 31 Mar 2025
		{Date: "28-03-2025", NAV: "100.0"},
		{Date: "31-03-2025", NAV: "101.5"},
		{Date: "02-04-2025", NAV: "102.0"}, // start of FY25
		// FY25 ends 31 Mar 2026
		{Date: "28-03-2026", NAV: "110.0"},
		{Date: "01-04-2026", NAV: "111.0"}, // start of FY26 — must not win FY25
		// FY23 ends 31 Mar 2024
		{Date: "15-06-2023", NAV: "90.0"},
		{Date: "29-03-2024", NAV: "95.0"},
	}
	got := pickFiscalYearEnds(points, []int{2023, 2024, 2025})
	if got[2023] != 95.0 {
		t.Fatalf("FY23: got %v want 95", got[2023])
	}
	if got[2024] != 101.5 {
		t.Fatalf("FY24: got %v want 101.5", got[2024])
	}
	if got[2025] != 110.0 {
		t.Fatalf("FY25: got %v want 110", got[2025])
	}
	if _, ok := got[2022]; ok {
		t.Fatalf("unexpected FY22")
	}
}
