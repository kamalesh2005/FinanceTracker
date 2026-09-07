package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"financetracker/models"
	"financetracker/recrules"
	"financetracker/trendrules"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func trendReclassifyTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("db: %v", err)
	}
	sqlDB.SetMaxOpenConns(1)
	if err := db.AutoMigrate(&models.Stock{}, &models.AppConfig{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if err := EnsureAppConfig(db); err != nil {
		t.Fatalf("seed app config: %v", err)
	}
	return db
}

func trendReclassifyRouter(h *Handler) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.PUT("/admin/config", h.PutAdminConfig)
	return r
}

func putAdminConfig(t *testing.T, r http.Handler, body any) map[string]any {
	t.Helper()
	b, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	req := httptest.NewRequest(http.MethodPut, "/admin/config", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("PUT /admin/config status=%d body=%s", w.Code, w.Body.String())
	}
	var out map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return out
}

func loadStockBySymbol(t *testing.T, db *gorm.DB, symbol string) models.Stock {
	t.Helper()
	var s models.Stock
	if err := db.Where("symbol = ?", symbol).First(&s).Error; err != nil {
		t.Fatalf("load %s: %v", symbol, err)
	}
	return s
}

func jsonInt(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	default:
		return -1
	}
}

func bullishMAFields() models.Stock {
	fetched := time.Date(2026, 9, 4, 6, 0, 0, 0, time.UTC)
	return models.Stock{
		CurrentPrice:         120,
		MA7:                  110,
		MA20:                 100,
		MA50:                 90,
		AdjustedSTDelta:      5,
		AdjustedMTDelta:      2,
		Trend:                "neutral",
		LastTrendFetchedDate: &fetched,
	}
}

func TestPutAdminConfigReclassifiesPullDataYTrends(t *testing.T) {
	db := trendReclassifyTestDB(t)
	h := NewHandler(db)
	r := trendReclassifyRouter(h)

	held := bullishMAFields()
	held.Symbol = "HELD"
	held.Name = "Held"
	held.PullData = models.PullDataYes
	if err := db.Create(&held).Error; err != nil {
		t.Fatal(err)
	}

	catalog := bullishMAFields()
	catalog.Symbol = "SKIPN"
	catalog.Name = "Not pulled"
	catalog.PullData = models.PullDataNo
	if err := db.Create(&catalog).Error; err != nil {
		t.Fatal(err)
	}

	incomplete := models.Stock{
		Symbol:               "NOMA",
		Name:                 "No MAs",
		PullData:             models.PullDataYes,
		Trend:                "bearish_st",
		CurrentPrice:         50,
		LastTrendFetchedDate: held.LastTrendFetchedDate,
	}
	if err := db.Create(&incomplete).Error; err != nil {
		t.Fatal(err)
	}

	out := putAdminConfig(t, r, gin.H{"trend_rules": trendrules.DefaultRuleset().ToMap()})
	if jsonInt(out["trends_reclassified"]) != 1 {
		t.Fatalf("trends_reclassified=%v want 1", out["trends_reclassified"])
	}
	if jsonInt(out["trends_skipped"]) != 1 {
		t.Fatalf("trends_skipped=%v want 1", out["trends_skipped"])
	}

	gotHeld := loadStockBySymbol(t, db, "HELD")
	if gotHeld.Trend != trendrules.TrendBullish {
		t.Fatalf("HELD trend=%q want %q", gotHeld.Trend, trendrules.TrendBullish)
	}
	if gotHeld.MA7 != 110 || gotHeld.MA20 != 100 || gotHeld.CurrentPrice != 120 {
		t.Fatalf("HELD MAs/price rewritten: ma7=%.1f ma20=%.1f price=%.1f", gotHeld.MA7, gotHeld.MA20, gotHeld.CurrentPrice)
	}
	if gotHeld.LastTrendFetchedDate == nil || !gotHeld.LastTrendFetchedDate.Equal(*held.LastTrendFetchedDate) {
		t.Fatalf("HELD last_trend_fetched_date changed")
	}

	gotN := loadStockBySymbol(t, db, "SKIPN")
	if gotN.Trend != "neutral" {
		t.Fatalf("pull_data=N trend=%q want unchanged neutral", gotN.Trend)
	}

	gotInc := loadStockBySymbol(t, db, "NOMA")
	if gotInc.Trend != "bearish_st" {
		t.Fatalf("missing-MA trend=%q want unchanged bearish_st", gotInc.Trend)
	}
}

func TestPutAdminConfigSignalRulesDoNotReclassifyTrends(t *testing.T) {
	db := trendReclassifyTestDB(t)
	h := NewHandler(db)
	r := trendReclassifyRouter(h)

	held := bullishMAFields()
	held.Symbol = "HELD"
	held.Name = "Held"
	held.PullData = models.PullDataYes
	if err := db.Create(&held).Error; err != nil {
		t.Fatal(err)
	}

	out := putAdminConfig(t, r, gin.H{"recommendation_rules": recrules.DefaultRuleset(5).ToMap()})
	if _, ok := out["trends_reclassified"]; ok {
		t.Fatalf("signal-only save should not reclassify, got %v", out["trends_reclassified"])
	}

	got := loadStockBySymbol(t, db, "HELD")
	if got.Trend != "neutral" {
		t.Fatalf("trend=%q want unchanged neutral", got.Trend)
	}
}
