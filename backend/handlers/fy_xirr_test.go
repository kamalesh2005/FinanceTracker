package handlers

import (
	"math"
	"testing"
	"time"

	"financetracker/models"
)

func TestXirrStockSinceFY25_PreFYUsesLtpFY24(t *testing.T) {
	buy := time.Date(2020, 1, 15, 0, 0, 0, 0, time.UTC)
	lots := []models.UserStockTransaction{{
		Type:             models.TransactionTypeBuy,
		StockID:          1,
		Quantity:         10,
		OriginalQuantity: 10,
		Price:            50, // ignored — pre-FY25
		TransactionDate:  &buy,
	}}
	prices := map[uint]stockFYPrices{
		1: {Current: 200, LtpFY2024: 100, LtpFY2025: 110},
	}
	rate := xirrStockSinceFY25(lots, prices)
	if rate == nil {
		t.Fatal("expected rate")
	}
	// ~1 year 100→110 = 10%
	if math.Abs(*rate-0.10) > 1e-4 {
		t.Fatalf("rate=%v want ~0.10", *rate)
	}
}

func TestXirrStockSinceFY25_UndatedUsesLtpFY24(t *testing.T) {
	lots := []models.UserStockTransaction{{
		Type:             models.TransactionTypeBuy,
		StockID:          1,
		Quantity:         10,
		OriginalQuantity: 10,
		Price:            1,
		TransactionDate:  nil,
	}}
	prices := map[uint]stockFYPrices{
		1: {Current: 200, LtpFY2024: 100, LtpFY2025: 110},
	}
	rate := xirrStockSinceFY25(lots, prices)
	if rate == nil {
		t.Fatal("expected rate for undated lot")
	}
}

func TestXirrStockSinceFY25_MissingLTPSkipped(t *testing.T) {
	buy := time.Date(2020, 1, 15, 0, 0, 0, 0, time.UTC)
	lots := []models.UserStockTransaction{{
		Type:             models.TransactionTypeBuy,
		StockID:          1,
		Quantity:         10,
		OriginalQuantity: 10,
		Price:            50,
		TransactionDate:  &buy,
	}}
	prices := map[uint]stockFYPrices{
		1: {Current: 200, LtpFY2024: 0, LtpFY2025: 110},
	}
	if rate := xirrStockSinceFY25(lots, prices); rate != nil {
		t.Fatalf("expected nil when LtpFY2024 missing, got %v", *rate)
	}
}

func TestXirrStockSinceFY25_PostFY25Excluded(t *testing.T) {
	buy := time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC)
	lots := []models.UserStockTransaction{{
		Type:             models.TransactionTypeBuy,
		StockID:          1,
		Quantity:         10,
		OriginalQuantity: 10,
		Price:            100,
		TransactionDate:  &buy,
	}}
	prices := map[uint]stockFYPrices{
		1: {Current: 200, LtpFY2024: 100, LtpFY2025: 110},
	}
	if rate := xirrStockSinceFY25(lots, prices); rate != nil {
		t.Fatalf("expected nil for post-FY25 buy, got %v", *rate)
	}
}

func TestXirrStockFY26YTD_PreFYUsesLtpFY25(t *testing.T) {
	buy := time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC)
	lots := []models.UserStockTransaction{{
		Type:             models.TransactionTypeBuy,
		StockID:          1,
		Quantity:         10,
		OriginalQuantity: 10,
		Price:            50,
		TransactionDate:  &buy,
	}}
	prices := map[uint]stockFYPrices{
		1: {Current: 120, LtpFY2024: 100, LtpFY2025: 100},
	}
	// Short YTD window: simple return is 20%, not annualized XIRR.
	asOf := time.Date(2026, 8, 23, 0, 0, 0, 0, time.UTC)
	rate := xirrStockFY26YTD(lots, prices, asOf)
	if rate == nil {
		t.Fatal("expected rate")
	}
	if math.Abs(*rate-0.20) > 1e-3 {
		t.Fatalf("rate=%v want ~0.20 (simple, not annualized)", *rate)
	}
}

