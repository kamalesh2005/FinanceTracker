package handlers

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"financetracker/models"

	"gorm.io/gorm"
)

var (
	errInsufficientQuantity = errors.New("insufficient quantity")
)

func normalizeSource(source string) string {
	source = strings.TrimSpace(source)
	if source == "" {
		return models.SourceManualAdd
	}
	return source
}

func timePtr(t time.Time) *time.Time {
	if t.IsZero() {
		return nil
	}
	d := t
	return &d
}

func cloneTime(t *time.Time) *time.Time {
	if t == nil {
		return nil
	}
	d := *t
	return &d
}

func saleStamp(txDate *time.Time) time.Time {
	if txDate != nil && !txDate.IsZero() {
		return *txDate
	}
	return time.Now()
}

func catalogStockTrend(tx *gorm.DB, stockID uint) string {
	var stock models.Stock
	if err := tx.Select("trend").First(&stock, stockID).Error; err != nil {
		return ""
	}
	return strings.TrimSpace(stock.Trend)
}

func txnOriginOr(origin, fallback string) string {
	origin = strings.TrimSpace(origin)
	if origin == "" {
		return fallback
	}
	return origin
}

// sortLotsFIFO puts blank buy dates first (oldest), then date ascending, then id.
func sortLotsFIFO(lots []models.UserStockTransaction) {
	sort.SliceStable(lots, func(i, j int) bool {
		ti, tj := lots[i].TransactionDate, lots[j].TransactionDate
		switch {
		case ti == nil && tj == nil:
			return lots[i].ID < lots[j].ID
		case ti == nil:
			return true
		case tj == nil:
			return false
		case !ti.Equal(*tj):
			return ti.Before(*tj)
		default:
			return lots[i].ID < lots[j].ID
		}
	})
}

func validateBuyQuantityPrice(quantity, price float64) error {
	return validateBuyQuantityPriceOpts(quantity, price, false)
}

func validateBuyQuantityPriceOpts(quantity, price float64, allowZeroPrice bool) error {
	if quantity < 0 {
		return fmt.Errorf("quantity cannot be negative")
	}
	if price < 0 {
		return fmt.Errorf("price cannot be negative")
	}
	if !allowZeroPrice && quantity > 0 && price <= 0 {
		return fmt.Errorf("price must be greater than 0")
	}
	return nil
}

type stockTxnExtras struct {
	Brokerage          float64
	TransactionCharges float64
	StampDuty          float64
	Segment            string
	STT                string
	Exchange           string
}

type applyStockTxnOpts struct {
	AllowZeroBuyPrice bool
	Extras            *stockTxnExtras
	Origin            string
}

// RecomputeUserStock rebuilds User_Stocks for user+source+stock from open buy lots.
func RecomputeUserStock(db *gorm.DB, userID, stockID uint, source string) (models.UserStock, error) {
	return recomputeUserStock(db, userID, stockID, source)
}

// recomputeUserStock rebuilds User_Stocks from remaining buy lot quantities only (ignores sells for avg/qty).
func recomputeUserStock(db *gorm.DB, userID, stockID uint, source string) (models.UserStock, error) {
	source = normalizeSource(source)

	var txs []models.UserStockTransaction
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).
		Find(&txs).Error; err != nil {
		return models.UserStock{}, err
	}
	sortLotsFIFO(txs)

	qty := 0.0
	invested := 0.0
	avg := 0.0
	var lastBuyPrice float64
	var lastSalePrice float64
	var lastBuyDate *time.Time
	var lastSaleDate *time.Time

	for _, tx := range txs {
		switch tx.Type {
		case models.TransactionTypeBuy:
			if tx.Quantity > 1e-9 {
				invested += tx.Price * tx.Quantity
				qty += tx.Quantity
			}
			lastBuyPrice = tx.Price
			lastBuyDate = cloneTime(tx.TransactionDate)
		case models.TransactionTypeSell:
			lastSalePrice = tx.Price
			lastSaleDate = cloneTime(tx.TransactionDate)
		}
	}
	if qty > 1e-9 {
		avg = invested / qty
	} else {
		qty = 0
		avg = 0
	}

	var pos models.UserStock
	err := db.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).First(&pos).Error
	if err != nil && err != gorm.ErrRecordNotFound {
		return models.UserStock{}, err
	}

	pos.UserID = userID
	pos.StockID = stockID
	pos.Source = source
	pos.Quantity = qty
	pos.AvgBuyPrice = avg
	pos.LastBuyPrice = lastBuyPrice
	pos.LastBuyDate = lastBuyDate
	pos.LastSalePrice = lastSalePrice
	pos.LastSaleDate = lastSaleDate

	if err == gorm.ErrRecordNotFound {
		if err := db.Create(&pos).Error; err != nil {
			return models.UserStock{}, err
		}
		return pos, nil
	}
	if err := db.Save(&pos).Error; err != nil {
		return models.UserStock{}, err
	}
	return pos, nil
}

