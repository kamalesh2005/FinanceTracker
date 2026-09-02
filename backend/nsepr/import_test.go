package nsepr

import (
	"archive/zip"
	"bytes"
	"strings"
	"testing"
	"time"

	"financetracker/models"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func TestParseTradeDateFromFilename(t *testing.T) {
	got, err := ParseTradeDateFromFilename("pr31072026.csv")
	if err != nil {
		t.Fatal(err)
	}
	want := time.Date(2026, 7, 31, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("got %v want %v", got, want)
	}

	got6, err := ParseTradeDateFromFilename("Pr200826.csv")
	if err != nil {
		t.Fatal(err)
	}
	want6 := time.Date(2026, 8, 20, 0, 0, 0, 0, time.UTC)
	if !got6.Equal(want6) {
		t.Fatalf("6-digit got %v want %v", got6, want6)
	}

	if _, err := ParseTradeDateFromFilename("ETF_31Jul.csv"); err == nil {
		t.Fatal("expected error for non-pr filename")
	}
}

func TestImportPRCSV_NameOnlyRealHeaders(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:nsepr_name?mode=memory&cache=shared"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&models.Stock{}, &models.StockDailyClose{}); err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.Stock{Symbol: "INFY", Name: "Infosys Limited"}).Error; err != nil {
		t.Fatal(err)
	}

	csv := `MKT,SECURITY,PREV_CL_PR,OPEN_PRICE,HIGH_PRICE,LOW_PRICE,CLOSE_PRICE,NET_TRDVAL,NET_TRDQTY,IND_SEC,CORP_IND,TRADES,HI_52_WK,LO_52_WK
Y,Nifty 50,24078.30,24225.45,24265.15,24184.55,24231.85,0,0,Y, ,0,26373.20,22182.55
N,INFOSYS LIMITED,1119.80,1143.00,1144.70,1125.70,1130.00,0,0,Y, ,0,1728.00,982.40
`
	result, err := ImportPRCSV(db, strings.NewReader(csv), "pr20082026.csv")
	if err != nil {
		t.Fatal(err)
	}
	if result.Updated != 1 {
		t.Fatalf("updated=%d skipped=%d unmatched=%d", result.Updated, result.Skipped, result.Unmatched)
	}
	var stock models.Stock
	if err := db.Where("symbol = ?", "INFY").First(&stock).Error; err != nil {
		t.Fatal(err)
	}
	if stock.CurrentPrice != 1130 {
		t.Fatalf("price=%v", stock.CurrentPrice)
	}
}

func TestExtractPRCSV(t *testing.T) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create("other.txt")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = w.Write([]byte("ignore"))
	w, err = zw.Create("subdir/pr31072026.csv")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = w.Write([]byte("SYMBOL,CLOSE\nINFY,100\n"))
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}

	data, name, err := ExtractPRCSV(buf.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.EqualFold(name, "pr31072026.csv") {
		t.Fatalf("filename=%q", name)
	}
	if !strings.Contains(string(data), "INFY") {
		t.Fatalf("csv content unexpected: %s", data)
	}
}

func TestImportPRCSV_UpdatesExistingOnly(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:nsepr_import?mode=memory&cache=shared"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&models.Stock{}, &models.StockDailyClose{}); err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.Stock{Symbol: "INFY", Name: "Infosys Limited", CurrentPrice: 1}).Error; err != nil {
		t.Fatal(err)
	}

	csv := `SYMBOL,SERIES,SECURITY,CLOSE_PRICE,HI_52_WK,LO_52_WK
INFY,EQ,Infosys Limited,1500.5,1800,1200
UNKNOWN,EQ,Unknown Co,10,11,9
TOTAL,,,,,
`
	result, err := ImportPRCSV(db, strings.NewReader(csv), "pr31072026.csv")
	if err != nil {
		t.Fatal(err)
	}
	if result.Updated != 1 {
		t.Fatalf("updated=%d want 1", result.Updated)
	}
	if result.Unmatched < 1 {
		t.Fatalf("unmatched=%d want >=1", result.Unmatched)
	}

	var stock models.Stock
	if err := db.Where("symbol = ?", "INFY").First(&stock).Error; err != nil {
		t.Fatal(err)
	}
	if stock.CurrentPrice != 1500.5 {
		t.Fatalf("price=%v", stock.CurrentPrice)
	}
	if stock.SixthHighestPrice != 1800 || stock.SixthLowestPrice != 1200 {
		t.Fatalf("52w high/low = %v/%v", stock.SixthHighestPrice, stock.SixthLowestPrice)
	}

	var closes int64
	if err := db.Model(&models.StockDailyClose{}).Where("symbol = ?", "INFY").Count(&closes).Error; err != nil {
		t.Fatal(err)
	}
	if closes != 1 {
		t.Fatalf("closes=%d want 1", closes)
	}

	var unknown int64
	if err := db.Model(&models.Stock{}).Where("symbol = ?", "UNKNOWN").Count(&unknown).Error; err != nil {
		t.Fatal(err)
	}
	if unknown != 0 {
		t.Fatal("must not create new catalog rows")
	}
}

func TestImportPRCSV_PreferEQSeries(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:nsepr_eq?mode=memory&cache=shared"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&models.Stock{}, &models.StockDailyClose{}); err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.Stock{Symbol: "RELIANCE", Name: "Reliance Industries Ltd"}).Error; err != nil {
		t.Fatal(err)
	}

	csv := `SYMBOL,SERIES,SECURITY,CLOSE_PRICE,HI_52_WK,LO_52_WK
RELIANCE,BE,Reliance Industries Ltd,100,200,50
RELIANCE,EQ,Reliance Industries Ltd,250,300,100
`
	result, err := ImportPRCSV(db, strings.NewReader(csv), "pr01082026.csv")
	if err != nil {
		t.Fatal(err)
	}
	if result.Updated != 1 {
		t.Fatalf("updated=%d", result.Updated)
	}
	var stock models.Stock
	if err := db.Where("symbol = ?", "RELIANCE").First(&stock).Error; err != nil {
		t.Fatal(err)
	}
	if stock.CurrentPrice != 250 {
		t.Fatalf("want EQ close 250 got %v", stock.CurrentPrice)
	}
}
