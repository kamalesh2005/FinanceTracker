package nseimport

import (
	"strings"
	"testing"

	"financetracker/models"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func testDB(t *testing.T) *gorm.DB {
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
	if err := db.AutoMigrate(&models.Stock{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func mustStock(t *testing.T, db *gorm.DB, symbol string) models.Stock {
	t.Helper()
	var s models.Stock
	if err := db.Where("UPPER(symbol) = ?", strings.ToUpper(symbol)).First(&s).Error; err != nil {
		t.Fatalf("lookup %s: %v", symbol, err)
	}
	return s
}

const nseAllCSV = `Trade Date,Symbol,Series,Security Name,Category,Last Trade Date,Face Value(Rs.),Issue Size,Close Price/Paid up value(Rs.),Market Cap(Rs.)
31-Jul-26,360ONE,EQ,360 ONE WAM LIMITED,Listed,31-Jul-26,1,406486596,1135.3,4.61E+11
`

const niftyCSV = `Company Name,Industry,Symbol,Series,ISIN Code
360 ONE WAM Ltd.,Financial Services,360ONE,EQ,INE466L01038
`

func TestImportCSV_NSEAllCreatesWithPrice(t *testing.T) {
	db := testDB(t)
	result, err := ImportCSV(db, strings.NewReader(nseAllCSV))
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	if result.Created != 1 || result.Updated != 0 || result.Errors != 0 {
		t.Fatalf("result = %+v, want created=1", result)
	}
	s := mustStock(t, db, "360ONE")
	if s.Name != "360 ONE WAM LIMITED" {
		t.Errorf("name = %q", s.Name)
	}
	if s.CurrentPrice != 1135.3 {
		t.Errorf("current_price = %v, want 1135.3", s.CurrentPrice)
	}
	if s.Series != "EQ" {
		t.Errorf("series = %q", s.Series)
	}
	if s.ListingCategory != "Listed" {
		t.Errorf("listing_category = %q", s.ListingCategory)
	}
	if s.Industry != "" {
		t.Errorf("industry = %q, want empty from NSE_All", s.Industry)
	}
	if s.PullData != models.PullDataNo {
		t.Errorf("pull_data = %q, want N", s.PullData)
	}
}

func TestImportCSV_NiftyCreatesWithoutPrice(t *testing.T) {
	db := testDB(t)
	result, err := ImportCSV(db, strings.NewReader(niftyCSV))
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	if result.Created != 1 || result.Errors != 0 {
		t.Fatalf("result = %+v, want created=1", result)
	}
	s := mustStock(t, db, "360ONE")
	if s.Name != "360 ONE WAM Ltd." {
		t.Errorf("name = %q", s.Name)
	}
	if s.Industry != "Financial Services" {
		t.Errorf("industry = %q", s.Industry)
	}
	if s.CurrentPrice != 0 {
		t.Errorf("current_price = %v, want 0 on create without close", s.CurrentPrice)
	}
	if s.Series != "EQ" {
		t.Errorf("series = %q", s.Series)
	}
}

func TestImportCSV_NiftyDoesNotOverwriteExistingPrice(t *testing.T) {
	db := testDB(t)
	if _, err := ImportCSV(db, strings.NewReader(nseAllCSV)); err != nil {
		t.Fatalf("nse all import: %v", err)
	}
	result, err := ImportCSV(db, strings.NewReader(niftyCSV))
	if err != nil {
		t.Fatalf("nifty import: %v", err)
	}
	if result.Updated != 1 || result.Created != 0 || result.Errors != 0 {
		t.Fatalf("result = %+v, want updated=1", result)
	}
	s := mustStock(t, db, "360ONE")
	if s.CurrentPrice != 1135.3 {
		t.Errorf("current_price = %v, want preserved 1135.3", s.CurrentPrice)
	}
	if s.Industry != "Financial Services" {
		t.Errorf("industry = %q", s.Industry)
	}
	if s.Name != "360 ONE WAM Ltd." {
		t.Errorf("name = %q, want Company Name", s.Name)
	}
	if s.ListingCategory != "Listed" {
		t.Errorf("listing_category = %q, want preserved from NSE_All", s.ListingCategory)
	}
	if s.MarketCapRs == 0 {
		t.Errorf("market_cap_rs wiped; want preserved from NSE_All")
	}
}

func TestImportCSV_NSEAllDoesNotClearIndustry(t *testing.T) {
	db := testDB(t)
	if _, err := ImportCSV(db, strings.NewReader(niftyCSV)); err != nil {
		t.Fatalf("nifty import: %v", err)
	}
	result, err := ImportCSV(db, strings.NewReader(nseAllCSV))
	if err != nil {
		t.Fatalf("nse all import: %v", err)
	}
	if result.Updated != 1 {
		t.Fatalf("result = %+v, want updated=1", result)
	}
	s := mustStock(t, db, "360ONE")
	if s.Industry != "Financial Services" {
		t.Errorf("industry = %q, want preserved", s.Industry)
	}
	if s.CurrentPrice != 1135.3 {
		t.Errorf("current_price = %v", s.CurrentPrice)
	}
	if s.Name != "360 ONE WAM LIMITED" {
		t.Errorf("name = %q, want Security Name", s.Name)
	}
}

func TestImportCSV_MissingNameHeadersError(t *testing.T) {
	db := testDB(t)
	_, err := ImportCSV(db, strings.NewReader("Symbol,Series\n360ONE,EQ\n"))
	if err == nil {
		t.Fatal("expected missing name-column error")
	}
	if !strings.Contains(err.Error(), "Security Name or Company Name") {
		t.Errorf("error = %v", err)
	}
}

func TestImportCSV_MissingClosePriceOK(t *testing.T) {
	db := testDB(t)
	csv := "Symbol,Security Name,Series\nFOO,Foo Ltd,EQ\n"
	result, err := ImportCSV(db, strings.NewReader(csv))
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	if result.Created != 1 {
		t.Fatalf("result = %+v, want created=1", result)
	}
}

func TestImportCSV_DoesNotOverwritePullDataYes(t *testing.T) {
	db := testDB(t)
	if err := db.Create(&models.Stock{Symbol: "360ONE", Name: "old", PullData: models.PullDataYes, CurrentPrice: 10}).Error; err != nil {
		t.Fatalf("seed: %v", err)
	}
	if _, err := ImportCSV(db, strings.NewReader(niftyCSV)); err != nil {
		t.Fatalf("import: %v", err)
	}
	s := mustStock(t, db, "360ONE")
	if s.PullData != models.PullDataYes {
		t.Errorf("pull_data = %q, want Y", s.PullData)
	}
	if s.Industry != "Financial Services" {
		t.Errorf("industry = %q", s.Industry)
	}
}