// ApplyFIFOSell stamps sale_price/sale_date onto oldest open buy lots and splits a lot
// when only part of it is sold. Remainder stays on the original row so FIFO order is unchanged.
func ApplyFIFOSell(db *gorm.DB, userID, stockID uint, source string, sellQty, salePrice float64, saleDate time.Time) error {
	return applyFIFOSell(db, userID, stockID, source, sellQty, salePrice, saleDate)
}

// applyFIFOSell stamps sale_price/sale_date onto oldest open buy lots (FIFO).
// Full consume: Quantity=0 and sale fields set. Partial: remainder stays on the
// original id; a new buy row is inserted for the sold slice.
func applyFIFOSell(db *gorm.DB, userID, stockID uint, source string, sellQty, salePrice float64, saleDate time.Time) error {
	var buys []models.UserStockTransaction
	if err := db.Where(
		"user_id = ? AND stock_id = ? AND source = ? AND type = ? AND quantity > 0",
		userID, stockID, source, models.TransactionTypeBuy,
	).Find(&buys).Error; err != nil {
		return err
	}
	sortLotsFIFO(buys)

	remaining := sellQty
	for i := range buys {
		if remaining < 1e-9 {
			break
		}
		openQty := buys[i].Quantity
		if openQty <= remaining+1e-9 {
			d := saleDate
			buys[i].Quantity = 0
			buys[i].SalePrice = salePrice
			buys[i].SaleDate = &d
			if err := db.Save(&buys[i]).Error; err != nil {
				return err
			}
			remaining -= openQty
			if remaining < 1e-9 {
				remaining = 0
			}
			continue
		}

		take := remaining
		remainderQty := openQty - take
		if remainderQty < 1e-9 {
			remainderQty = 0
		}

		d := saleDate
		sold := buys[i]
		sold.ID = 0
		sold.CreatedAt = time.Time{}
		sold.Quantity = 0
		sold.OriginalQuantity = take
		sold.SalePrice = salePrice
		sold.SaleDate = &d
		if err := db.Create(&sold).Error; err != nil {
			return err
		}

		buys[i].Quantity = remainderQty
		buys[i].OriginalQuantity = remainderQty
		buys[i].SalePrice = 0
		buys[i].SaleDate = nil
		if err := db.Save(&buys[i]).Error; err != nil {
			return err
		}
		remaining = 0
	}
	if remaining > 1e-9 {
		return fmt.Errorf("%w: could not allocate %.4f from buy lots", errInsufficientQuantity, remaining)
	}
	return nil
}

func clearPriceThresholds(pos *models.UserStock) {
	pos.SetBuyPrice = 0
	pos.SetProfitBookingPrice = 0
	pos.SetStopLossPrice = 0
}

// ApplyManualStockTransaction inserts a ledger row then recomputes the position for the source.
func ApplyManualStockTransaction(
	db *gorm.DB,
	userID, stockID uint,
	txType models.TransactionType,
	quantity, price float64,
	txDate time.Time,
	source string,
) (models.UserStockTransaction, models.UserStock, error) {
	return applyManualStockTransaction(db, userID, stockID, txType, quantity, price, txDate, source)
}

