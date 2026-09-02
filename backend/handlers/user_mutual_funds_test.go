package handlers

import (
	"testing"
	"time"

	"financetracker/models"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func mfUploadTestDB(t *testing.T) *gorm.DB {
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
	if err := db.AutoMigrate(&models.MutualFund{}, &models.UserMutualFundTransaction{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func TestApplyUploadMFPosition_OmitsDateAndSetsOrigin(t *testing.T) {
	db := mfUploadTestDB(t)
	pos, delta, err := applyUploadMFPosition(
		db, 1,
		"INF090I01239", "120503", "Test Fund", "Broker Name", models.SourceHDFCSec,
		10, 50, 55, nil,
	)
	if err != nil {
		t.Fatalf("upload: %v", err)
	}
	if pos.Quantity != 10 || pos.NAV != 50 {
		t.Fatalf("position=%+v", pos)
	}
	if !pos.PurchaseDate.IsZero() {
		t.Fatalf("purchase_date should be zero on snapshot upload, got %v", pos.PurchaseDate)
	}
	if delta == nil || delta.TransactionDate != nil || delta.Origin != models.TxOriginSnapshot {
		t.Fatalf("delta date/origin=%v/%q", delta.TransactionDate, delta.Origin)
	}
	if delta.Type != models.TransactionTypeBuy || delta.Quantity != 10 {
		t.Fatalf("delta=%+v", delta)
	}

	// Same qty reupload: no new ledger row; purchase date still unset.
	pos2, delta2, err := applyUploadMFPosition(
		db, 1,
		"INF090I01239", "120503", "Test Fund", "Broker Name", models.SourceHDFCSec,
		10, 50, 55, nil,
	)
	if err != nil {
		t.Fatalf("reupload: %v", err)
	}
	if pos2.Quantity != 10 || delta2 != nil {
		t.Fatalf("same qty should be no-op on ledger: pos=%+v delta=%v", pos2, delta2)
	}
	if !pos2.PurchaseDate.IsZero() {
		t.Fatalf("reupload must not set purchase_date, got %v", pos2.PurchaseDate)
	}

	var count int64
	if err := db.Model(&models.UserMutualFundTransaction{}).Count(&count).Error; err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("ledger rows=%d want 1", count)
	}
}

func TestApplyUploadMFPosition_DeltaBuyAndSell(t *testing.T) {
	db := mfUploadTestDB(t)
	_, _, err := applyUploadMFPosition(
		db, 1,
		"INF090I01239", "120503", "Test Fund", "Broker", models.SourceICICIDirect,
		10, 100, 110, nil,
	)
	if err != nil {
		t.Fatal(err)
	}

	pos, delta, err := applyUploadMFPosition(
		db, 1,
		"INF090I01239", "120503", "Test Fund", "Broker", models.SourceICICIDirect,
		15, 100, 120, nil,
	)
	if err != nil {
		t.Fatal(err)
	}
	if pos.Quantity != 15 || delta == nil || delta.Type != models.TransactionTypeBuy || delta.Quantity != 5 {
		t.Fatalf("buy delta: pos=%+v delta=%+v", pos, delta)
	}
	if delta.Price != 120 {
		t.Fatalf("buy delta price=%v want current NAV 120", delta.Price)
	}

	pos, delta, err = applyUploadMFPosition(
		db, 1,
		"INF090I01239", "120503", "Test Fund", "Broker", models.SourceICICIDirect,
		7, 100, 125, nil,
	)
	if err != nil {
		t.Fatal(err)
	}
	if pos.Quantity != 7 || delta == nil || delta.Type != models.TransactionTypeSell || delta.Quantity != 8 {
		t.Fatalf("sell delta: pos=%+v delta=%+v", pos, delta)
	}

	buys, err := loadOpenMFBuys(db, 1, "INF090I01239", "Broker", models.SourceICICIDirect)
	if err != nil {
		t.Fatal(err)
	}
	open := 0.0
	for _, b := range buys {
		open += b.Quantity
	}
	if open < 6.999 || open > 7.001 {
		t.Fatalf("open buy lots sum=%v want 7", open)
	}
}

func TestApplyUploadMFPosition_ZeroStale(t *testing.T) {
	db := mfUploadTestDB(t)
	_, _, err := applyUploadMFPosition(
		db, 1,
		"INF090I01239", "120503", "Test Fund", "Broker", models.SourceHDFCSec,
		10, 50, 55, nil,
	)
	if err != nil {
		t.Fatal(err)
	}

	pos, delta, err := applyUploadMFPosition(
		db, 1,
		"INF090I01239", "120503", "Test Fund", "Broker", models.SourceHDFCSec,
		0, 50, 55, nil,
	)
	if err != nil {
		t.Fatal(err)
	}
	if pos.Quantity != 0 || delta == nil || delta.Type != models.TransactionTypeSell || delta.Quantity != 10 {
		t.Fatalf("zero: pos=%+v delta=%+v", pos, delta)
	}

	buys, err := loadOpenMFBuys(db, 1, "INF090I01239", "Broker", models.SourceHDFCSec)
	if err != nil {
		t.Fatal(err)
	}
	if len(buys) != 0 {
		t.Fatalf("expected no open buys after full sell, got %+v", buys)
	}
}

func TestApplyMFFIFOSell_SplitsLot(t *testing.T) {
	db := mfUploadTestDB(t)
	day := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	lot := models.UserMutualFundTransaction{
		UserID:           1,
		ISIN:             "INF090I01239",
		Source:           models.SourceManualAdd,
		Type:             models.TransactionTypeBuy,
		Quantity:         10,
		OriginalQuantity: 10,
		Price:            100,
		TransactionDate:  &day,
	}
	if err := db.Create(&lot).Error; err != nil {
		t.Fatal(err)
	}
	saleDay := time.Date(2021, 1, 1, 0, 0, 0, 0, time.UTC)
	if err := applyMFFIFOSell(db, 1, "INF090I01239", "", models.SourceManualAdd, 4, 150, saleDay); err != nil {
		t.Fatalf("fifo: %v", err)
	}

	var buys []models.UserMutualFundTransaction
	if err := db.Where("type = ?", models.TransactionTypeBuy).Find(&buys).Error; err != nil {
		t.Fatal(err)
	}
	if len(buys) != 2 {
		t.Fatalf("want remainder + sold slice, got %d", len(buys))
	}
}

func TestApplyUploadMFPosition_UnmatchedBySourceName(t *testing.T) {
	db := mfUploadTestDB(t)
	pos, delta, err := applyUploadMFPosition(
		db, 1,
		"", "", "", "Unknown Scheme XYZ", models.SourceZerodha,
		5, 20, 0, nil,
	)
	if err != nil {
		t.Fatal(err)
	}
	if pos.ISIN != "" || pos.SourceSchemeName != "Unknown Scheme XYZ" || pos.Quantity != 5 {
		t.Fatalf("pos=%+v", pos)
	}
	if delta == nil || delta.ISIN != "" || delta.SourceSchemeName != "Unknown Scheme XYZ" {
		t.Fatalf("delta=%+v", delta)
	}
}
