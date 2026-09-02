package handlers

import (
	"fmt"
	"testing"
	"time"

	"financetracker/models"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func openCatalogCronTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	if err := db.AutoMigrate(&models.Stock{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func seedNonHeldEQStock(t *testing.T, db *gorm.DB, symbol string, refreshedAt *time.Time) {
	t.Helper()
	s := models.Stock{
		Symbol:                    symbol,
		Name:                      symbol + " Ltd",
		Series:                    "EQ",
		PullData:                  models.PullDataNo,
		LastCatalogYahooRefreshAt: refreshedAt,
	}
	if err := db.Create(&s).Error; err != nil {
		t.Fatalf("create %s: %v", symbol, err)
	}
}

func TestBuildNonHeldEQCatalogQueue_DailyCap250(t *testing.T) {
	db := openCatalogCronTestDB(t)
	now := time.Date(2026, 8, 30, 2, 0, 0, 0, time.UTC)

	for i := 0; i < 300; i++ {
		seedNonHeldEQStock(t, db, fmt.Sprintf("SYM%03d", i), nil)
	}

	queue, err := BuildNonHeldEQCatalogQueue(db, now)
	if err != nil {
		t.Fatalf("queue: %v", err)
	}
	if len(queue) != catalogDailyLimit {
		t.Fatalf("len(queue)=%d want %d", len(queue), catalogDailyLimit)
	}
}

func TestBuildNonHeldEQCatalogQueue_SkipsWhenDailyQuotaMet(t *testing.T) {
	db := openCatalogCronTestDB(t)
	now := time.Date(2026, 8, 30, 2, 0, 0, 0, time.UTC)
	today := time.Date(2026, 8, 30, 1, 0, 0, 0, time.UTC)

	for i := 0; i < catalogDailyLimit; i++ {
		seedNonHeldEQStock(t, db, fmt.Sprintf("DONE%03d", i), &today)
	}
	seedNonHeldEQStock(t, db, "WAIT001", nil)

	queue, err := BuildNonHeldEQCatalogQueue(db, now)
	if err != nil {
		t.Fatalf("queue: %v", err)
	}
	if len(queue) != 0 {
		t.Fatalf("len(queue)=%d want 0 when daily quota met", len(queue))
	}
}

func TestBuildNonHeldEQCatalogQueue_WeeklyGate(t *testing.T) {
	db := openCatalogCronTestDB(t)
	now := time.Date(2026, 8, 30, 2, 0, 0, 0, time.UTC)
	recent := now.Add(-3 * 24 * time.Hour)
	stale := now.Add(-8 * 24 * time.Hour)

	seedNonHeldEQStock(t, db, "RECENT", &recent)
	seedNonHeldEQStock(t, db, "STALE", &stale)

	queue, err := BuildNonHeldEQCatalogQueue(db, now)
	if err != nil {
		t.Fatalf("queue: %v", err)
	}
	if len(queue) != 1 {
		t.Fatalf("len(queue)=%d want 1", len(queue))
	}
	if queue[0].Symbol != "STALE" {
		t.Fatalf("symbol=%q want STALE", queue[0].Symbol)
	}
}

func TestBuildNonHeldEQCatalogQueue_NullsFirst(t *testing.T) {
	db := openCatalogCronTestDB(t)
	now := time.Date(2026, 8, 30, 2, 0, 0, 0, time.UTC)
	stale := now.Add(-8 * 24 * time.Hour)

	seedNonHeldEQStock(t, db, "OLD", &stale)
	seedNonHeldEQStock(t, db, "NEW", nil)

	queue, err := BuildNonHeldEQCatalogQueue(db, now)
	if err != nil {
		t.Fatalf("queue: %v", err)
	}
	if len(queue) != 2 {
		t.Fatalf("len(queue)=%d want 2", len(queue))
	}
	if queue[0].Symbol != "NEW" {
		t.Fatalf("first=%q want NEW (NULLS FIRST)", queue[0].Symbol)
	}
}

func TestBuildNonHeldEQCatalogQueue_ExcludesHeldAndNonEQ(t *testing.T) {
	db := openCatalogCronTestDB(t)
	now := time.Date(2026, 8, 30, 2, 0, 0, 0, time.UTC)

	if err := db.Create(&models.Stock{
		Symbol: "HELD", Name: "Held", Series: "EQ", PullData: models.PullDataYes,
	}).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.Stock{
		Symbol: "BE", Name: "BE series", Series: "BE", PullData: models.PullDataNo,
	}).Error; err != nil {
		t.Fatal(err)
	}
	seedNonHeldEQStock(t, db, "EQOK", nil)

	queue, err := BuildNonHeldEQCatalogQueue(db, now)
	if err != nil {
		t.Fatalf("queue: %v", err)
	}
	if len(queue) != 1 || queue[0].Symbol != "EQOK" {
		t.Fatalf("queue=%v want only EQOK", symbols(queue))
	}
}

func symbols(stocks []models.Stock) []string {
	out := make([]string, len(stocks))
	for i, s := range stocks {
		out[i] = s.Symbol
	}
	return out
}