// replaceManualAddPosition zeros open Manual Add buy lots and creates a single lot at qty/price.
func replaceManualAddPosition(
	db *gorm.DB,
	userID, stockID uint,
	quantity, price float64,
	txDate time.Time,
) error {
	if err := validateBuyQuantityPrice(quantity, price); err != nil {
		return err
	}

	var buys []models.UserStockTransaction
	if err := db.Where(
		"user_id = ? AND stock_id = ? AND source = ? AND type = ? AND quantity > 0",
		userID, stockID, models.SourceManualAdd, models.TransactionTypeBuy,
	).Find(&buys).Error; err != nil {
		return err
	}
	for i := range buys {
		buys[i].Quantity = 0
		if err := db.Save(&buys[i]).Error; err != nil {
			return err
		}
	}

	ledger := models.UserStockTransaction{
		UserID:           userID,
		StockID:          stockID,
		Source:           models.SourceManualAdd,
		Type:             models.TransactionTypeBuy,
		Quantity:         quantity,
		OriginalQuantity: quantity,
		Price:            price,
		TransactionDate:  timePtr(txDate),
		Origin:           models.TxOriginUI,
	}
	if err := db.Create(&ledger).Error; err != nil {
		return err
	}

	pos, err := recomputeUserStock(db, userID, stockID, models.SourceManualAdd)
	if err != nil {
		return err
	}
	clearPriceThresholds(&pos)
	pos.BSHClearDate = nil
	return db.Save(&pos).Error
}

// applyManualStockTransaction inserts a ledger row then recomputes Manual Add (or given source) position.
func applyManualStockTransaction(
	db *gorm.DB,
	userID, stockID uint,
	txType models.TransactionType,
	quantity, price float64,
	txDate time.Time,
	source string,
) (models.UserStockTransaction, models.UserStock, error) {
	return applyStockTransaction(db, userID, stockID, txType, quantity, price, txDate, source, applyStockTxnOpts{
		Origin: models.TxOriginUI,
	})
}

func applyStockTransaction(
	db *gorm.DB,
	userID, stockID uint,
	txType models.TransactionType,
	quantity, price float64,
	txDate time.Time,
	source string,
	opts applyStockTxnOpts,
) (models.UserStockTransaction, models.UserStock, error) {
	source = normalizeSource(source)
	if err := validateApplyStockTxn(txType, quantity, price, opts); err != nil {
		return models.UserStockTransaction{}, models.UserStock{}, err
	}

	var ledger models.UserStockTransaction
	var pos models.UserStock
	err := db.Transaction(func(tx *gorm.DB) error {
		var applyErr error
		ledger, pos, applyErr = applyStockTransactionOnTx(tx, userID, stockID, txType, quantity, price, txDate, source, opts)
		return applyErr
	})
	if err != nil {
		return models.UserStockTransaction{}, models.UserStock{}, err
	}
	return ledger, pos, nil
}

func validateApplyStockTxn(txType models.TransactionType, quantity, price float64, opts applyStockTxnOpts) error {
	if txType == models.TransactionTypeSell {
		if quantity <= 0 {
			return fmt.Errorf("quantity must be greater than 0")
		}
		if price <= 0 {
			return fmt.Errorf("price must be greater than 0")
		}
		return nil
	}
	return validateBuyQuantityPriceOpts(quantity, price, opts.AllowZeroBuyPrice)
}

