package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func clearReviewTestDB(t *testing.T) *gorm.DB {
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
	if err := db.AutoMigrate(&models.Stock{}, &models.UserStock{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func seedHolding(t *testing.T, db *gorm.DB, userID uint, symbol string, buyDay time.Time) (models.Stock, models.UserStock) {
	t.Helper()
	stock := models.Stock{Symbol: symbol, Name: symbol, CurrentPrice: 1500}
	if err := db.Create(&stock).Error; err != nil {
		t.Fatalf("create stock: %v", err)
	}
	pos := models.UserStock{
		UserID:                userID,
		StockID:               stock.ID,
		Source:                models.SourceManualAdd,
		Quantity:              10,
		AvgBuyPrice:           1400,
		LastBuyPrice:          1410,
		LastBuyDate:           &buyDay,
		LastSalePrice:         1550,
		LastSaleDate:          &buyDay,
		LastHoldPrice:         1480,
		LastHoldDate:          &buyDay,
		SetBuyPrice:           1300,
		SetProfitBookingPrice: 1600,
		SetStopLossPrice:      1200,
	}
	if err := db.Create(&pos).Error; err != nil {
		t.Fatalf("create holding: %v", err)
	}
	return stock, pos
}

func postClearReview(h *Handler, userID uint, path string, body any) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/stocks/clear-review-values", func(c *gin.Context) {
		c.Set(middleware.ContextUserIDKey, userID)
		h.ClearAllStockReviewValues(c)
	})
	r.POST("/stocks/:id/clear-review-values", func(c *gin.Context) {
		c.Set(middleware.ContextUserIDKey, userID)
		h.ClearStockReviewValues(c)
	})
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func reloadPos(t *testing.T, db *gorm.DB, id uint) models.UserStock {
	t.Helper()
	var pos models.UserStock
	if err := db.First(&pos, id).Error; err != nil {
		t.Fatalf("reload: %v", err)
	}
	return pos
}

func TestClearStockReviewValues_ThresholdOnly(t *testing.T) {
	db := clearReviewTestDB(t)
	h := &Handler{DB: db}
	day := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	stock, pos := seedHolding(t, db, 1, "INFY", day)

	w := postClearReview(h, 1, fmt.Sprintf("/stocks/%d/clear-review-values", stock.ID), map[string]any{
		"source": models.SourceManualAdd,
		"fields": []string{"set_buy_price"},
	})
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	got := reloadPos(t, db, pos.ID)
	if got.SetBuyPrice != 0 {
		t.Fatalf("set_buy_price=%v want 0", got.SetBuyPrice)
	}
	if got.SetProfitBookingPrice != 1600 || got.SetStopLossPrice != 1200 {
		t.Fatalf("other thresholds changed: profit=%v stop=%v", got.SetProfitBookingPrice, got.SetStopLossPrice)
	}
	if got.BSHClearDate != nil {
		t.Fatalf("bsh_clear_date should be nil, got %v", got.BSHClearDate)
	}
	if got.LastBuyPrice != 1410 {
		t.Fatalf("last_buy_price changed: %v", got.LastBuyPrice)
	}
}

func TestClearStockReviewValues_LastBuySetsClearDate(t *testing.T) {
	db := clearReviewTestDB(t)
	h := &Handler{DB: db}
	day := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	stock, pos := seedHolding(t, db, 1, "TCS", day)

	w := postClearReview(h, 1, fmt.Sprintf("/stocks/%d/clear-review-values", stock.ID), map[string]any{
		"source": models.SourceManualAdd,
		"fields": []string{"last_buy"},
	})
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	got := reloadPos(t, db, pos.ID)
	if got.BSHClearDate == nil {
		t.Fatal("expected bsh_clear_date")
	}
	if got.LastBuyPrice != 1410 || got.LastSalePrice != 1550 || got.LastHoldPrice != 1480 {
		t.Fatalf("last action prices were wiped: buy=%v sale=%v hold=%v", got.LastBuyPrice, got.LastSalePrice, got.LastHoldPrice)
	}
	if got.SetBuyPrice != 1300 {
		t.Fatalf("threshold should be unchanged, got %v", got.SetBuyPrice)
	}
}

func TestClearStockReviewValues_All(t *testing.T) {
	db := clearReviewTestDB(t)
	h := &Handler{DB: db}
	day := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	stock, pos := seedHolding(t, db, 1, "HDFCBANK", day)

	w := postClearReview(h, 1, fmt.Sprintf("/stocks/%d/clear-review-values", stock.ID), map[string]any{
		"source": models.SourceManualAdd,
		"fields": []string{"all"},
	})
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	got := reloadPos(t, db, pos.ID)
	if got.SetBuyPrice != 0 || got.SetProfitBookingPrice != 0 || got.SetStopLossPrice != 0 {
		t.Fatalf("thresholds not cleared: %+v", got)
	}
	if got.BSHClearDate == nil {
		t.Fatal("expected bsh_clear_date")
	}
	if got.LastBuyPrice != 1410 {
		t.Fatalf("last_buy_price wiped: %v", got.LastBuyPrice)
	}
}

func TestClearStockReviewValues_UnknownField(t *testing.T) {
	db := clearReviewTestDB(t)
	h := &Handler{DB: db}
	day := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	stock, _ := seedHolding(t, db, 1, "WIPRO", day)

	w := postClearReview(h, 1, fmt.Sprintf("/stocks/%d/clear-review-values", stock.ID), map[string]any{
		"source": models.SourceManualAdd,
		"fields": []string{"nope"},
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestClearAllStockReviewValues_OnlyCurrentUser(t *testing.T) {
	db := clearReviewTestDB(t)
	h := &Handler{DB: db}
	day := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	_, mine := seedHolding(t, db, 1, "RELIANCE", day)
	_, other := seedHolding(t, db, 2, "SBIN", day)

	w := postClearReview(h, 1, "/stocks/clear-review-values", map[string]any{})
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	gotMine := reloadPos(t, db, mine.ID)
	if gotMine.SetBuyPrice != 0 || gotMine.BSHClearDate == nil {
		t.Fatalf("current user not cleared: buy=%v date=%v", gotMine.SetBuyPrice, gotMine.BSHClearDate)
	}
	gotOther := reloadPos(t, db, other.ID)
	if gotOther.SetBuyPrice != 1300 || gotOther.BSHClearDate != nil {
		t.Fatalf("other user was cleared: buy=%v date=%v", gotOther.SetBuyPrice, gotOther.BSHClearDate)
	}
	if gotMine.LastBuyPrice != 1410 {
		t.Fatalf("last_buy_price wiped: %v", gotMine.LastBuyPrice)
	}
}
