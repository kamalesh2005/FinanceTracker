package bsebhav

import (
	"strings"
	"testing"
	"time"

	"financetracker/models"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func TestLooksLikeBhavCSV(t *testing.T) {
	ok := []byte("TradDt,ISIN,TckrSymb,FinInstrmNm,ClsPric\n2026-08-21,INE117A01022,ABB,ABB INDIA LIMITED,7412.00\n")
	if !looksLikeBhavCSV(ok) {
		t.Fatal("expected valid header")
	}
	if looksLikeBhavCSV([]byte("<!DOCTYPE html><html>missing</html>")) {
		t.Fatal("HTML must fail")
	}
}

func TestImportCSV_CreateUpdateAnd12hGate(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:bse_import_"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&models.Stock{}); err != nil {
		t.Fatal(err)
	}

	csv1 := `ISIN,TckrSymb,FinInstrmNm,ClsPric
INE117A01022,ABB,ABB INDIA LIMITED,7412.00
`
	r1, err := ImportCSV(db, strings.NewReader(csv1), "BhavCopy_BSE_CM_0_0_0_20260821_F_0000.CSV")
	if err != nil {
		t.Fatal(err)
	}
	if r1.Created != 1 {
		t.Fatalf("created=%d want 1", r1.Created)
	}

	var stock models.Stock
	if err := db.Where("isin = ?", "INE117A01022").First(&stock).Error; err != nil {
		t.Fatal(err)
	}
	if stock.Symbol != "ABB" || stock.CurrentPrice != 7412 {
		t.Fatalf("stock=%+v", stock)
	}

	// Within 12h: skip
	csv2 := `ISIN,TckrSymb,FinInstrmNm,ClsPric
INE117A01022,ABB,ABB INDIA LIMITED,7500.00
`
	r2, err := ImportCSV(db, strings.NewReader(csv2), "bse.csv")
	if err != nil {
		t.Fatal(err)
	}
	if r2.Skipped != 1 || r2.Updated != 0 {
		t.Fatalf("within 12h: updated=%d skipped=%d", r2.Updated, r2.Skipped)
	}
	if err := db.Where("isin = ?", "INE117A01022").First(&stock).Error; err != nil {
		t.Fatal(err)
	}
	if stock.CurrentPrice != 7412 {
		t.Fatalf("price should stay 7412 got %v", stock.CurrentPrice)
	}

	// Age last_price_fetched beyond 12h
	old := time.Now().UTC().Add(-13 * time.Hour)
	if err := db.Model(&stock).Update("last_price_fetched_date", old).Error; err != nil {
		t.Fatal(err)
	}
	r3, err := ImportCSV(db, strings.NewReader(csv2), "bse.csv")
	if err != nil {
		t.Fatal(err)
	}
	if r3.Updated != 1 {
		t.Fatalf("after 12h: updated=%d", r3.Updated)
	}
	if err := db.Where("isin = ?", "INE117A01022").First(&stock).Error; err != nil {
		t.Fatal(err)
	}
	if stock.CurrentPrice != 7500 {
		t.Fatalf("price=%v want 7500", stock.CurrentPrice)
	}
}

func TestImportCSV_SymbolConflictDifferentISIN(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:bse_conflict_"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&models.Stock{}); err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.Stock{
		Symbol: "ABB",
		ISIN:   "INEOTHER00001",
		Name:   "Other ABB",
	}).Error; err != nil {
		t.Fatal(err)
	}

	csv := `ISIN,TckrSymb,FinInstrmNm,ClsPric
INE117A01022,ABB,ABB INDIA LIMITED,7412.00
`
	r, err := ImportCSV(db, strings.NewReader(csv), "bse.csv")
	if err != nil {
		t.Fatal(err)
	}
	if r.Skipped != 1 || r.Created != 0 {
		t.Fatalf("conflict: created=%d skipped=%d", r.Created, r.Skipped)
	}
}

func TestImportCSV_AttachISINToExistingSymbol(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:bse_attach_"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&models.Stock{}); err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.Stock{
		Symbol: "ABB",
		Name:   "Abb stub",
	}).Error; err != nil {
		t.Fatal(err)
	}

	csv := `ISIN,TckrSymb,FinInstrmNm,ClsPric
INE117A01022,ABB,ABB INDIA LIMITED,7412.00
`
	r, err := ImportCSV(db, strings.NewReader(csv), "bse.csv")
	if err != nil {
		t.Fatal(err)
	}
	if r.Updated != 1 {
		t.Fatalf("updated=%d want 1", r.Updated)
	}
	var stock models.Stock
	if err := db.Where("symbol = ?", "ABB").First(&stock).Error; err != nil {
		t.Fatal(err)
	}
	if stock.ISIN != "INE117A01022" || stock.CurrentPrice != 7412 {
		t.Fatalf("stock=%+v", stock)
	}
}
