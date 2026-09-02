package handlers

import (
	"fmt"
	"sort"
	"strings"
	"time"
	"unicode"

	"financetracker/models"

	"gorm.io/gorm"
)

// partialLedgerItem is one trade row from an HDFC / Zerodha / Bulk transactions file.
type partialLedgerItem struct {
	Symbol             string    `json:"symbol"`
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

type resolvedPartialItem struct {
	StockID            uint
	Action             string
	Quantity           float64
	Price              float64
	TransactionDate    time.Time
	Brokerage          float64
	TransactionCharges float64
	StampDuty          float64
	Segment            string
	STT                string
	Exchange           string
}

// normalizeStockNameKey collapses whitespace/case and LTD/LIMITED for name matching.
func normalizeStockNameKey(name string) string {
	name = strings.ToUpper(strings.TrimSpace(name))
	if name == "" {
		return ""
	}
	var b strings.Builder
	prevSpace := false
	for _, r := range name {
		if unicode.IsSpace(r) {
			if !prevSpace {
				b.WriteByte(' ')
				prevSpace = true
			}
			continue
		}
		prevSpace = false
		b.WriteRune(r)
	}
	s := b.String()
	replacer := strings.NewReplacer(
		" LIMITED", "",
		" LTD.", "",
		" LTD", "",
		".", "",
		",", "",
	)
	s = replacer.Replace(s)
	return strings.Join(strings.Fields(s), " ")
}

// loadStockNameIndex loads Global_Stocks once into a normalized-name map (first wins on ties).
func loadStockNameIndex(db *gorm.DB) (map[string]models.Stock, error) {
	var stocks []models.Stock
	if err := db.Find(&stocks).Error; err != nil {
		return nil, err
	}
	idx := make(map[string]models.Stock, len(stocks))
	for i := range stocks {
		key := normalizeStockNameKey(stocks[i].Name)
		if key == "" {
			continue
		}
		if _, exists := idx[key]; exists {
			continue
		}
		idx[key] = stocks[i]
	}
	return idx, nil
}

func lookupStockByNormalizedName(idx map[string]models.Stock, name string) (models.Stock, bool) {
	key := normalizeStockNameKey(name)
	if key == "" {
		return models.Stock{}, false
	}
	stock, ok := idx[key]
	return stock, ok
}

// findStockByNormalizedName looks up Global_Stocks by normalized company name (no create).
// Prefer loadStockNameIndex + lookupStockByNormalizedName when resolving many rows.
func findStockByNormalizedName(db *gorm.DB, name string) (models.Stock, bool, error) {
	idx, err := loadStockNameIndex(db)
	if err != nil {
		return models.Stock{}, false, err
	}
	stock, ok := lookupStockByNormalizedName(idx, name)
	return stock, ok, nil
}

func findStockByISIN(db *gorm.DB, isin string) (models.Stock, bool, error) {
	isin = strings.ToUpper(strings.TrimSpace(isin))
	if isin == "" {
		return models.Stock{}, false, nil
	}
	var stock models.Stock
	err := db.Where("UPPER(TRIM(isin)) = ?", isin).First(&stock).Error
	if err == gorm.ErrRecordNotFound {
		return models.Stock{}, false, nil
	}
	if err != nil {
		return models.Stock{}, false, err
	}
	return stock, true, nil
}

func dayStartUTC(t time.Time) time.Time {
	u := t.UTC()
	return time.Date(u.Year(), u.Month(), u.Day(), 0, 0, 0, 0, time.UTC)
}

func dayEndUTC(t time.Time) time.Time {
	return dayStartUTC(t).Add(24*time.Hour - time.Nanosecond)
}

func sortSellsFIFO(sells []models.UserStockTransaction) {
	sort.SliceStable(sells, func(i, j int) bool {
		ti, tj := sells[i].TransactionDate, sells[j].TransactionDate
		switch {
		case ti == nil && tj == nil:
			return sells[i].ID < sells[j].ID
		case ti == nil:
			return true
		case tj == nil:
			return false
		case !ti.Equal(*tj):
			return ti.Before(*tj)
		default:
			return sells[i].ID < sells[j].ID
		}
	})
}

func mergePartialTradeLedger(db *gorm.DB, userID uint, source string, items []resolvedPartialItem) error {
	source = normalizeSource(source)
	if !models.IsPartialLedgerImportSource(source) {
		return fmt.Errorf("source %q does not support partial ledger merge", source)
	}
	if len(items) == 0 {
		return fmt.Errorf("items cannot be empty")
	}
	origin := models.TxOriginForPartialLedger(source)

	byStock := map[uint][]resolvedPartialItem{}
	for _, item := range items {
		if item.StockID == 0 || item.Quantity <= 1e-9 {
			continue
		}
		action := strings.ToLower(strings.TrimSpace(item.Action))
		if action != "buy" && action != "sell" {
			return fmt.Errorf("unsupported action %q", item.Action)
		}
		if item.TransactionDate.IsZero() {
			return fmt.Errorf("transaction_date is required")
		}
		item.Action = action
		byStock[item.StockID] = append(byStock[item.StockID], item)
	}
	if len(byStock) == 0 {
		return fmt.Errorf("no valid trade rows to merge")
	}

	return db.Transaction(func(tx *gorm.DB) error {
		for stockID, rows := range byStock {
			if err := mergePartialTradeLedgerForStock(tx, userID, stockID, source, origin, rows); err != nil {
				return err
			}
		}
		return nil
	})
}

func mergePartialTradeLedgerForStock(
	tx *gorm.DB,
	userID, stockID uint,
	source, origin string,
	rows []resolvedPartialItem,
) error {
	oldest := dayStartUTC(rows[0].TransactionDate)
	newest := dayEndUTC(rows[0].TransactionDate)
	for _, r := range rows[1:] {
		d0 := dayStartUTC(r.TransactionDate)
		d1 := dayEndUTC(r.TransactionDate)
		if d0.Before(oldest) {
			oldest = d0
		}
		if d1.After(newest) {
			newest = d1
		}
	}

	if err := tx.Where(
		"user_id = ? AND stock_id = ? AND source = ? AND (transaction_date IS NULL OR (transaction_date >= ? AND transaction_date <= ?))",
		userID, stockID, source, oldest, newest,
	).Delete(&models.UserStockTransaction{}).Error; err != nil {
		return err
	}

	// Clear sale stamps and reopen remaining buy lots so FIFO can be reapplied.
	var remainingBuys []models.UserStockTransaction
	if err := tx.Where(
		"user_id = ? AND stock_id = ? AND source = ? AND type = ?",
		userID, stockID, source, models.TransactionTypeBuy,
	).Find(&remainingBuys).Error; err != nil {
		return err
	}
	for i := range remainingBuys {
		orig := remainingBuys[i].OriginalQuantity
		if orig <= 1e-9 {
			orig = remainingBuys[i].Quantity
		}
		remainingBuys[i].Quantity = orig
		remainingBuys[i].OriginalQuantity = orig
		remainingBuys[i].SalePrice = 0
		remainingBuys[i].SaleDate = nil
		if err := tx.Save(&remainingBuys[i]).Error; err != nil {
			return err
		}
	}

	sort.SliceStable(rows, func(i, j int) bool {
		ti, tj := rows[i].TransactionDate, rows[j].TransactionDate
		if !ti.Equal(tj) {
			return ti.Before(tj)
		}
		iBuy := rows[i].Action == "buy"
		jBuy := rows[j].Action == "buy"
		if iBuy != jBuy {
			return iBuy
		}
		return false
	})

	for _, item := range rows {
		txType := models.TransactionTypeBuy
		if item.Action == "sell" {
			txType = models.TransactionTypeSell
		}
		day := dayStartUTC(item.TransactionDate)
		ledger := models.UserStockTransaction{
			UserID:             userID,
			StockID:            stockID,
			Source:             source,
			Type:               txType,
			Quantity:           item.Quantity,
			OriginalQuantity:   item.Quantity,
			Price:              item.Price,
			TransactionDate:    timePtr(day),
			Origin:             origin,
			Brokerage:          item.Brokerage,
			TransactionCharges: item.TransactionCharges,
			StampDuty:          item.StampDuty,
			Segment:            strings.TrimSpace(item.Segment),
			STT:                strings.TrimSpace(item.STT),
			Exchange:           strings.TrimSpace(item.Exchange),
		}
		if err := tx.Create(&ledger).Error; err != nil {
			return err
		}
	}

	var allTxs []models.UserStockTransaction
	if err := tx.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).
		Find(&allTxs).Error; err != nil {
		return err
	}
	buySum := 0.0
	sellSum := 0.0
	for _, row := range allTxs {
		switch row.Type {
		case models.TransactionTypeBuy:
			q := row.OriginalQuantity
			if q <= 1e-9 {
				q = row.Quantity
			}
			buySum += q
		case models.TransactionTypeSell:
			sellSum += row.Quantity
		}
	}
	totalTxnQty := buySum - sellSum

	var pos models.UserStock
	err := tx.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).First(&pos).Error
	posExists := err == nil
	if err != nil && err != gorm.ErrRecordNotFound {
		return err
	}
	existingQty := 0.0
	existingAvg := 0.0
	if posExists {
		existingQty = pos.Quantity
		existingAvg = pos.AvgBuyPrice
	}

	targetQty := existingQty
	if totalTxnQty > existingQty+1e-9 {
		targetQty = totalTxnQty
	}
	if !posExists {
		if totalTxnQty > 1e-9 {
			targetQty = totalTxnQty
		} else {
			targetQty = 0
		}
	}

	gap := targetQty - totalTxnQty
	if gap > 1e-9 {
		pad := models.UserStockTransaction{
			UserID:           userID,
			StockID:          stockID,
			Source:           source,
			Type:             models.TransactionTypeBuy,
			Quantity:         gap,
			OriginalQuantity: gap,
			Price:            0,
			TransactionDate:  nil,
			Origin:           origin,
		}
		if err := tx.Create(&pad).Error; err != nil {
			return err
		}
	}

	var sells []models.UserStockTransaction
	if err := tx.Where(
		"user_id = ? AND stock_id = ? AND source = ? AND type = ?",
		userID, stockID, source, models.TransactionTypeSell,
	).Find(&sells).Error; err != nil {
		return err
	}
	sortSellsFIFO(sells)
	for _, sell := range sells {
		saleDay := saleStamp(sell.TransactionDate)
		if err := applyFIFOSell(tx, userID, stockID, source, sell.Quantity, sell.Price, saleDay); err != nil {
			return fmt.Errorf("stock_id %d FIFO sell: %w", stockID, err)
		}
	}

	return finalizePartialPosition(tx, userID, stockID, source, targetQty, existingAvg)
}