func TestXirrStockFY26YTD_ExcludesHistoricalSales(t *testing.T) {
	buyOld := time.Date(2004, 5, 14, 0, 0, 0, 0, time.UTC)
	saleOld := time.Date(2005, 1, 17, 0, 0, 0, 0, time.UTC)
	buyKeep := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	// Historical sale at tiny price must not drag FY26 when cost is rewritten to LtpFY2025.
	lots := []models.UserStockTransaction{
		{
			Type:             models.TransactionTypeBuy,
			StockID:          1,
			Quantity:         0,
			OriginalQuantity: 75,
			Price:            400,
			TransactionDate:  &buyOld,
			SalePrice:        417,
			SaleDate:         &saleOld,
		},
		{
			Type:             models.TransactionTypeBuy,
			StockID:          1,
			Quantity:         10,
			OriginalQuantity: 10,
			Price:            50,
			TransactionDate:  &buyKeep,
		},
	}
	prices := map[uint]stockFYPrices{
		1: {Current: 120, LtpFY2024: 100, LtpFY2025: 100},
	}
	asOf := time.Date(2026, 8, 23, 0, 0, 0, 0, time.UTC)
	rate := xirrStockFY26YTD(lots, prices, asOf)
	if rate == nil {
		t.Fatal("expected rate from open lot only")
	}
	if math.Abs(*rate-0.20) > 1e-3 {
		t.Fatalf("rate=%v want ~0.20 (historical sale excluded)", *rate)
	}
}

func TestXirrStockFY26YTD_IncludesSaleInFY26(t *testing.T) {
	buy := time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC)
	sale := time.Date(2026, 5, 15, 0, 0, 0, 0, time.UTC)
	lots := []models.UserStockTransaction{{
		Type:             models.TransactionTypeBuy,
		StockID:          1,
		Quantity:         0,
		OriginalQuantity: 10,
		Price:            50,
		TransactionDate:  &buy,
		SalePrice:        110,
		SaleDate:         &sale,
	}}
	prices := map[uint]stockFYPrices{
		1: {Current: 200, LtpFY2024: 100, LtpFY2025: 100},
	}
	asOf := time.Date(2026, 8, 23, 0, 0, 0, 0, time.UTC)
	rate := xirrStockFY26YTD(lots, prices, asOf)
	if rate == nil {
		t.Fatal("expected rate")
	}
	// 100 → 110 = 10%
	if math.Abs(*rate-0.10) > 1e-3 {
		t.Fatalf("rate=%v want ~0.10", *rate)
	}
}

func TestXirrStockSinceFY25_ExcludesHistoricalSales(t *testing.T) {
	buyOld := time.Date(2010, 1, 1, 0, 0, 0, 0, time.UTC)
	saleOld := time.Date(2015, 6, 1, 0, 0, 0, 0, time.UTC)
	buyKeep := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	lots := []models.UserStockTransaction{
		{
			Type:             models.TransactionTypeBuy,
			StockID:          1,
			Quantity:         0,
			OriginalQuantity: 100,
			Price:            10,
			TransactionDate:  &buyOld,
			SalePrice:        12,
			SaleDate:         &saleOld,
		},
		{
			Type:             models.TransactionTypeBuy,
			StockID:          1,
			Quantity:         10,
			OriginalQuantity: 10,
			Price:            50,
			TransactionDate:  &buyKeep,
		},
	}
	prices := map[uint]stockFYPrices{
		1: {Current: 200, LtpFY2024: 100, LtpFY2025: 110},
	}
	rate := xirrStockSinceFY25(lots, prices)
	if rate == nil {
		t.Fatal("expected rate")
	}
	if math.Abs(*rate-0.10) > 1e-4 {
		t.Fatalf("rate=%v want ~0.10 (historical sale excluded)", *rate)
	}
}

func TestXirrStockSinceFY25_SaleAfterFY25MarksToLtpFY25(t *testing.T) {
	buy := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	sale := time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC) // after FY25
	lots := []models.UserStockTransaction{{
		Type:             models.TransactionTypeBuy,
		StockID:          1,
		Quantity:         0,
		OriginalQuantity: 10,
		Price:            50,
		TransactionDate:  &buy,
		SalePrice:        50, // would look like a huge loss vs FY24 LTP if used
		SaleDate:         &sale,
	}}
	prices := map[uint]stockFYPrices{
		1: {Current: 200, LtpFY2024: 100, LtpFY2025: 110},
	}
	rate := xirrStockSinceFY25(lots, prices)
	if rate == nil {
		t.Fatal("expected rate")
	}
	if math.Abs(*rate-0.10) > 1e-4 {
		t.Fatalf("rate=%v want ~0.10 (post-FY25 sale ignored)", *rate)
	}
}

func TestXirrMFSinceFY25_UsesNavFY(t *testing.T) {
	lots := []models.UserMutualFundTransaction{{
		Type:             models.TransactionTypeBuy,
		ISIN:             "INF123",
		Quantity:         10,
		OriginalQuantity: 10,
		Price:            50, // ignored — undated
		TransactionDate:  nil,
	}}
	prices := map[string]mfFYPrices{
		"INF123": {Current: 200, NavFY2024: 100, NavFY2025: 110},
	}
	rate := xirrMFSinceFY25(lots, prices)
	if rate == nil {
		t.Fatal("expected MF rate")
	}
	if math.Abs(*rate-0.10) > 1e-4 {
		t.Fatalf("rate=%v want ~0.10", *rate)
	}
}

