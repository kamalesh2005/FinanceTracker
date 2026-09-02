package handlers

import (
	"testing"
	"time"

	"financetracker/models"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func fifoTestDB(t *testing.T) *gorm.DB {
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
	if err := db.AutoMigrate(&models.Stock{}, &models.UserStock{}, &models.UserStockTransaction{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func fifoDate(y int, m time.Month, d int) time.Time {
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

func insertBuy(t *testing.T, db *gorm.DB, userID, stockID uint, source string, qty, price float64, day time.Time) models.UserStockTransaction {
	t.Helper()
	lot := models.UserStockTransaction{
		UserID:           userID,
		StockID:          stockID,
		Source:           source,
		Type:             models.TransactionTypeBuy,
		Quantity:         qty,
		OriginalQuantity: qty,
		Price:            price,
		TransactionDate:  timePtr(day),
	}
	if err := db.Create(&lot).Error; err != nil {
		t.Fatalf("create buy: %v", err)
	}
	return lot
}

func insertSell(t *testing.T, db *gorm.DB, userID, stockID uint, source string, qty, price float64, day time.Time) models.UserStockTransaction {
	t.Helper()
	row := models.UserStockTransaction{
		UserID:           userID,
		StockID:          stockID,
		Source:           source,
		Type:             models.TransactionTypeSell,
		Quantity:         qty,
		OriginalQuantity: qty,
		Price:            price,
		TransactionDate:  timePtr(day),
	}
	if err := db.Create(&row).Error; err != nil {
		t.Fatalf("create sell: %v", err)
	}
	return row
}

func loadBuys(t *testing.T, db *gorm.DB, userID, stockID uint, source string) []models.UserStockTransaction {
	t.Helper()
	var buys []models.UserStockTransaction
	if err := db.Where(
		"user_id = ? AND stock_id = ? AND source = ? AND type = ?",
		userID, stockID, source, models.TransactionTypeBuy,
	).Order("id ASC").Find(&buys).Error; err != nil {
		t.Fatalf("load buys: %v", err)
	}
	return buys
}

func TestApplyFIFOSell_PartialSplitKeepsOriginalID(t *testing.T) {
	db := fifoTestDB(t)
	buy := insertBuy(t, db, 1, 10, models.SourceManualAdd, 10, 100, fifoDate(2019, 1, 1))
	saleDay := fifoDate(2020, 3, 1)
	if err := applyFIFOSell(db, 1, 10, models.SourceManualAdd, 4, 150, saleDay); err != nil {
		t.Fatalf("fifo: %v", err)
	}

	buys := loadBuys(t, db, 1, 10, models.SourceManualAdd)
	if len(buys) != 2 {
		t.Fatalf("buy rows=%d want 2", len(buys))
	}

	var remainder, sold *models.UserStockTransaction
	for i := range buys {
		if buys[i].ID == buy.ID {
			remainder = &buys[i]
		} else {
			sold = &buys[i]
		}
	}
	if remainder == nil || sold == nil {
		t.Fatalf("expected original remainder and new sold slice: %+v", buys)
	}
	if remainder.Quantity != 6 || remainder.OriginalQuantity != 6 {
		t.Fatalf("remainder qty/orig=%v/%v want 6/6", remainder.Quantity, remainder.OriginalQuantity)
	}
	if remainder.SalePrice != 0 || remainder.SaleDate != nil {
		t.Fatalf("remainder should have no sale: %+v", remainder)
	}
	if sold.Quantity != 0 || sold.OriginalQuantity != 4 {
		t.Fatalf("sold slice qty/orig=%v/%v want 0/4", sold.Quantity, sold.OriginalQuantity)
	}
	if sold.SalePrice != 150 || sold.SaleDate == nil || !sold.SaleDate.Equal(saleDay) {
		t.Fatalf("sold slice sale=%v date=%v", sold.SalePrice, sold.SaleDate)
	}
	if sold.Price != 100 || sold.TransactionDate == nil || buy.TransactionDate == nil || !sold.TransactionDate.Equal(*buy.TransactionDate) {
		t.Fatalf("sold slice should keep buy price/date: %+v", sold)
	}
}

func TestApplyFIFOSell_ClosesOldestThenContinues(t *testing.T) {
	db := fifoTestDB(t)
	first := insertBuy(t, db, 1, 10, models.SourceManualAdd, 5, 100, fifoDate(2019, 1, 1))
	second := insertBuy(t, db, 1, 10, models.SourceManualAdd, 8, 110, fifoDate(2019, 6, 1))
	saleDay := fifoDate(2020, 1, 1)
	if err := applyFIFOSell(db, 1, 10, models.SourceManualAdd, 7, 150, saleDay); err != nil {
		t.Fatalf("fifo: %v", err)
	}

	var closed models.UserStockTransaction
	if err := db.First(&closed, first.ID).Error; err != nil {
		t.Fatal(err)
	}
	if closed.Quantity != 0 || closed.SalePrice != 150 {
		t.Fatalf("oldest lot should be fully sold: %+v", closed)
	}

	var open models.UserStockTransaction
	if err := db.First(&open, second.ID).Error; err != nil {
		t.Fatal(err)
	}
	if open.Quantity != 6 || open.OriginalQuantity != 6 || open.SalePrice != 0 {
		t.Fatalf("second lot remainder: %+v", open)
	}

	buys := loadBuys(t, db, 1, 10, models.SourceManualAdd)
	if len(buys) != 3 {
		t.Fatalf("buy rows=%d want 3 (closed + remainder + sold slice)", len(buys))
	}
}

func TestApplyManualBuy_RemainingEqualsBoughtQty(t *testing.T) {
	db := fifoTestDB(t)
	stock := models.Stock{Symbol: "TCS", CurrentPrice: 3500}
	if err := db.Create(&stock).Error; err != nil {
		t.Fatal(err)
	}
	day := fifoDate(2024, 1, 15)
	ledger, pos, err := applyManualStockTransaction(
		db, 1, stock.ID, models.TransactionTypeBuy, 12, 3400, day, models.SourceManualAdd,
	)
	if err != nil {
		t.Fatalf("buy: %v", err)
	}
	if ledger.Quantity != 12 || ledger.OriginalQuantity != 12 {
		t.Fatalf("buy lot qty/orig=%v/%v want 12/12", ledger.Quantity, ledger.OriginalQuantity)
	}
	if pos.Quantity != 12 || pos.AvgBuyPrice != 3400 {
		t.Fatalf("position qty/avg=%v/%v", pos.Quantity, pos.AvgBuyPrice)
	}
	if ledger.Origin != models.TxOriginUI {
		t.Fatalf("origin=%q want %q", ledger.Origin, models.TxOriginUI)
	}
	if ledger.TransactionDate == nil || !ledger.TransactionDate.Equal(day) {
		t.Fatalf("buy date=%v want %v", ledger.TransactionDate, day)
	}
}

func TestBackfillFIFO_StampsSaleAndIsIdempotent(t *testing.T) {
	db := fifoTestDB(t)
	buy := insertBuy(t, db, 1, 10, models.SourceManualAdd, 10, 100, fifoDate(2019, 1, 1))
	// Old FIFO leftover: remaining reduced, no sale_price.
	if err := db.Model(&buy).Update("quantity", 6).Error; err != nil {
		t.Fatal(err)
	}
	insertSell(t, db, 1, 10, models.SourceManualAdd, 4, 150, fifoDate(2020, 3, 1))

	if err := BackfillOriginalQuantityAndFIFO(db); err != nil {
		t.Fatalf("backfill: %v", err)
	}
	buys1 := loadBuys(t, db, 1, 10, models.SourceManualAdd)
	if len(buys1) != 2 {
		t.Fatalf("after first backfill buy rows=%d want 2", len(buys1))
	}
	stamped := 0
	for _, b := range buys1 {
		if b.SalePrice > 0 && b.SaleDate != nil {
			stamped++
			if b.OriginalQuantity != 4 || b.Quantity != 0 || b.SalePrice != 150 {
				t.Fatalf("sold slice after backfill: %+v", b)
			}
		} else if b.ID == buy.ID {
			if b.Quantity != 6 || b.OriginalQuantity != 6 {
				t.Fatalf("remainder after backfill: %+v", b)
			}
		}
	}
	if stamped != 1 {
		t.Fatalf("stamped sale lots=%d want 1", stamped)
	}

	if err := BackfillOriginalQuantityAndFIFO(db); err != nil {
		t.Fatalf("second backfill: %v", err)
	}
	buys2 := loadBuys(t, db, 1, 10, models.SourceManualAdd)
	if len(buys2) != len(buys1) {
		t.Fatalf("second backfill duplicated splits: %d -> %d", len(buys1), len(buys2))
	}
}

func TestBackfill_NoSellFixesRemainingToBoughtQty(t *testing.T) {
	db := fifoTestDB(t)
	buy := insertBuy(t, db, 1, 10, models.SourceManualAdd, 10, 100, fifoDate(2019, 1, 1))
	if err := db.Model(&buy).Update("quantity", 7).Error; err != nil {
		t.Fatal(err)
	}
	if err := BackfillOriginalQuantityAndFIFO(db); err != nil {
		t.Fatal(err)
	}
	var got models.UserStockTransaction
	if err := db.First(&got, buy.ID).Error; err != nil {
		t.Fatal(err)
	}
	if got.Quantity != 10 || got.OriginalQuantity != 10 {
		t.Fatalf("unsold buy should reset remaining=bought: %+v", got)
	}
}

func insertBuyUndated(t *testing.T, db *gorm.DB, userID, stockID uint, source string, qty, price float64) models.UserStockTransaction {
	t.Helper()
	lot := models.UserStockTransaction{
		UserID:           userID,
		StockID:          stockID,
		Source:           source,
		Type:             models.TransactionTypeBuy,
		Quantity:         qty,
		OriginalQuantity: qty,
		Price:            price,
		Origin:           models.TxOriginSnapshot,
	}
	if err := db.Create(&lot).Error; err != nil {
		t.Fatalf("create undated buy: %v", err)
	}
	return lot
}

func TestApplyFIFOSell_NullDateIsOldest(t *testing.T) {
	db := fifoTestDB(t)
	dated := insertBuy(t, db, 1, 10, models.SourceHDFCSec, 5, 100, fifoDate(2018, 1, 1))
	blank := insertBuyUndated(t, db, 1, 10, models.SourceHDFCSec, 8, 90)
	saleDay := fifoDate(2024, 6, 1)
	if err := applyFIFOSell(db, 1, 10, models.SourceHDFCSec, 3, 150, saleDay); err != nil {
		t.Fatalf("fifo: %v", err)
	}

	var blankLot models.UserStockTransaction
	if err := db.First(&blankLot, blank.ID).Error; err != nil {
		t.Fatal(err)
	}
	if blankLot.Quantity != 5 || blankLot.OriginalQuantity != 5 {
		t.Fatalf("blank remainder qty/orig=%v/%v want 5/5", blankLot.Quantity, blankLot.OriginalQuantity)
	}
	if blankLot.TransactionDate != nil {
		t.Fatalf("remainder should keep blank buy date: %+v", blankLot)
	}

	var datedLot models.UserStockTransaction
	if err := db.First(&datedLot, dated.ID).Error; err != nil {
		t.Fatal(err)
	}
	if datedLot.Quantity != 5 || datedLot.SalePrice != 0 {
		t.Fatalf("dated lot should be untouched: %+v", datedLot)
	}

	buys := loadBuys(t, db, 1, 10, models.SourceHDFCSec)
	sold := 0
	for _, b := range buys {
		if b.SalePrice > 0 && b.Quantity == 0 {
			sold++
			if b.OriginalQuantity != 3 || b.TransactionDate != nil {
				t.Fatalf("sold slice from blank lot: %+v", b)
			}
		}
	}
	if sold != 1 {
		t.Fatalf("sold slices=%d want 1", sold)
	}
}

func TestApplyUploadPosition_OmitsDateAndSetsOrigin(t *testing.T) {
	db := fifoTestDB(t)
	stock := models.Stock{Symbol: "INFY", CurrentPrice: 1500}
	if err := db.Create(&stock).Error; err != nil {
		t.Fatal(err)
	}
	pos, delta, err := applyUploadPosition(db, 1, stock.ID, stock.Symbol, models.SourceHDFCSec, 10, 1400, nil, false, 1500)
	if err != nil {
		t.Fatalf("upload: %v", err)
	}
	if pos.Quantity != 10 || pos.AvgBuyPrice != 1400 {
		t.Fatalf("position=%+v", pos)
	}
	if pos.LastBuyDate != nil {
		t.Fatalf("first insert last_buy_date should be nil, got %v", pos.LastBuyDate)
	}
	if delta == nil || delta.TransactionDate != nil || delta.Origin != models.TxOriginSnapshot {
		t.Fatalf("delta date/origin=%v/%q", delta.TransactionDate, delta.Origin)
	}

	pos2, delta2, err := applyUploadPosition(db, 1, stock.ID, stock.Symbol, models.SourceHDFCSec, 10, 1400, nil, false, 1500)
	if err != nil {
		t.Fatalf("reupload: %v", err)
	}
	if delta2 != nil {
		t.Fatalf("unchanged qty should not write a ledger row: %+v", delta2)
	}
	var lots []models.UserStockTransaction
	if err := db.Where("user_id = ? AND stock_id = ?", 1, stock.ID).Find(&lots).Error; err != nil {
		t.Fatal(err)
	}
	if len(lots) != 1 || lots[0].TransactionDate != nil {
		t.Fatalf("reupload must not overwrite buy date: %+v", lots)
	}
	_ = pos2
}
