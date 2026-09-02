package handlers

import "testing"

func TestPctReturn(t *testing.T) {
	if pctReturn(0, 10) != nil {
		t.Fatal("expected nil for zero start")
	}
	got := pctReturn(100, 110)
	if got == nil || *got != 10 {
		t.Fatalf("got %v want 10", got)
	}
	got = pctReturn(100, 90)
	if got == nil || *got != -10 {
		t.Fatalf("got %v want -10", got)
	}
}