func applyStockTransactionOnTx(
	tx *gorm.DB,
	userID, stockID uint,
	txType models.TransactionType,
	quantity, price float64,
	txDate time.Time,
	source string,
	opts applyStockTxnOpts,
) (models.UserStockTransaction, models.UserStock, error) {
	source = normalizeSource(source)
	if txType == models.TransactionTypeSell {
		var holding models.UserStock
		err := tx.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).First(&holding).Error
		if err == gorm.ErrRecordNotFound || holding.Quantity < quantity-1e-9 {
			available := 0.0
			if err == nil {
				available = holding.Quantity
			}
			return models.UserStockTransaction{}, models.UserStock{}, fmt.Errorf("%w: available %.2f, requested %.2f", errInsufficientQuantity, available, quantity)
		}
		if err != nil && err != gorm.ErrRecordNotFound {
			return models.UserStockTransaction{}, models.UserStock{}, err
		}
	}

	ledger := models.UserStockTransaction{
		UserID:           userID,
		StockID:          stockID,
		Source:           source,
		Type:             txType,
		Quantity:         quantity,
		OriginalQuantity: quantity,
		Price:            price,
		TransactionDate:  timePtr(txDate),
		Origin:           txnOriginOr(opts.Origin, models.TxOriginUI),
	}
	if extras := opts.Extras; extras != nil {
		ledger.Brokerage = extras.Brokerage
		ledger.TransactionCharges = extras.TransactionCharges
		ledger.StampDuty = extras.StampDuty
		ledger.Segment = extras.Segment
		ledger.STT = extras.STT
		ledger.Exchange = extras.Exchange
	}
	if err := tx.Create(&ledger).Error; err != nil {
		return models.UserStockTransaction{}, models.UserStock{}, err
	}

	if txType == models.TransactionTypeSell {
		if err := applyFIFOSell(tx, userID, stockID, source, quantity, price, txDate); err != nil {
			return models.UserStockTransaction{}, models.UserStock{}, err
		}
	}

	pos, err := recomputeUserStock(tx, userID, stockID, source)
	if err != nil {
		return models.UserStockTransaction{}, models.UserStock{}, err
	}
	clearPriceThresholds(&pos)
	pos.BSHClearDate = nil
	if trend := catalogStockTrend(tx, stockID); trend != "" {
		switch txType {
		case models.TransactionTypeBuy:
			pos.LastBuyTrend = trend
		case models.TransactionTypeSell:
			pos.LastSaleTrend = trend
		}
	}
	if err := tx.Save(&pos).Error; err != nil {
		return models.UserStockTransaction{}, models.UserStock{}, err
	}
	return ledger, pos, nil
}

type ledgerRebuildItem struct {
	Symbol             string    `json:"symbol" binding:"required"`
	Name               string    `json:"name"`
	ISIN               string    `json:"isin"`
	Action             string    `json:"action" binding:"required"`
	Quantity           float64   `json:"quantity"`
	Price              float64   `json:"price"`
	TransactionDate    time.Time `json:"transaction_date" binding:"required"`
	Brokerage          float64   `json:"brokerage"`
	TransactionCharges float64   `json:"transaction_charges"`
	StampDuty          float64   `json:"stamp_duty"`
	Segment            string    `json:"segment"`
	STT                string    `json:"stt"`
	Exchange           string    `json:"exchange"`
}

func rebuildICICIDirectLedger(db *gorm.DB, userID uint, items []ledgerRebuildItem) error {
	source := models.SourceICICIDirect
	ordered := append([]ledgerRebuildItem(nil), items...)
	sort.SliceStable(ordered, func(i, j int) bool {
		ti, tj := ordered[i].TransactionDate, ordered[j].TransactionDate
		if !ti.Equal(tj) {
			return ti.Before(tj)
		}
		iBuy := strings.EqualFold(strings.TrimSpace(ordered[i].Action), "buy")
		jBuy := strings.EqualFold(strings.TrimSpace(ordered[j].Action), "buy")
		if iBuy != jBuy {
			return iBuy
		}
		return false
	})

	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("user_id = ? AND source = ?", userID, source).
			Delete(&models.UserStockTransaction{}).Error; err != nil {
			return err
		}
		if err := tx.Model(&models.UserStock{}).
			Where("user_id = ? AND source = ?", userID, source).
			Updates(map[string]interface{}{
				"quantity":      0,
				"avg_buy_price": 0,
			}).Error; err != nil {
			return err
		}

		for _, item := range ordered {
			symbol := strings.ToUpper(strings.TrimSpace(item.Symbol))
			action := strings.ToLower(strings.TrimSpace(item.Action))
			if symbol == "" || item.Quantity <= 1e-9 {
				continue
			}
			var txType models.TransactionType
			switch action {
			case "buy":
				txType = models.TransactionTypeBuy
			case "sell":
				txType = models.TransactionTypeSell
			default:
				return fmt.Errorf("%s: unsupported action %q", symbol, item.Action)
			}

			var stock models.Stock
			if err := tx.Where("symbol = ?", symbol).First(&stock).Error; err != nil {
				return fmt.Errorf("%s: stock not found", symbol)
			}

			opts := applyStockTxnOpts{
				AllowZeroBuyPrice: txType == models.TransactionTypeBuy,
				Origin:            models.TxOriginICICITransactions,
				Extras: &stockTxnExtras{
					Brokerage:          item.Brokerage,
					TransactionCharges: item.TransactionCharges,
					StampDuty:          item.StampDuty,
					Segment:            strings.TrimSpace(item.Segment),
					STT:                strings.TrimSpace(item.STT),
					Exchange:           strings.TrimSpace(item.Exchange),
				},
			}
			if err := validateApplyStockTxn(txType, item.Quantity, item.Price, opts); err != nil {
				return fmt.Errorf("%s on %s: %w", symbol, item.TransactionDate.Format("02-Jan-2006"), err)
			}
			if _, _, err := applyStockTransactionOnTx(
				tx, userID, stock.ID, txType, item.Quantity, item.Price, item.TransactionDate, source, opts,
			); err != nil {
				return fmt.Errorf("%s on %s: %w", symbol, item.TransactionDate.Format("02-Jan-2006"), err)
			}
		}
		return nil
	})
}

