package handlers

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
)

func TestRebuildICICIDirectLedgerReplaysFIFOAndFees(t *testing.T) {
	db := fifoTestDB(t)
	if err := db.Create(&models.Stock{ID: 1, Symbol: "ACC", Name: "ACC LIMITED"}).Error; err != nil {
		t.Fatalf("stock: %v", err)
	}
	oldDay := fifoDate(2018, 1, 1)
	if err := db.Create(&models.UserStock{
		UserID:      1,
		StockID:     1,
		Source:      models.SourceICICIDirect,
		Quantity:    10,
		AvgBuyPrice: 50,
	}).Error; err != nil {
		t.Fatalf("position: %v", err)
	}
	insertBuy(t, db, 1, 1, models.SourceICICIDirect, 10, 50, oldDay)

	items := []ledgerRebuildItem{
		{
			Symbol: "ACC", Action: "Buy", Quantity: 10, Price: 100,
			TransactionDate: fifoDate(2020, 1, 1),
			Brokerage:       5.5, TransactionCharges: 0.2, StampDuty: 1.1,
			Segment: "Rolling", STT: "STT Paid", Exchange: "NSE",
		},
		{
			Symbol: "ACC", Action: "Sell", Quantity: 4, Price: 150,
			TransactionDate: fifoDate(2021, 6, 1),
			Brokerage:       2.0, TransactionCharges: 0.1, StampDuty: 0,
			Segment: "TT", STT: "STT Paid", Exchange: "BSE",
		},
		{
			Symbol: "ACC", Action: "Buy", Quantity: 2, Price: 0,
			TransactionDate: fifoDate(2022, 1, 1),
			Segment:         "Rolling", STT: "STT Not Paid", Exchange: "NSE",
		},
	}
	if err := rebuildICICIDirectLedger(db, 1, items); err != nil {
		t.Fatalf("rebuild: %v", err)
	}

	var lots []models.UserStockTransaction
	if err := db.Where("user_id = ? AND source = ?", 1, models.SourceICICIDirect).
		Order("transaction_date ASC, id ASC").Find(&lots).Error; err != nil {
		t.Fatalf("list lots: %v", err)
	}
	if len(lots) < 3 {
		t.Fatalf("got %d ledger rows, want at least 3", len(lots))
	}
	for _, lot := range lots {
		if lot.TransactionDate != nil && lot.TransactionDate.Equal(oldDay) {
			t.Fatalf("old lot survived rebuild")
		}
	}

	var buyFees *models.UserStockTransaction
	var sellFees *models.UserStockTransaction
	var bonus *models.UserStockTransaction
	for i := range lots {
		switch {
		case lots[i].Type == models.TransactionTypeBuy && lots[i].Price == 100:
			buyFees = &lots[i]
		case lots[i].Type == models.TransactionTypeSell:
			sellFees = &lots[i]
		case lots[i].Type == models.TransactionTypeBuy && lots[i].Price == 0:
			bonus = &lots[i]
		}
	}
	if buyFees == nil || sellFees == nil || bonus == nil {
		t.Fatalf("missing expected lots buy=%v sell=%v bonus=%v", buyFees != nil, sellFees != nil, bonus != nil)
	}
	if buyFees.Brokerage != 5.5 || buyFees.TransactionCharges != 0.2 || buyFees.StampDuty != 1.1 {
		t.Fatalf("buy fees=%v/%v/%v", buyFees.Brokerage, buyFees.TransactionCharges, buyFees.StampDuty)
	}
	if buyFees.Segment != "Rolling" || buyFees.STT != "STT Paid" || buyFees.Exchange != "NSE" {
		t.Fatalf("buy extras segment=%q stt=%q exch=%q", buyFees.Segment, buyFees.STT, buyFees.Exchange)
	}
	if sellFees.Brokerage != 2.0 || sellFees.Exchange != "BSE" {
		t.Fatalf("sell extras brokerage=%v exch=%q", sellFees.Brokerage, sellFees.Exchange)
	}
	if buyFees.Origin != models.TxOriginICICITransactions {
		t.Fatalf("icici origin=%q want %q", buyFees.Origin, models.TxOriginICICITransactions)
	}

	var pos models.UserStock
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", 1, 1, models.SourceICICIDirect).
		First(&pos).Error; err != nil {
		t.Fatalf("position: %v", err)
	}
	// Remaining: 10 bought - 4 sold + 2 bonus = 8; invested is remaining 6 @ 100.
	if pos.Quantity < 8-1e-9 || pos.Quantity > 8+1e-9 {
		t.Fatalf("qty=%v want 8", pos.Quantity)
	}
	if pos.AvgBuyPrice < 75-1e-6 || pos.AvgBuyPrice > 75+1e-6 {
		t.Fatalf("avg=%v want 75 (600 invested / 8 qty)", pos.AvgBuyPrice)
	}
}

