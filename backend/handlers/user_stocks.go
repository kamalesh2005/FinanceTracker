package handlers

import (
	"errors"
	"fmt"
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

// RecomputeUserStock rebuilds User_Stocks for user+source+stock from open buy lots.
func RecomputeUserStock(db *gorm.DB, userID, stockID uint, source string) (models.UserStock, error) {
	return recomputeUserStock(db, userID, stockID, source)
}

// recomputeUserStock rebuilds User_Stocks from remaining buy lot quantities only (ignores sells for avg/qty).
func recomputeUserStock(db *gorm.DB, userID, stockID uint, source string) (models.UserStock, error) {
	source = normalizeSource(source)

	var txs []models.UserStockTransaction
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).
		Order("transaction_date ASC, id ASC").
		Find(&txs).Error; err != nil {
		return models.UserStock{}, err
	}

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
			d := tx.TransactionDate
			lastBuyDate = &d
		case models.TransactionTypeSell:
			lastSalePrice = tx.Price
			d := tx.TransactionDate
			lastSaleDate = &d
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

// applyFIFOSell reduces remaining Quantity on oldest buy lots (does not change OriginalQuantity).
func applyFIFOSell(db *gorm.DB, userID, stockID uint, source string, sellQty float64) error {
	var buys []models.UserStockTransaction
	if err := db.Where(
		"user_id = ? AND stock_id = ? AND source = ? AND type = ? AND quantity > 0",
		userID, stockID, source, models.TransactionTypeBuy,
	).Order("transaction_date ASC, id ASC").Find(&buys).Error; err != nil {
		return err
	}

	remaining := sellQty
	for i := range buys {
		if remaining < 1e-9 {
			break
		}
		take := buys[i].Quantity
		if take > remaining {
			take = remaining
		}
		buys[i].Quantity -= take
		if buys[i].Quantity < 1e-9 {
			buys[i].Quantity = 0
		}
		if err := db.Save(&buys[i]).Error; err != nil {
			return err
		}
		remaining -= take
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
	if quantity <= 0 {
		return fmt.Errorf("quantity must be greater than 0")
	}
	if price <= 0 {
		return fmt.Errorf("price must be greater than 0")
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
		TransactionDate:  txDate,
	}
	if err := db.Create(&ledger).Error; err != nil {
		return err
	}

	pos, err := recomputeUserStock(db, userID, stockID, models.SourceManualAdd)
	if err != nil {
		return err
	}
	clearPriceThresholds(&pos)
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
	source = normalizeSource(source)
	if quantity <= 0 {
		return models.UserStockTransaction{}, models.UserStock{}, fmt.Errorf("quantity must be greater than 0")
	}
	if price <= 0 {
		return models.UserStockTransaction{}, models.UserStock{}, fmt.Errorf("price must be greater than 0")
	}

	var ledger models.UserStockTransaction
	var pos models.UserStock
	err := db.Transaction(func(tx *gorm.DB) error {
		if txType == models.TransactionTypeSell {
			var holding models.UserStock
			err := tx.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).First(&holding).Error
			if err == gorm.ErrRecordNotFound || holding.Quantity < quantity-1e-9 {
				available := 0.0
				if err == nil {
					available = holding.Quantity
				}
				return fmt.Errorf("%w: available %.2f, requested %.2f", errInsufficientQuantity, available, quantity)
			}
			if err != nil && err != gorm.ErrRecordNotFound {
				return err
			}
		}

		ledger = models.UserStockTransaction{
			UserID:           userID,
			StockID:          stockID,
			Source:           source,
			Type:             txType,
			Quantity:         quantity,
			OriginalQuantity: quantity,
			Price:            price,
			TransactionDate:  txDate,
		}
		if err := tx.Create(&ledger).Error; err != nil {
			return err
		}

		if txType == models.TransactionTypeSell {
			if err := applyFIFOSell(tx, userID, stockID, source, quantity); err != nil {
				return err
			}
		}

		var recomputeErr error
		pos, recomputeErr = recomputeUserStock(tx, userID, stockID, source)
		if recomputeErr != nil {
			return recomputeErr
		}
		clearPriceThresholds(&pos)
		return tx.Save(&pos).Error
	})
	if err != nil {
		return models.UserStockTransaction{}, models.UserStock{}, err
	}
	return ledger, pos, nil
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
// New inserts leave last_* blank. Qty updates set last_* from Yahoo (never file avg).
// When watchList is true and fileQty > 0, qty is forced to 1 and last_* use avg vs currentPrice.
func applyUploadPosition(
	db *gorm.DB,
	userID, stockID uint,
	symbol, source string,
	fileQty, avgBuyPrice float64,
	txDate time.Time,
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
				TransactionDate:  txDate,
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
			TransactionDate:  txDate,
		}
		if err := db.Create(&ledger).Error; err != nil {
			return models.UserStock{}, nil, err
		}
		deltaTxn = &ledger
		if yahooPrice > 0 {
			pos.LastBuyPrice = yahooPrice
			d := txDate
			pos.LastBuyDate = &d
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
			TransactionDate:  txDate,
		}
		if err := db.Create(&ledger).Error; err != nil {
			return models.UserStock{}, nil, err
		}
		deltaTxn = &ledger
		if err := applyFIFOSell(db, userID, stockID, source, sellQty); err != nil {
			return models.UserStock{}, nil, err
		}
		if yahooPrice > 0 {
			pos.LastSalePrice = yahooPrice
			d := txDate
			pos.LastSaleDate = &d
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
	txDate time.Time,
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
		TransactionDate:  txDate,
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
		d := txDate
		if avgBuyPrice < currentPrice {
			pos.LastBuyPrice = avgBuyPrice
			pos.LastBuyDate = &d
		} else if avgBuyPrice > currentPrice {
			pos.LastSalePrice = avgBuyPrice
			pos.LastSaleDate = &d
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