func finalizePartialPosition(
	tx *gorm.DB,
	userID, stockID uint,
	source string,
	targetQty, existingAvg float64,
) error {
	var buys []models.UserStockTransaction
	if err := tx.Where(
		"user_id = ? AND stock_id = ? AND source = ? AND type = ?",
		userID, stockID, source, models.TransactionTypeBuy,
	).Find(&buys).Error; err != nil {
		return err
	}

	hasUndated := false
	openUndatedIdx := -1
	openQty := 0.0
	investedDated := 0.0
	datedOpenQty := 0.0
	for i := range buys {
		if buys[i].TransactionDate == nil {
			hasUndated = true
		}
		if buys[i].Quantity <= 1e-9 {
			continue
		}
		openQty += buys[i].Quantity
		if buys[i].TransactionDate == nil {
			if openUndatedIdx < 0 {
				openUndatedIdx = i
			}
		} else {
			investedDated += buys[i].Price * buys[i].Quantity
			datedOpenQty += buys[i].Quantity
		}
	}

	avg := existingAvg
	if !hasUndated {
		avg = 0
		if openQty > 1e-9 {
			invested := 0.0
			for i := range buys {
				if buys[i].Quantity > 1e-9 {
					invested += buys[i].Price * buys[i].Quantity
				}
			}
			avg = invested / openQty
		}
	} else if openUndatedIdx >= 0 {
		undatedOpen := 0.0
		for i := range buys {
			if buys[i].TransactionDate == nil && buys[i].Quantity > 1e-9 {
				undatedOpen += buys[i].Quantity
			}
		}
		if undatedOpen > 1e-9 {
			// P_u so (investedDated + P_u * undatedOpen) / (datedOpen + undatedOpen) == existingAvg
			totalOpen := datedOpenQty + undatedOpen
			needed := existingAvg*totalOpen - investedDated
			pu := needed / undatedOpen
			if pu < 0 {
				pu = 0
			}
			for i := range buys {
				if buys[i].TransactionDate == nil {
					buys[i].Price = pu
					if err := tx.Model(&buys[i]).Update("price", pu).Error; err != nil {
						return err
					}
				}
			}
			avg = existingAvg
		}
	}

	var lastBuyPrice, lastSalePrice float64
	var lastBuyDate, lastSaleDate *time.Time
	var all []models.UserStockTransaction
	if err := tx.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).
		Find(&all).Error; err != nil {
		return err
	}
	sortLotsFIFO(all)
	for _, row := range all {
		switch row.Type {
		case models.TransactionTypeBuy:
			lastBuyPrice = row.Price
			lastBuyDate = cloneTime(row.TransactionDate)
		case models.TransactionTypeSell:
			lastSalePrice = row.Price
			lastSaleDate = cloneTime(row.TransactionDate)
		}
	}

	qty := targetQty
	if qty < 0 {
		qty = 0
	}
	// Prefer actual open lot total when it diverges slightly after FIFO.
	if openQty > 1e-9 || targetQty <= 1e-9 {
		qty = openQty
	}

	var pos models.UserStock
	err := tx.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).First(&pos).Error
	if err != nil && err != gorm.ErrRecordNotFound {
		return err
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
	clearPriceThresholds(&pos)
	pos.BSHClearDate = nil

	if err == gorm.ErrRecordNotFound {
		return tx.Create(&pos).Error
	}
	return tx.Save(&pos).Error
}
