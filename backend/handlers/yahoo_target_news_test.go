package handlers

import (
	"testing"
	"time"
)

func TestNeedsAgeRefresh(t *testing.T) {
	now := time.Date(2026, 8, 30, 12, 0, 0, 0, time.UTC)
	minAge := 7 * 24 * time.Hour

	if !needsAgeRefresh(nil, now, minAge) {
		t.Fatal("nil last should need refresh")
	}
	if !needsAgeRefresh(nil, now, 0) {
		t.Fatal("zero minAge should always refresh")
	}

	fresh := now.Add(-2 * 24 * time.Hour)
	if needsAgeRefresh(&fresh, now, minAge) {
		t.Fatal("2d old should not need refresh with 7d minAge")
	}

	stale := now.Add(-8 * 24 * time.Hour)
	if !needsAgeRefresh(&stale, now, minAge) {
		t.Fatal("8d old should need refresh with 7d minAge")
	}

	always := now.Add(-1 * time.Hour)
	if !needsAgeRefresh(&always, now, 0) {
		t.Fatal("zero minAge should refresh even recent timestamp")
	}
}

func TestCatalogTargetNewsPolicy_UsesSevenDays(t *testing.T) {
	if catalogTargetNewsPolicy.minConsensusAge != catalogConsensusNewsMinAge {
		t.Fatalf("consensus age=%v want %v", catalogTargetNewsPolicy.minConsensusAge, catalogConsensusNewsMinAge)
	}
	if catalogTargetNewsPolicy.minNewsAge != catalogConsensusNewsMinAge {
		t.Fatalf("news age=%v want %v", catalogTargetNewsPolicy.minNewsAge, catalogConsensusNewsMinAge)
	}
	if catalogConsensusNewsMinAge != 7*24*time.Hour {
		t.Fatalf("catalogConsensusNewsMinAge=%v", catalogConsensusNewsMinAge)
	}
}
