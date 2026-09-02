package handlers

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"financetracker/models"

	"gorm.io/gorm"
)

// applyUploadMFPosition sets User_MutualFunds from file qty/avg NAV and writes a
// delta buy/sell to User_MutualFund_Transactions. Snapshot uploads omit
// transaction_date (nil) and do not set PurchaseDate on the holding.
func applyUploadMFPosition(
	db *gorm.DB,
	userID uint,
	isin, schemeCode, schemeName, sourceSchemeName, source string,
	fileQty, avgNAV, currentNAV float64,
	txDate *time.Time,
) (models.MutualFund, *models.UserMutualFundTransaction, error) {
	source = normalizeSource(source)
	isin = strings.ToUpper(strings.TrimSpace(isin))
	sourceSchemeName = strings.TrimSpace(sourceSchemeName)
	if fileQty < 0 {
		return models.MutualFund{}, nil, fmt.Errorf("quantity cannot be negative")
	}

	var pos models.MutualFund
	err := findUserMutualFund(db, userID, source, isin, sourceSchemeName, &pos)
	if err != nil && err != gorm.ErrRecordNotFound {
		return models.MutualFund{}, nil, err
	}

	var deltaTxn *models.UserMutualFundTransaction

	if err == gorm.ErrRecordNotFound {
		if fileQty > 0 {
			ledger := models.UserMutualFundTransaction{
				UserID:           userID,
				ISIN:             isin,
				SourceSchemeName: sourceSchemeName,
				Source:           source,
				Type:             models.TransactionTypeBuy,
				Quantity:         fileQty,
				OriginalQuantity: fileQty,
				Price:            avgNAV,
				TransactionDate:  cloneTime(txDate),
				Origin:           models.TxOriginSnapshot,
			}
			if err := db.Create(&ledger).Error; err != nil {
				return models.MutualFund{}, nil, err
			}
			deltaTxn = &ledger
			pos = models.MutualFund{
				UserID:           userID,
				ISIN:             isin,
				SchemeCode:       schemeCode,
				SchemeName:       schemeName,
				SourceSchemeName: sourceSchemeName,
				Source:           source,
				Quantity:         fileQty,
				NAV:              avgNAV,
				CurrentNAV:       currentNAV,
				// PurchaseDate left zero — snapshot files have no transaction dates.
			}
			if err := db.Create(&pos).Error; err != nil {
				return models.MutualFund{}, nil, err
			}
			return pos, deltaTxn, nil
		}
		return models.MutualFund{}, nil, nil
	}

	oldQty := pos.Quantity
	delta := fileQty - oldQty
	ledgerPrice := currentNAV
	if ledgerPrice <= 0 {
		ledgerPrice = avgNAV
	}

	if delta > 1e-9 {
		if ledgerPrice <= 0 {
			ledgerPrice = avgNAV
		}
		ledger := models.UserMutualFundTransaction{
			UserID:           userID,
			ISIN:             isin,
			SourceSchemeName: firstNonEmpty(sourceSchemeName, pos.SourceSchemeName),
			Source:           source,
			Type:             models.TransactionTypeBuy,
			Quantity:         delta,
			OriginalQuantity: delta,
			Price:            ledgerPrice,
			TransactionDate:  cloneTime(txDate),
			Origin:           models.TxOriginSnapshot,
		}
		if err := db.Create(&ledger).Error; err != nil {
			return models.MutualFund{}, nil, err
		}
		deltaTxn = &ledger
	} else if delta < -1e-9 {
		sellQty := -delta
		if ledgerPrice <= 0 {
			ledgerPrice = avgNAV
			if ledgerPrice <= 0 {
				ledgerPrice = pos.NAV
			}
		}
		ledger := models.UserMutualFundTransaction{
			UserID:           userID,
			ISIN:             firstNonEmpty(isin, pos.ISIN),
			SourceSchemeName: firstNonEmpty(sourceSchemeName, pos.SourceSchemeName),
			Source:           source,
			Type:             models.TransactionTypeSell,
			Quantity:         sellQty,
			OriginalQuantity: sellQty,
			Price:            ledgerPrice,
			TransactionDate:  cloneTime(txDate),
			Origin:           models.TxOriginSnapshot,
		}
		if err := db.Create(&ledger).Error; err != nil {
			return models.MutualFund{}, nil, err
		}
		deltaTxn = &ledger
		if err := applyMFFIFOSell(
			db, userID, firstNonEmpty(isin, strings.ToUpper(strings.TrimSpace(pos.ISIN))),
			firstNonEmpty(sourceSchemeName, pos.SourceSchemeName), source,
			sellQty, ledgerPrice, saleStamp(txDate),
		); err != nil {
			return models.MutualFund{}, nil, err
		}
	}

	if isin != "" {
		pos.ISIN = isin
	}
	if schemeCode != "" {
		pos.SchemeCode = schemeCode
	}
	if schemeName != "" {
		pos.SchemeName = schemeName
	}
	if sourceSchemeName != "" {
		pos.SourceSchemeName = sourceSchemeName
	}
	pos.Quantity = fileQty
	if fileQty > 0 {
		pos.NAV = avgNAV
	} else {
		pos.NAV = 0
	}
	if currentNAV > 0 {
		pos.CurrentNAV = currentNAV
	}
	// Do not overwrite PurchaseDate on reupload — holdings files have no dates.
	if err := db.Save(&pos).Error; err != nil {
		return models.MutualFund{}, nil, err
	}
	return pos, deltaTxn, nil
}