// yahooPriceForUpload returns Yahoo last price when available; 0 if fetch fails.
func yahooPriceForUpload(symbol string) float64 {
	symbol = strings.TrimSpace(symbol)
	if symbol == "" {
		return 0
	}
	price, err := fetchYahooFinancePrice(symbol)
	if err != nil || price <= 0 {
		return 0
	}
	return price
}

// applyUploadPosition sets User_Stocks from file qty/avg and writes a delta buy/sell to the ledger.
// Snapshot uploads omit transaction_date (nil). New inserts leave last_* blank. Qty updates set last_* from Yahoo
// (never file avg) and only set last_* dates when txDate is present.
// When watchList is true and fileQty > 0, qty is forced to 1 and last_* use avg vs currentPrice.
func applyUploadPosition(
	db *gorm.DB,
	userID, stockID uint,
	symbol, source string,
	fileQty, avgBuyPrice float64,
	txDate *time.Time,
	watchList bool,
	currentPrice float64,
) (models.UserStock, *models.UserStockTransaction, error) {
	source = normalizeSource(source)
	if fileQty < 0 {
		return models.UserStock{}, nil, fmt.Errorf("quantity cannot be negative")
	}

	if watchList && fileQty > 0 {
		return applyWatchListUploadPosition(db, userID, stockID, source, avgBuyPrice, txDate, currentPrice)
	}

	var pos models.UserStock
	err := db.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).First(&pos).Error
	if err != nil && err != gorm.ErrRecordNotFound {
		return models.UserStock{}, nil, err
	}

	var deltaTxn *models.UserStockTransaction

	if err == gorm.ErrRecordNotFound {
		if fileQty > 0 {
			ledger := models.UserStockTransaction{
				UserID:           userID,
				StockID:          stockID,
				Source:           source,
				Type:             models.TransactionTypeBuy,
				Quantity:         fileQty,
				OriginalQuantity: fileQty,
				Price:            avgBuyPrice,
				TransactionDate:  cloneTime(txDate),
				Origin:           models.TxOriginSnapshot,
			}
			if err := db.Create(&ledger).Error; err != nil {
				return models.UserStock{}, nil, err
			}
			deltaTxn = &ledger
			// last_* stay blank on first insert — never copy file avg into them.
			pos = models.UserStock{
				UserID:      userID,
				StockID:     stockID,
				Source:      source,
				Quantity:    fileQty,
				AvgBuyPrice: avgBuyPrice,
			}
			if err := db.Create(&pos).Error; err != nil {
				return models.UserStock{}, nil, err
			}
			return pos, deltaTxn, nil
		}
		return models.UserStock{}, nil, nil
	}

	oldQty := pos.Quantity
	delta := fileQty - oldQty
	yahooPrice := 0.0
	if delta > 1e-9 || delta < -1e-9 {
		yahooPrice = yahooPriceForUpload(symbol)
	}

	if delta > 1e-9 {
		ledgerPrice := yahooPrice
		if ledgerPrice <= 0 {
			ledgerPrice = avgBuyPrice
		}
		ledger := models.UserStockTransaction{
			UserID:           userID,
			StockID:          stockID,
			Source:           source,
			Type:             models.TransactionTypeBuy,
			Quantity:         delta,
			OriginalQuantity: delta,
			Price:            ledgerPrice,
			TransactionDate:  cloneTime(txDate),
			Origin:           models.TxOriginSnapshot,
		}
		if err := db.Create(&ledger).Error; err != nil {
			return models.UserStock{}, nil, err
		}
		deltaTxn = &ledger
		if yahooPrice > 0 {
			pos.LastBuyPrice = yahooPrice
			pos.LastBuyDate = cloneTime(txDate)
		}
		// Yahoo failed: leave last_buy_* blank/unchanged — never use file avg.
	} else if delta < -1e-9 {
		sellQty := -delta
		ledgerPrice := yahooPrice
		if ledgerPrice <= 0 {
			ledgerPrice = avgBuyPrice
			if ledgerPrice <= 0 {
				ledgerPrice = pos.AvgBuyPrice
			}
		}
		ledger := models.UserStockTransaction{
			UserID:           userID,
			StockID:          stockID,
			Source:           source,
			Type:             models.TransactionTypeSell,
			Quantity:         sellQty,
			OriginalQuantity: sellQty,
			Price:            ledgerPrice,
			TransactionDate:  cloneTime(txDate),
			Origin:           models.TxOriginSnapshot,
		}
		if err := db.Create(&ledger).Error; err != nil {
			return models.UserStock{}, nil, err
		}
		deltaTxn = &ledger
		if err := applyFIFOSell(db, userID, stockID, source, sellQty, ledgerPrice, saleStamp(txDate)); err != nil {
			return models.UserStock{}, nil, err
		}
		if yahooPrice > 0 {
			pos.LastSalePrice = yahooPrice
			pos.LastSaleDate = cloneTime(txDate)
		}
	}

	pos.Quantity = fileQty
	if fileQty > 0 {
		pos.AvgBuyPrice = avgBuyPrice
	} else {
		pos.AvgBuyPrice = 0
	}
	if err := db.Save(&pos).Error; err != nil {
		return models.UserStock{}, nil, err
	}
	return pos, deltaTxn, nil
}

