package dailyclose

import (
	"testing"
	"time"
)

func TestPickFiscalYearEndsFromBars(t *testing.T) {
	bars := []DayBar{
		{Date: time.Date(2025, 3, 28, 0, 0, 0, 0, time.UTC), Close: 100},
		{Date: time.Date(2025, 3, 31, 0, 0, 0, 0, time.UTC), Close: 101.5},
		{Date: time.Date(2025, 4, 2, 0, 0, 0, 0, time.UTC), Close: 102},
		{Date: time.Date(2026, 3, 28, 0, 0, 0, 0, time.UTC), Close: 110},
		{Date: time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC), Close: 111},
		{Date: time.Date(2023, 6, 15, 0, 0, 0, 0, time.UTC), Close: 90},
		{Date: time.Date(2024, 3, 29, 0, 0, 0, 0, time.UTC), Close: 95},
	}
	got := pickFiscalYearEndsFromBars(bars, []int{2023, 2024, 2025})
	if got[2023] != 95 {
		t.Fatalf("FY23: got %v want 95", got[2023])
	}
	if got[2024] != 101.5 {
		t.Fatalf("FY24: got %v want 101.5", got[2024])
	}
	if got[2025] != 110 {
		t.Fatalf("FY25: got %v want 110", got[2025])
	}
}