func findUserMutualFund(db *gorm.DB, userID uint, source, isin, sourceSchemeName string, out *models.MutualFund) error {
	if isin != "" {
		return db.Where("user_id = ? AND source = ? AND UPPER(isin) = ?", userID, source, isin).First(out).Error
	}
	return db.Where(
		"user_id = ? AND source = ? AND (isin IS NULL OR TRIM(isin) = '') AND LOWER(TRIM(source_scheme_name)) = ?",
		userID, source, strings.ToLower(strings.TrimSpace(sourceSchemeName)),
	).First(out).Error
}

func loadOpenMFBuys(db *gorm.DB, userID uint, isin, sourceSchemeName, source string) ([]models.UserMutualFundTransaction, error) {
	var buys []models.UserMutualFundTransaction
	q := db.Where(
		"user_id = ? AND source = ? AND type = ? AND quantity > 0",
		userID, source, models.TransactionTypeBuy,
	)
	isin = strings.ToUpper(strings.TrimSpace(isin))
	if isin != "" {
		q = q.Where("UPPER(isin) = ?", isin)
	} else {
		q = q.Where(
			"(isin IS NULL OR TRIM(isin) = '') AND LOWER(TRIM(source_scheme_name)) = ?",
			strings.ToLower(strings.TrimSpace(sourceSchemeName)),
		)
	}
	if err := q.Find(&buys).Error; err != nil {
		return nil, err
	}
	return buys, nil
}

func sortMFLotsFIFO(lots []models.UserMutualFundTransaction) {
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

func applyMFFIFOSell(
	db *gorm.DB,
	userID uint,
	isin, sourceSchemeName, source string,
	sellQty, salePrice float64,
	saleDate time.Time,
) error {
	buys, err := loadOpenMFBuys(db, userID, isin, sourceSchemeName, source)
	if err != nil {
		return err
	}
	sortMFLotsFIFO(buys)

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

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

// replaceManualAddMFPosition zeros open Manual Add buy lots for the fund key and
// creates a single buy lot at qty/NAV (mirrors stock replaceManualAddPosition).
func replaceManualAddMFPosition(
	db *gorm.DB,
	userID uint,
	isin, sourceSchemeName string,
	quantity, nav float64,
	txDate *time.Time,
) error {
	isin = strings.ToUpper(strings.TrimSpace(isin))
	sourceSchemeName = strings.TrimSpace(sourceSchemeName)
	source := models.SourceManualAdd

	buys, err := loadOpenMFBuys(db, userID, isin, sourceSchemeName, source)
	if err != nil {
		return err
	}
	for i := range buys {
		buys[i].Quantity = 0
		if err := db.Save(&buys[i]).Error; err != nil {
			return err
		}
	}
	if quantity <= 1e-9 {
		return nil
	}
	ledger := models.UserMutualFundTransaction{
		UserID:           userID,
		ISIN:             isin,
		SourceSchemeName: sourceSchemeName,
		Source:           source,
		Type:             models.TransactionTypeBuy,
		Quantity:         quantity,
		OriginalQuantity: quantity,
		Price:            nav,
		TransactionDate:  cloneTime(txDate),
		Origin:           models.TxOriginUI,
	}
	return db.Create(&ledger).Error
}

func deleteMFTransactionsForHolding(db *gorm.DB, userID uint, isin, sourceSchemeName, source string) error {
	source = normalizeSource(source)
	isin = strings.ToUpper(strings.TrimSpace(isin))
	q := db.Where("user_id = ? AND source = ?", userID, source)
	if isin != "" {
		q = q.Where("UPPER(isin) = ?", isin)
	} else {
		q = q.Where(
			"(isin IS NULL OR TRIM(isin) = '') AND LOWER(TRIM(source_scheme_name)) = ?",
			strings.ToLower(strings.TrimSpace(sourceSchemeName)),
		)
	}
	return q.Delete(&models.UserMutualFundTransaction{}).Error
}
