package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func screenerTestDB(t *testing.T) *gorm.DB {
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
	if err := db.AutoMigrate(&models.Stock{}, &models.UserWatchlist{}, &models.UserScreenerStockLabel{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func seedCatalogStock(t *testing.T, db *gorm.DB, s models.Stock) models.Stock {
	t.Helper()
	if s.Series == "" {
		s.Series = "EQ"
	}
	if s.PullData == "" {
		s.PullData = models.PullDataNo
	}
	if err := db.Create(&s).Error; err != nil {
		t.Fatalf("create stock %s: %v", s.Symbol, err)
	}
	return s
}

func screenerRouter(h *Handler, userID uint) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	withUser := func(handler gin.HandlerFunc) gin.HandlerFunc {
		return func(c *gin.Context) {
			c.Set(middleware.ContextUserIDKey, userID)
			handler(c)
		}
	}
	r.GET("/stocks/screener/options", withUser(h.GetScreenerOptions))
	r.GET("/stocks/screener", withUser(h.SearchScreener))
	r.POST("/stocks/screener/labels", withUser(h.AddScreenerLabel))
	r.DELETE("/stocks/screener/labels/:stock_id/:label", withUser(h.RemoveScreenerLabel))
	r.GET("/watchlist", withUser(h.GetWatchlist))
	r.POST("/watchlist", withUser(h.AddToWatchlist))
	r.DELETE("/watchlist/:stock_id", withUser(h.RemoveFromWatchlist))
	return r
}

func doJSON(r http.Handler, method, path string, body any) *httptest.ResponseRecorder {
	var reader *bytes.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		reader = bytes.NewReader(b)
	} else {
		reader = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, reader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestSearchScreener_PageSizeAndFilters(t *testing.T) {
	db := screenerTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}

	for i := 1; i <= 25; i++ {
		seedCatalogStock(t, db, models.Stock{
			Symbol:          fmt.Sprintf("EQ%02d", i),
			Name:            fmt.Sprintf("Equity %02d", i),
			Industry:        "IT Services",
			MarketCap:       "Large Cap",
			Trend:           "bullish",
			AdjustedSTDelta: float64(i),
			AdjustedMTDelta: 1.5,
			ConsensusTarget: 3000,
			ConsensusUpside: 10,
			ConsensusType:   "buy",
			CurrentPrice:    100,
		})
	}
	seedCatalogStock(t, db, models.Stock{
		Symbol:    "BOND1",
		Name:      "Not Equity",
		Series:    "GB",
		Industry:  "IT Services",
		Trend:     "bullish",
		MarketCap: "Large Cap",
	})
	seedCatalogStock(t, db, models.Stock{
		Symbol:          "INFY",
		Name:            "Infosys",
		Industry:        "IT Services",
		MarketCap:       "Large Cap",
		Trend:           "neutral",
		AdjustedSTDelta: 0.5,
		ConsensusType:   "hold",
	})
	seedCatalogStock(t, db, models.Stock{
		Symbol:          "TCS",
		Name:            "Tata Consultancy",
		Industry:        "IT Services",
		MarketCap:       "Large Cap",
		Trend:           "bullish",
		AdjustedSTDelta: 4.2,
		AdjustedMTDelta: 2.1,
		ConsensusTarget: 4000,
		ConsensusUpside: 20,
		ConsensusType:   "buy",
		CurrentPrice:    2280,
		MA7:             2270,
		MA20:            2250,
		MA50:            2200,
	})

	r := screenerRouter(h, 1)

	w := doJSON(r, http.MethodGet, "/stocks/screener", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	var page1 struct {
		Items    []screenerStockJSON `json:"items"`
		Total    int64               `json:"total"`
		Page     int                 `json:"page"`
		PageSize int                 `json:"page_size"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &page1); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if page1.PageSize != 20 {
		t.Fatalf("page_size=%d want 20", page1.PageSize)
	}
	if len(page1.Items) > 20 {
		t.Fatalf("got %d items, want at most 20", len(page1.Items))
	}
	if page1.Total != 27 { // 25 EQ## + INFY + TCS; BOND1 excluded
		t.Fatalf("total=%d want 27 (EQ series only)", page1.Total)
	}

	w = doJSON(r, http.MethodGet, "/stocks/screener?page=2", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("page2 status=%d body=%s", w.Code, w.Body.String())
	}
	var page2 struct {
		Items []screenerStockJSON `json:"items"`
		Total int64               `json:"total"`
		Page  int                 `json:"page"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &page2); err != nil {
		t.Fatalf("decode page2: %v", err)
	}
	if page2.Page != 2 {
		t.Fatalf("page=%d want 2", page2.Page)
	}
	if int64(len(page1.Items)+len(page2.Items)) != page2.Total {
		t.Fatalf("page items %d+%d != total %d", len(page1.Items), len(page2.Items), page2.Total)
	}

	w = doJSON(r, http.MethodGet, "/stocks/screener?industry=IT%20Services&trend=bullish&adj_st_min=24&consensus_type=buy", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("filter status=%d body=%s", w.Code, w.Body.String())
	}
	var filtered struct {
		Items []screenerStockJSON `json:"items"`
		Total int64               `json:"total"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &filtered); err != nil {
		t.Fatalf("decode filtered: %v", err)
	}
	if filtered.Total != 1 { // EQ25 adj ST=25 > 24; EQ24=24 excluded
		t.Fatalf("filtered total=%d want 1 body=%s", filtered.Total, w.Body.String())
	}
	if filtered.Items[0].Symbol != "EQ25" {
		t.Fatalf("unexpected item %+v", filtered.Items[0])
	}

	w = doJSON(r, http.MethodGet, "/stocks/screener?trend=bullish&trend=neutral&consensus_type=buy&consensus_type=hold", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("multi filter status=%d body=%s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &filtered); err != nil {
		t.Fatalf("decode multi: %v", err)
	}
	if filtered.Total != 27 { // all EQ rows are bullish+buy or INFY neutral+hold
		t.Fatalf("multi total=%d want 27 body=%s", filtered.Total, w.Body.String())
	}

	w = doJSON(r, http.MethodGet, "/stocks/screener?name_like=Tata%20Cons", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("name_like status=%d body=%s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &filtered); err != nil {
		t.Fatalf("decode name_like: %v", err)
	}
	if filtered.Total != 1 {
		t.Fatalf("name_like total=%d want 1 body=%s", filtered.Total, w.Body.String())
	}
	if filtered.Items[0].Symbol != "TCS" {
		t.Fatalf("name_like item %+v want TCS", filtered.Items[0])
	}
}

func TestScreenerOptions_DistinctValues(t *testing.T) {
	db := screenerTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	seedCatalogStock(t, db, models.Stock{Symbol: "A", Industry: "Banks", ConsensusType: "buy"})
	seedCatalogStock(t, db, models.Stock{Symbol: "B", Industry: "Banks", ConsensusType: "hold"})
	seedCatalogStock(t, db, models.Stock{Symbol: "C", Industry: "IT Services", ConsensusType: "buy"})
	seedCatalogStock(t, db, models.Stock{Symbol: "D"})

	r := screenerRouter(h, 1)
	w := doJSON(r, http.MethodGet, "/stocks/screener/options", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	var opts struct {
		Industries     []string `json:"industries"`
		ConsensusTypes []string `json:"consensus_types"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &opts); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(opts.Industries) != 2 {
		t.Fatalf("industries=%v want 2", opts.Industries)
	}
	if len(opts.ConsensusTypes) != 2 {
		t.Fatalf("consensus_types=%v want 2", opts.ConsensusTypes)
	}
}

func TestWatchlist_AddUniquePullDataAndScope(t *testing.T) {
	db := screenerTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	tcs := seedCatalogStock(t, db, models.Stock{
		Symbol:   "TCS",
		Name:     "Tata Consultancy",
		PullData: models.PullDataNo,
	})
	infy := seedCatalogStock(t, db, models.Stock{Symbol: "INFY", Name: "Infosys"})

	user1 := screenerRouter(h, 1)
	user2 := screenerRouter(h, 2)

	w := doJSON(user1, http.MethodPost, "/watchlist", gin.H{"stock_id": tcs.ID})
	if w.Code != http.StatusCreated {
		t.Fatalf("add status=%d body=%s", w.Code, w.Body.String())
	}
	w = doJSON(user1, http.MethodPost, "/watchlist", gin.H{"stock_id": tcs.ID})
	if w.Code != http.StatusCreated {
		t.Fatalf("duplicate add status=%d body=%s", w.Code, w.Body.String())
	}
	var count int64
	if err := db.Model(&models.UserWatchlist{}).Where("user_id = ? AND stock_id = ?", 1, tcs.ID).Count(&count).Error; err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 1 {
		t.Fatalf("watchlist rows=%d want 1", count)
	}

	var stored models.Stock
	if err := db.First(&stored, tcs.ID).Error; err != nil {
		t.Fatalf("reload stock: %v", err)
	}
	if stored.PullData != models.PullDataYes {
		t.Fatalf("pull_data=%q want Y", stored.PullData)
	}

	doJSON(user1, http.MethodPost, "/watchlist", gin.H{"stock_id": infy.ID})
	doJSON(user2, http.MethodPost, "/watchlist", gin.H{"stock_id": tcs.ID})

	w = doJSON(user1, http.MethodGet, "/watchlist", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list status=%d body=%s", w.Code, w.Body.String())
	}
	var items []screenerStockJSON
	if err := json.Unmarshal(w.Body.Bytes(), &items); err != nil {
		t.Fatalf("decode list: %v", err)
	}
	if len(items) != 2 {
		t.Fatalf("user1 watchlist len=%d want 2", len(items))
	}

	w = doJSON(user2, http.MethodGet, "/watchlist", nil)
	if err := json.Unmarshal(w.Body.Bytes(), &items); err != nil {
		t.Fatalf("decode user2: %v", err)
	}
	if len(items) != 1 || items[0].Symbol != "TCS" {
		t.Fatalf("user2 watchlist=%v want [TCS]", items)
	}

	w = doJSON(user1, http.MethodGet, fmt.Sprintf("/stocks/screener"), nil)
	var page struct {
		Items []screenerStockJSON `json:"items"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &page); err != nil {
		t.Fatalf("decode screener: %v", err)
	}
	foundTCS := false
	for _, item := range page.Items {
		if item.Symbol == "TCS" {
			foundTCS = true
			if !item.InWatchlist {
				t.Fatalf("TCS in_watchlist=false for user 1")
			}
		}
		if item.Symbol == "INFY" && !item.InWatchlist {
			t.Fatalf("INFY in_watchlist=false for user 1")
		}
	}
	if !foundTCS {
		t.Fatalf("TCS missing from screener results")
	}

	w = doJSON(user1, http.MethodDelete, fmt.Sprintf("/watchlist/%d", tcs.ID), nil)
	if w.Code != http.StatusNoContent {
		t.Fatalf("delete status=%d body=%s", w.Code, w.Body.String())
	}
	if err := db.First(&stored, tcs.ID).Error; err != nil {
		t.Fatalf("reload after delete: %v", err)
	}
	if stored.PullData != models.PullDataYes {
		t.Fatalf("pull_data flipped to %q after remove", stored.PullData)
	}

	w = doJSON(user1, http.MethodGet, "/watchlist", nil)
	if err := json.Unmarshal(w.Body.Bytes(), &items); err != nil {
		t.Fatalf("decode after delete: %v", err)
	}
	if len(items) != 1 || items[0].Symbol != "INFY" {
		t.Fatalf("after delete got %v want [INFY]", items)
	}

	w = doJSON(user2, http.MethodGet, "/watchlist", nil)
	if err := json.Unmarshal(w.Body.Bytes(), &items); err != nil {
		t.Fatalf("decode user2 after user1 delete: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("user2 lost watchlist row")
	}
}

func TestAddToWatchlist_UnknownStock(t *testing.T) {
	db := screenerTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	r := screenerRouter(h, 1)
	w := doJSON(r, http.MethodPost, "/watchlist", gin.H{"stock_id": 999})
	if w.Code != http.StatusNotFound {
		t.Fatalf("status=%d want 404 body=%s", w.Code, w.Body.String())
	}
}

func TestScreenerLabels_AddRemoveAndOptions(t *testing.T) {
	db := screenerTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	stock := seedCatalogStock(t, db, models.Stock{Symbol: "TCS", Name: "Tata Consultancy"})
	r := screenerRouter(h, 1)

	w := doJSON(r, http.MethodPost, "/stocks/screener/labels", gin.H{
		"stock_id": stock.ID,
		"label":    "Track",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("add label status=%d body=%s", w.Code, w.Body.String())
	}
	var labeled screenerStockJSON
	if err := json.Unmarshal(w.Body.Bytes(), &labeled); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(labeled.Labels) != 1 || labeled.Labels[0] != "Track" {
		t.Fatalf("labels=%v want [Track]", labeled.Labels)
	}

	w = doJSON(r, http.MethodPost, "/stocks/screener/labels", gin.H{
		"stock_id": stock.ID,
		"label":    "Track",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("duplicate add status=%d body=%s", w.Code, w.Body.String())
	}

	w = doJSON(r, http.MethodGet, "/stocks/screener/options", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("options status=%d body=%s", w.Code, w.Body.String())
	}
	var opts struct {
		Labels []string `json:"labels"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &opts); err != nil {
		t.Fatalf("decode options: %v", err)
	}
	wantDefaults := len(models.DefaultScreenerLabels)
	if len(opts.Labels) < wantDefaults {
		t.Fatalf("labels=%v want at least %d defaults", opts.Labels, wantDefaults)
	}

	w = doJSON(r, http.MethodDelete, fmt.Sprintf("/stocks/screener/labels/%d/%s", stock.ID, "Track"), nil)
	if w.Code != http.StatusNoContent {
		t.Fatalf("remove status=%d body=%s", w.Code, w.Body.String())
	}

	w = doJSON(r, http.MethodDelete, fmt.Sprintf("/stocks/screener/labels/%d/%s", stock.ID, "Track"), nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("remove missing status=%d want 404 body=%s", w.Code, w.Body.String())
	}
}

func TestSearchScreener_LabelFilter(t *testing.T) {
	db := screenerTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	_ = seedCatalogStock(t, db, models.Stock{Symbol: "AAA", Name: "Unlabeled"})
	tracked := seedCatalogStock(t, db, models.Stock{Symbol: "BBB", Name: "Tracked"})
	hidden := seedCatalogStock(t, db, models.Stock{Symbol: "CCC", Name: "Hidden"})
	ignored := seedCatalogStock(t, db, models.Stock{Symbol: "DDD", Name: "Ignored"})

	for _, row := range []struct {
		stock models.Stock
		label string
	}{
		{tracked, "Track"},
		{hidden, "Hide"},
		{ignored, "Ignore"},
	} {
		if err := db.Create(&models.UserScreenerStockLabel{
			UserID:  1,
			StockID: row.stock.ID,
			Label:   row.label,
		}).Error; err != nil {
			t.Fatalf("seed label %s: %v", row.label, err)
		}
	}

	r := screenerRouter(h, 1)

	w := doJSON(r, http.MethodGet, "/stocks/screener?label=Track&label="+models.ScreenerLabelUnlabeled, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("default-like filter status=%d body=%s", w.Code, w.Body.String())
	}
	var page struct {
		Items []screenerStockJSON `json:"items"`
		Total int64               `json:"total"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &page); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if page.Total != 2 {
		t.Fatalf("total=%d want 2 (unlabeled + Track) body=%s", page.Total, w.Body.String())
	}
	symbols := map[string]bool{}
	for _, item := range page.Items {
		symbols[item.Symbol] = true
	}
	if !symbols["AAA"] || !symbols["BBB"] {
		t.Fatalf("items=%v want AAA and BBB", symbols)
	}
	if symbols["CCC"] || symbols["DDD"] {
		t.Fatalf("Hide/Ignore leaked into results: %v", symbols)
	}

	w = doJSON(r, http.MethodGet, "/stocks/screener?label=Track", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("track-only status=%d body=%s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &page); err != nil {
		t.Fatalf("decode track-only: %v", err)
	}
	if page.Total != 1 || page.Items[0].Symbol != "BBB" {
		t.Fatalf("track-only=%v want [BBB]", page.Items)
	}

	w = doJSON(r, http.MethodGet, "/stocks/screener?label="+models.ScreenerLabelUnlabeled, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("unlabeled-only status=%d body=%s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &page); err != nil {
		t.Fatalf("decode unlabeled-only: %v", err)
	}
	if page.Total != 1 || page.Items[0].Symbol != "AAA" {
		t.Fatalf("unlabeled-only=%v want [AAA]", page.Items)
	}
}
