package jobs

import (
	"testing"
	"time"
)

func TestNextWeekday1230IST(t *testing.T) {
	ist := time.FixedZone("IST", 5*60*60+30*60)

	// Monday 10:00 -> same Monday 12:30
	mon := time.Date(2026, 3, 2, 10, 0, 0, 0, ist)
	next := nextWeekday1230IST(mon, ist)
	want := time.Date(2026, 3, 2, 12, 30, 0, 0, ist)
	if !next.Equal(want) {
		t.Fatalf("got %v want %v", next, want)
	}

	// Monday 13:00 -> Tuesday 12:30
	monAfternoon := time.Date(2026, 3, 2, 13, 0, 0, 0, ist)
	next = nextWeekday1230IST(monAfternoon, ist)
	want = time.Date(2026, 3, 3, 12, 30, 0, 0, ist)
	if !next.Equal(want) {
		t.Fatalf("got %v want %v", next, want)
	}

	// Friday 13:00 -> Monday 12:30 (skip weekend)
	fri := time.Date(2026, 3, 6, 13, 0, 0, 0, ist)
	next = nextWeekday1230IST(fri, ist)
	want = time.Date(2026, 3, 9, 12, 30, 0, 0, ist)
	if !next.Equal(want) {
		t.Fatalf("got %v want %v", next, want)
	}

	// Saturday 10:00 -> Monday 12:30
	sat := time.Date(2026, 3, 7, 10, 0, 0, 0, ist)
	next = nextWeekday1230IST(sat, ist)
	want = time.Date(2026, 3, 9, 12, 30, 0, 0, ist)
	if !next.Equal(want) {
		t.Fatalf("got %v want %v", next, want)
	}
}
