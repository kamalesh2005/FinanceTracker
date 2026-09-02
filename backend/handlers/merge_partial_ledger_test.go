package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
)

func TestMergePartialTradeLedgerDateRangePreservesOutside(t *testing.T) {
	db := fifoTestDB(t)
	if err := db.Create(&models.Stock{ID: 1, Symbol: "BEL", Name: "BHARAT ELECTRONICS LTD"}).Error; err != nil {
		t.Fatalf("stock: %v", err)
	}
	src := models.SourceZerodha
	outside := fifoDate(2023, 1, 1)
	insertBuy(t, db, 1, 1, src, 10, 100, outside)
	if err := db.Create(&models.UserStock{
		UserID: 1, StockID: 1, Source: src, Quantity: 10, AvgBuyPrice: 100,
	}).Error; err != nil {
		t.Fatalf("pos: %v", err)
	}
	// Undated pad that should be deleted on merge.
	if err := db.Create(&models.UserStockTransaction{
		UserID: 1, StockID: 1, Source: src, Type: models.TransactionTypeBuy,
		Quantity: 2, OriginalQuantity: 2, Price: 50, TransactionDate: nil,
	}).Error; err != nil {
		t.Fatalf("undated: %v", err)
	}

	items := []resolvedPartialItem{
		{StockID: 1, Action: "buy", Quantity: 5, Price: 200, TransactionDate: fifoDate(2024, 6, 1)},
		{StockID: 1, Action: "sell", Quantity: 2, Price: 250, TransactionDate: fifoDate(2024, 7, 1)},
	}
	if err := mergePartialTradeLedger(db, 1, src, items); err != nil {
		t.Fatalf("merge: %v", err)
	}

	var lots []models.UserStockTransaction
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", 1, 1, src).
		Order("id ASC").Find(&lots).Error; err != nil {
		t.Fatalf("list: %v", err)
	}
	hasOutside := false
	hasUndated := false
	for _, lot := range lots {
		if lot.TransactionDate != nil && lot.TransactionDate.Equal(outside) {
			hasOutside = true
		}
		if lot.TransactionDate == nil {
			hasUndated = true
		}
	}
	if !hasOutside {
		t.Fatalf("outside-range buy should survive: %+v", lots)
	}
	// Position was 10; total txn after merge = 10+5-2 = 13 > 10 → qty becomes 13, no undated pad.
	if hasUndated {
		t.Fatalf("unexpected undated after qty bump: %+v", lots)
	}

	var pos models.UserStock
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", 1, 1, src).First(&pos).Error; err != nil {
		t.Fatalf("pos: %v", err)
	}
	if pos.Quantity < 12.9 || pos.Quantity > 13.1 {
		t.Fatalf("qty=%v want 13", pos.Quantity)
	}
}

func TestMergePartialTradeLedgerUndatedPadAndAvgSolve(t *testing.T) {
	db := fifoTestDB(t)
	if err := db.Create(&models.Stock{ID: 1, Symbol: "TCS", Name: "TATA CONSULTANCY"}).Error; err != nil {
		t.Fatalf("stock: %v", err)
	}
	src := models.SourceManualBulkUpload
	if err := db.Create(&models.UserStock{
		UserID: 1, StockID: 1, Source: src, Quantity: 20, AvgBuyPrice: 100,
	}).Error; err != nil {
		t.Fatalf("pos: %v", err)
	}

	items := []resolvedPartialItem{
		{StockID: 1, Action: "buy", Quantity: 10, Price: 120, TransactionDate: fifoDate(2024, 1, 1)},
	}
	if err := mergePartialTradeLedger(db, 1, src, items); err != nil {
		t.Fatalf("merge: %v", err)
	}

	var pos models.UserStock
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", 1, 1, src).First(&pos).Error; err != nil {
		t.Fatalf("pos: %v", err)
	}
	if pos.Quantity < 19.9 || pos.Quantity > 20.1 {
		t.Fatalf("qty=%v want 20", pos.Quantity)
	}
	if pos.AvgBuyPrice < 99.9 || pos.AvgBuyPrice > 100.1 {
		t.Fatalf("avg=%v want 100 (preserved)", pos.AvgBuyPrice)
	}

	buys := loadBuys(t, db, 1, 1, src)
	var undated *models.UserStockTransaction
	for i := range buys {
		if buys[i].TransactionDate == nil && buys[i].Quantity > 1e-9 {
			undated = &buys[i]
		}
	}
	if undated == nil {
		t.Fatalf("expected open undated pad: %+v", buys)
	}
	if undated.Quantity < 9.9 || undated.Quantity > 10.1 {
		t.Fatalf("undated qty=%v want 10", undated.Quantity)
	}
	// (120*10 + P*10)/20 = 100 → P = 80
	if undated.Price < 79.9 || undated.Price > 80.1 {
		t.Fatalf("undated price=%v want 80", undated.Price)
	}
}