func TestXirrMFSinceFY25_IncludesSaleStamp(t *testing.T) {
	buy := time.Date(2020, 1, 15, 0, 0, 0, 0, time.UTC)
	sale := time.Date(2025, 9, 1, 0, 0, 0, 0, time.UTC)
	lots := []models.UserMutualFundTransaction{{
		Type:             models.TransactionTypeBuy,
		ISIN:             "INF123",
		Quantity:         0,
		OriginalQuantity: 10,
		Price:            50,
		TransactionDate:  &buy,
		SalePrice:        105,
		SaleDate:         &sale,
	}}
	prices := map[string]mfFYPrices{
		"INF123": {Current: 200, NavFY2024: 100, NavFY2025: 110},
	}
	rate := xirrMFSinceFY25(lots, prices)
	if rate == nil {
		t.Fatal("expected rate for sold lot within FY25")
	}
}

func TestXirrMFFY26YTD_PreFYUsesNavFY25(t *testing.T) {
	buy := time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC)
	lots := []models.UserMutualFundTransaction{{
		Type:             models.TransactionTypeBuy,
		ISIN:             "INF123",
		Quantity:         10,
		OriginalQuantity: 10,
		Price:            50,
		TransactionDate:  &buy,
	}}
	prices := map[string]mfFYPrices{
		"INF123": {Current: 120, NavFY2024: 100, NavFY2025: 100},
	}
	asOf := time.Date(2026, 8, 23, 0, 0, 0, 0, time.UTC)
	rate := xirrMFFY26YTD(lots, prices, asOf)
	if rate == nil {
		t.Fatal("expected rate")
	}
	if math.Abs(*rate-0.20) > 1e-3 {
		t.Fatalf("rate=%v want ~0.20 (simple, not annualized)", *rate)
	}
}

func TestXirrMFFY26YTD_ExcludesHistoricalSales(t *testing.T) {
	buyOld := time.Date(2018, 1, 1, 0, 0, 0, 0, time.UTC)
	saleOld := time.Date(2019, 6, 1, 0, 0, 0, 0, time.UTC)
	buyKeep := time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC)
	lots := []models.UserMutualFundTransaction{
		{
			Type:             models.TransactionTypeBuy,
			ISIN:             "INF123",
			Quantity:         0,
			OriginalQuantity: 100,
			Price:            40,
			TransactionDate:  &buyOld,
			SalePrice:        45,
			SaleDate:         &saleOld,
		},
		{
			Type:             models.TransactionTypeBuy,
			ISIN:             "INF123",
			Quantity:         10,
			OriginalQuantity: 10,
			Price:            50,
			TransactionDate:  &buyKeep,
		},
	}
	prices := map[string]mfFYPrices{
		"INF123": {Current: 120, NavFY2024: 100, NavFY2025: 100},
	}
	asOf := time.Date(2026, 8, 23, 0, 0, 0, 0, time.UTC)
	rate := xirrMFFY26YTD(lots, prices, asOf)
	if rate == nil {
		t.Fatal("expected rate")
	}
	if math.Abs(*rate-0.20) > 1e-3 {
		t.Fatalf("rate=%v want ~0.20 (historical sale excluded)", *rate)
	}
}

func TestXirrMFSinceFY25_ExcludesHistoricalSales(t *testing.T) {
	buyOld := time.Date(2018, 1, 1, 0, 0, 0, 0, time.UTC)
	saleOld := time.Date(2019, 6, 1, 0, 0, 0, 0, time.UTC)
	lots := []models.UserMutualFundTransaction{
		{
			Type:             models.TransactionTypeBuy,
			ISIN:             "INF123",
			Quantity:         0,
			OriginalQuantity: 100,
			Price:            40,
			TransactionDate:  &buyOld,
			SalePrice:        45,
			SaleDate:         &saleOld,
		},
		{
			Type:             models.TransactionTypeBuy,
			ISIN:             "INF123",
			Quantity:         10,
			OriginalQuantity: 10,
			Price:            50,
			TransactionDate:  nil,
		},
	}
	prices := map[string]mfFYPrices{
		"INF123": {Current: 200, NavFY2024: 100, NavFY2025: 110},
	}
	rate := xirrMFSinceFY25(lots, prices)
	if rate == nil {
		t.Fatal("expected rate")
	}
	if math.Abs(*rate-0.10) > 1e-4 {
		t.Fatalf("rate=%v want ~0.10 (historical sale excluded)", *rate)
	}
}