func TestRebuildICICIDirectLedgerRollsBackOnSellBeforeBuy(t *testing.T) {
	db := fifoTestDB(t)
	if err := db.Create(&models.Stock{ID: 1, Symbol: "ACC"}).Error; err != nil {
		t.Fatalf("stock: %v", err)
	}
	oldDay := fifoDate(2019, 3, 1)
	if err := db.Create(&models.UserStock{
		UserID: 1, StockID: 1, Source: models.SourceICICIDirect, Quantity: 5, AvgBuyPrice: 20,
	}).Error; err != nil {
		t.Fatalf("position: %v", err)
	}
	insertBuy(t, db, 1, 1, models.SourceICICIDirect, 5, 20, oldDay)

	err := rebuildICICIDirectLedger(db, 1, []ledgerRebuildItem{
		{
			Symbol: "ACC", Action: "Sell", Quantity: 2, Price: 30,
			TransactionDate: fifoDate(2020, 1, 1),
		},
		{
			Symbol: "ACC", Action: "Buy", Quantity: 10, Price: 25,
			TransactionDate: fifoDate(2021, 1, 1),
		},
	})
	if err == nil {
		t.Fatal("expected sell-before-buy to fail")
	}
	if !errors.Is(err, errInsufficientQuantity) {
		t.Fatalf("err=%v want insufficient quantity", err)
	}

	var pos models.UserStock
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", 1, 1, models.SourceICICIDirect).
		First(&pos).Error; err != nil {
		t.Fatalf("position: %v", err)
	}
	if pos.Quantity != 5 {
		t.Fatalf("qty after rollback=%v want 5", pos.Quantity)
	}
	var lots []models.UserStockTransaction
	if err := db.Where("user_id = ? AND source = ?", 1, models.SourceICICIDirect).Find(&lots).Error; err != nil {
		t.Fatalf("lots: %v", err)
	}
	if len(lots) != 1 || lots[0].Price != 20 {
		t.Fatalf("ledger after rollback=%+v", lots)
	}
}

func TestRebuildICICIDirectLedgerSameDayBuyBeforeSell(t *testing.T) {
	db := fifoTestDB(t)
	if err := db.Create(&models.Stock{ID: 1, Symbol: "ABB"}).Error; err != nil {
		t.Fatalf("stock: %v", err)
	}
	day := fifoDate(2022, time.March, 2)
	err := rebuildICICIDirectLedger(db, 1, []ledgerRebuildItem{
		{Symbol: "ABB", Action: "Sell", Quantity: 2, Price: 2200, TransactionDate: day},
		{Symbol: "ABB", Action: "Buy", Quantity: 2, Price: 2178, TransactionDate: day},
	})
	if err != nil {
		t.Fatalf("rebuild: %v", err)
	}
	var pos models.UserStock
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", 1, 1, models.SourceICICIDirect).
		First(&pos).Error; err != nil {
		t.Fatalf("position: %v", err)
	}
	if pos.Quantity > 1e-9 {
		t.Fatalf("qty=%v want 0 after same-day buy then sell", pos.Quantity)
	}
}

func TestFindOrCreateStockRecordCreatesWithoutYahoo(t *testing.T) {
	db := fifoTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	stock, err := h.findOrCreateStockRecord("newco", "NEW CO LTD", "INE123A01016")
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if stock.ID == 0 || stock.Symbol != "NEWCO" {
		t.Fatalf("stock=%+v", stock)
	}
	if stock.CurrentPrice != 0 || stock.SixthHighestPrice != 0 {
		t.Fatalf("yahoo fields filled without fetch: %+v", stock)
	}

	again, err := h.findOrCreateStockRecord("NEWCO", "NEW CO LTD", "INE123A01016")
	if err != nil {
		t.Fatalf("lookup: %v", err)
	}
	if again.ID != stock.ID {
		t.Fatalf("id=%d want %d", again.ID, stock.ID)
	}
}

func TestEnrichStockIfNeededSkippedInTests(t *testing.T) {
	db := fifoTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	stock := models.Stock{Symbol: "TCS", Name: "Tata Consultancy", CurrentPrice: 0, PullData: models.PullDataYes}
	if err := db.Create(&stock).Error; err != nil {
		t.Fatal(err)
	}
	h.enrichStockIfNeeded(&stock, models.SourceFormatManual)
	if stock.CurrentPrice != 0 || stock.SixthHighestPrice != 0 {
		t.Fatalf("yahoo fields filled despite skip: %+v", stock)
	}
	h.enrichCatalogSymbol("TCS", models.SourceFormatManual)
	var stored models.Stock
	if err := db.Where("symbol = ?", "TCS").First(&stored).Error; err != nil {
		t.Fatal(err)
	}
	if stored.PullData != models.PullDataYes {
		t.Fatalf("pull_data=%q", stored.PullData)
	}
}

func TestRebuildSourceLedgerCreatesMissingStocksWithoutYahoo(t *testing.T) {
	db := fifoTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/rebuild", func(c *gin.Context) {
		c.Set(middleware.ContextUserIDKey, uint(1))
		h.RebuildSourceLedger(c)
	})

	body, _ := json.Marshal(map[string]any{
		"source": models.SourceICICIDirect,
		"items": []map[string]any{
			{
				"symbol":           "NEWCO",
				"name":             "NEW CO LTD",
				"isin":             "INE123A01016",
				"action":           "Buy",
				"quantity":         10,
				"price":            100,
				"transaction_date": fifoDate(2022, 1, 1),
			},
		},
	})
	req := httptest.NewRequest(http.MethodPost, "/rebuild", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}

	var stock models.Stock
	if err := db.Where("symbol = ?", "NEWCO").First(&stock).Error; err != nil {
		t.Fatalf("stock: %v", err)
	}
	if stock.Name != "NEW CO LTD" {
		t.Fatalf("name=%q", stock.Name)
	}
	if stock.CurrentPrice != 0 {
		t.Fatalf("price=%v want 0 without yahoo", stock.CurrentPrice)
	}
	var pos models.UserStock
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", 1, stock.ID, models.SourceICICIDirect).
		First(&pos).Error; err != nil {
		t.Fatalf("position: %v", err)
	}
	if pos.Quantity < 10-1e-9 || pos.Quantity > 10+1e-9 {
		t.Fatalf("qty=%v want 10", pos.Quantity)
	}
}