func TestMergePartialTradeLedgerFIFOAndNoUndatedSetsAvg(t *testing.T) {
	db := fifoTestDB(t)
	if err := db.Create(&models.Stock{ID: 1, Symbol: "INFY", Name: "INFOSYS LIMITED"}).Error; err != nil {
		t.Fatalf("stock: %v", err)
	}
	src := models.SourceHDFCSec
	items := []resolvedPartialItem{
		{StockID: 1, Action: "buy", Quantity: 10, Price: 100, TransactionDate: fifoDate(2024, 1, 1)},
		{StockID: 1, Action: "sell", Quantity: 4, Price: 150, TransactionDate: fifoDate(2024, 2, 1)},
		{StockID: 1, Action: "buy", Quantity: 2, Price: 80, TransactionDate: fifoDate(2024, 3, 1)},
	}
	if err := mergePartialTradeLedger(db, 1, src, items); err != nil {
		t.Fatalf("merge: %v", err)
	}

	var pos models.UserStock
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", 1, 1, src).First(&pos).Error; err != nil {
		t.Fatalf("pos: %v", err)
	}
	// Open: 6@100 + 2@80 = 8, invested 600+160=760, avg=95
	if pos.Quantity < 7.9 || pos.Quantity > 8.1 {
		t.Fatalf("qty=%v want 8", pos.Quantity)
	}
	if pos.AvgBuyPrice < 94.9 || pos.AvgBuyPrice > 95.1 {
		t.Fatalf("avg=%v want 95", pos.AvgBuyPrice)
	}

	buys := loadBuys(t, db, 1, 1, src)
	sold := 0.0
	for _, b := range buys {
		if b.SaleDate != nil {
			sold += b.OriginalQuantity
			if b.SalePrice < 149.9 || b.SalePrice > 150.1 {
				t.Fatalf("sale price=%v", b.SalePrice)
			}
		}
	}
	if sold < 3.9 || sold > 4.1 {
		t.Fatalf("sold stamped qty=%v want 4", sold)
	}
}

func TestMergePartialTradeLedgerRestampsOutsideSells(t *testing.T) {
	db := fifoTestDB(t)
	if err := db.Create(&models.Stock{ID: 1, Symbol: "ACC", Name: "ACC LTD"}).Error; err != nil {
		t.Fatalf("stock: %v", err)
	}
	src := models.SourceZerodha
	oldBuy := insertBuy(t, db, 1, 1, src, 10, 50, fifoDate(2020, 1, 1))
	_ = oldBuy
	insertSell(t, db, 1, 1, src, 3, 70, fifoDate(2020, 6, 1))
	if err := applyFIFOSell(db, 1, 1, src, 3, 70, fifoDate(2020, 6, 1)); err != nil {
		t.Fatalf("seed fifo: %v", err)
	}
	if err := db.Create(&models.UserStock{
		UserID: 1, StockID: 1, Source: src, Quantity: 7, AvgBuyPrice: 50,
	}).Error; err != nil {
		t.Fatalf("pos: %v", err)
	}

	// New file only has a later buy; outside sell should be restamped after clear.
	items := []resolvedPartialItem{
		{StockID: 1, Action: "buy", Quantity: 1, Price: 60, TransactionDate: fifoDate(2024, 1, 1)},
	}
	if err := mergePartialTradeLedger(db, 1, src, items); err != nil {
		t.Fatalf("merge: %v", err)
	}

	buys := loadBuys(t, db, 1, 1, src)
	stamped := false
	for _, b := range buys {
		if b.SaleDate != nil && b.SalePrice > 69 {
			stamped = true
		}
	}
	if !stamped {
		t.Fatalf("expected outside sell restamped: %+v", buys)
	}
}

func TestNormalizeStockNameKey(t *testing.T) {
	a := normalizeStockNameKey("ADANI ENTERPRISES LTD")
	b := normalizeStockNameKey("Adani Enterprises Limited")
	if a == "" || a != b {
		t.Fatalf("keys %q vs %q", a, b)
	}
}

func TestFindStockByNormalizedName(t *testing.T) {
	db := fifoTestDB(t)
	if err := db.Create(&models.Stock{ID: 1, Symbol: "ADANIENT", Name: "ADANI ENTERPRISES LIMITED"}).Error; err != nil {
		t.Fatalf("stock: %v", err)
	}
	stock, ok, err := findStockByNormalizedName(db, "Adani Enterprises Ltd")
	if err != nil || !ok || stock.Symbol != "ADANIENT" {
		t.Fatalf("found=%v ok=%v err=%v stock=%+v", ok, ok, err, stock)
	}
	_, ok, err = findStockByNormalizedName(db, "UNKNOWN SCRIP")
	if err != nil || ok {
		t.Fatalf("want miss, ok=%v err=%v", ok, err)
	}
}

func TestMergeSourceLedgerHTTPUnmappedHDFC(t *testing.T) {
	db := fifoTestDB(t)
	if err := db.Create(&models.Stock{ID: 1, Symbol: "ARVINDFASH", Name: "ARVIND FASHIONS LIMITED"}).Error; err != nil {
		t.Fatalf("stock: %v", err)
	}
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set(middleware.ContextUserIDKey, uint(1))
		c.Next()
	})
	r.POST("/merge", h.MergeSourceLedger)

	body := map[string]interface{}{
		"source": models.SourceHDFCSec,
		"items": []map[string]interface{}{
			{
				"name": "ARVIND FASHIONS LIMITED", "action": "Buy", "quantity": 12, "price": 474.2,
				"transaction_date": fifoDate(2024, 7, 23).Format(time.RFC3339),
			},
			{
				"name": "TOTALLY UNKNOWN CO", "action": "Buy", "quantity": 1, "price": 10,
				"transaction_date": fifoDate(2024, 7, 23).Format(time.RFC3339),
			},
		},
	}
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/merge", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("json: %v", err)
	}
	unmapped, _ := resp["unmapped"].([]interface{})
	if len(unmapped) != 1 {
		t.Fatalf("unmapped=%v want 1", resp["unmapped"])
	}
	count, _ := resp["count"].(float64)
	if count != 1 {
		t.Fatalf("count=%v want 1", count)
	}
}
