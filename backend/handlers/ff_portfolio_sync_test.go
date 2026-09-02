package handlers

import (
	"testing"
	"time"

	"financetracker/models"
)

func TestFfClassifyStockBucket(t *testing.T) {
	cases := []struct {
		industry, isin, want string
	}{
		{"Gold & Silver", "INE123A01016", ffPresetDigitalGold},
		{"gold & silver", "", ffPresetDigitalGold},
		{"SGB", "IN0020200069", ffPresetSGB},
		{"sgb", "", ffPresetSGB},
		{"ETF", "INF123", ffPresetETFIndex},
		{"etf", "US0378331005", ffPresetETFIndex},
		{"Banks", "INE040A01034", ffPresetStocksDomestic},
		{"Banks", "", ffPresetStocksDomestic},
		// International ISIN still rolls into domestic; user fills International manually.
		{"Technology", "US0378331005", ffPresetStocksDomestic},
		{"", "US5949181045", ffPresetStocksDomestic},
	}
	for _, tc := range cases {
		got := ffClassifyStockBucket(tc.industry, tc.isin)
		if got != tc.want {
			t.Fatalf("industry=%q isin=%q: got %s want %s", tc.industry, tc.isin, got, tc.want)
		}
	}
}

func TestFfRupeesToK(t *testing.T) {
	if got := ffRupeesToK(500000); got != 500 {
		t.Fatalf("got %v want 500", got)
	}
	if got := ffRupeesToK(12345); got != 12.35 {
		t.Fatalf("got %v want 12.35", got)
	}
	if got := ffRupeesToK(0); got != 0 {
		t.Fatalf("got %v want 0", got)
	}
}

func TestSyncFFAssetsFromPortfolio(t *testing.T) {
	h, admin, _ := ffTestSetup(t)

	gold := models.Stock{
		Symbol: "GOLDBEES", Name: "Gold Bees", Industry: "Gold & Silver", CurrentPrice: 50,
		ISIN: "INE111A01010",
	}
	sgb := models.Stock{
		Symbol: "SGBOCT25", Name: "SGB Oct25", Industry: "SGB", CurrentPrice: 6000,
		ISIN: "IN0020200069",
	}
	etf := models.Stock{
		Symbol: "NIFTYBEES", Name: "Nifty Bees", Industry: "ETF", CurrentPrice: 200,
		ISIN: "INF222A01010",
	}
	dom := models.Stock{
		Symbol: "RELIANCE", Name: "Reliance", Industry: "Oil", CurrentPrice: 1000,
		ISIN: "INE002A01018",
	}
	intl := models.Stock{
		Symbol: "AAPL", Name: "Apple", Industry: "Technology", CurrentPrice: 150,
		ISIN: "US0378331005",
	}
	for _, s := range []*models.Stock{&gold, &sgb, &etf, &dom, &intl} {
		if err := h.DB.Create(s).Error; err != nil {
			t.Fatalf("stock: %v", err)
		}
	}

	holds := []models.UserStock{
		{UserID: admin.ID, StockID: gold.ID, Source: models.SourceManualAdd, Quantity: 10}, // 500
		{UserID: admin.ID, StockID: sgb.ID, Source: models.SourceManualAdd, Quantity: 1},   // 6000
		{UserID: admin.ID, StockID: etf.ID, Source: models.SourceManualAdd, Quantity: 5},   // 1000
		{UserID: admin.ID, StockID: dom.ID, Source: models.SourceManualAdd, Quantity: 2},   // 2000
		{UserID: admin.ID, StockID: intl.ID, Source: models.SourceManualAdd, Quantity: 4},  // 600 → domestic
	}
	for _, p := range holds {
		if err := h.DB.Create(&p).Error; err != nil {
			t.Fatalf("hold: %v", err)
		}
	}

	mf := models.MutualFund{
		UserID: admin.ID, SchemeCode: "x", SchemeName: "Fund", Source: models.SourceManualAdd,
		Quantity: 100, NAV: 20, CurrentNAV: 25, PurchaseDate: time.Now(),
	}
	if err := h.DB.Create(&mf).Error; err != nil {
		t.Fatalf("mf: %v", err)
	}

	if err := h.syncFFAssetsFromPortfolio(admin.ID); err != nil {
		t.Fatalf("sync: %v", err)
	}

	want := map[string]float64{
		ffPresetDigitalGold:    0.5,  // 500/1000
		ffPresetSGB:            6,    // 6000/1000
		ffPresetETFIndex:       1,    // 1000/1000
		ffPresetStocksDomestic: 2.6,  // (2000+600)/1000
		ffPresetMutualFunds:    2.5,  // 2500/1000
	}
	var assets []models.FFAsset
	if err := h.DB.Where("user_id = ?", admin.ID).Find(&assets).Error; err != nil {
		t.Fatalf("list: %v", err)
	}
	got := map[string]float64{}
	for _, a := range assets {
		if a.PresetKey == nil {
			continue
		}
		got[*a.PresetKey] = a.Value
	}
	for k, v := range want {
		if got[k] != v {
			t.Fatalf("%s: got %v want %v (all=%v)", k, got[k], v, got)
		}
	}
	if _, ok := got["stocks_international"]; ok {
		t.Fatalf("international should not be auto-synced: %v", got)
	}
}