// applyWatchListUploadPosition forces qty=1 and sets last_buy/last_sale from avg vs current.
func applyWatchListUploadPosition(
	db *gorm.DB,
	userID, stockID uint,
	source string,
	avgBuyPrice float64,
	txDate *time.Time,
	currentPrice float64,
) (models.UserStock, *models.UserStockTransaction, error) {
	source = normalizeSource(source)

	var buys []models.UserStockTransaction
	if err := db.Where(
		"user_id = ? AND stock_id = ? AND source = ? AND type = ? AND quantity > 0",
		userID, stockID, source, models.TransactionTypeBuy,
	).Find(&buys).Error; err != nil {
		return models.UserStock{}, nil, err
	}
	for i := range buys {
		buys[i].Quantity = 0
		if err := db.Save(&buys[i]).Error; err != nil {
			return models.UserStock{}, nil, err
		}
	}

	ledger := models.UserStockTransaction{
		UserID:           userID,
		StockID:          stockID,
		Source:           source,
		Type:             models.TransactionTypeBuy,
		Quantity:         1,
		OriginalQuantity: 1,
		Price:            avgBuyPrice,
		TransactionDate:  cloneTime(txDate),
		Origin:           models.TxOriginSnapshot,
	}
	if err := db.Create(&ledger).Error; err != nil {
		return models.UserStock{}, nil, err
	}

	var pos models.UserStock
	err := db.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).First(&pos).Error
	if err != nil && err != gorm.ErrRecordNotFound {
		return models.UserStock{}, nil, err
	}
	creating := err == gorm.ErrRecordNotFound
	if creating {
		pos = models.UserStock{
			UserID:  userID,
			StockID: stockID,
			Source:  source,
		}
	}

	pos.Quantity = 1
	pos.AvgBuyPrice = avgBuyPrice
	if currentPrice > 0 && avgBuyPrice > 0 {
		if avgBuyPrice < currentPrice {
			pos.LastBuyPrice = avgBuyPrice
			pos.LastBuyDate = cloneTime(txDate)
		} else if avgBuyPrice > currentPrice {
			pos.LastSalePrice = avgBuyPrice
			pos.LastSaleDate = cloneTime(txDate)
		}
	}

	if creating {
		if err := db.Create(&pos).Error; err != nil {
			return models.UserStock{}, nil, err
		}
	} else if err := db.Save(&pos).Error; err != nil {
		return models.UserStock{}, nil, err
	}
	return pos, &ledger, nil
}
