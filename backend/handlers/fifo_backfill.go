package handlers

import (
	"fmt"
	"log"

	"financetracker/models"

	"gorm.io/gorm"
)

// BackfillOriginalQuantityAndFIFO sets original_quantity from quantity where missing,
// fixes unsold buys so remaining equals bought qty, and (once per group) resets buy
// lots then replays sells with FIFO split + sale_price/sale_date.
// Groups that already have a stamped sale_price on a buy lot are skipped so splits
// are not duplicated on later startups.
func BackfillOriginalQuantityAndFIFO(db *gorm.DB) error {
	if err := db.Exec(`
		UPDATE "User_Stock_Transactions"
		SET original_quantity = quantity
		WHERE original_quantity = 0 AND quantity > 0
	`).Error; err != nil {
		return fmt.Errorf("backfill original_quantity: %w", err)
	}

	type groupKey struct {
		UserID  uint
		StockID uint
		Source  string
	}
	var keys []groupKey
	if err := db.Model(&models.UserStockTransaction{}).
		Select("user_id, stock_id, source").
		Group("user_id, stock_id, source").
		Scan(&keys).Error; err != nil {
		return err
	}

	for _, key := range keys {
		if err := backfillFIFOGroup(db, key.UserID, key.StockID, key.Source); err != nil {
			return err
		}
	}

	log.Println("Backfilled original_quantity and FIFO lot sale matches on User_Stock_Transactions")
	return nil
}

func backfillFIFOGroup(db *gorm.DB, userID, stockID uint, source string) error {
	var txs []models.UserStockTransaction
	if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stockID, source).
		Find(&txs).Error; err != nil {
		return err
	}
	sortLotsFIFO(txs)

	hasSell := false
	hasStampedSale := false
	for _, tx := range txs {
		if tx.Type == models.TransactionTypeSell {
			hasSell = true
		}
		if tx.Type == models.TransactionTypeBuy && tx.SalePrice > 1e-9 && tx.SaleDate != nil {
			hasStampedSale = true
		}
	}

	if !hasSell {
		for i := range txs {
			if txs[i].Type != models.TransactionTypeBuy {
				continue
			}
			if txs[i].SalePrice > 1e-9 && txs[i].SaleDate != nil {
				continue
			}
			orig := txs[i].OriginalQuantity
			if orig <= 0 {
				orig = txs[i].Quantity
			}
			if txs[i].Quantity != orig || txs[i].OriginalQuantity != orig {
				txs[i].OriginalQuantity = orig
				txs[i].Quantity = orig
				if err := db.Save(&txs[i]).Error; err != nil {
					return err
				}
			}
		}
		return nil
	}

	if hasStampedSale {
		return nil
	}

	for i := range txs {
		if txs[i].Type != models.TransactionTypeBuy {
			continue
		}
		orig := txs[i].OriginalQuantity
		if orig <= 0 {
			orig = txs[i].Quantity
		}
		txs[i].OriginalQuantity = orig
		txs[i].Quantity = orig
		txs[i].SalePrice = 0
		txs[i].SaleDate = nil
		if err := db.Save(&txs[i]).Error; err != nil {
			return err
		}
	}

	for i := range txs {
		tx := txs[i]
		if tx.Type != models.TransactionTypeSell {
			continue
		}
		if tx.OriginalQuantity <= 0 {
			tx.OriginalQuantity = tx.Quantity
			if err := db.Save(&tx).Error; err != nil {
				return err
			}
		}
		if err := applyFIFOSell(db, userID, stockID, source, tx.Quantity, tx.Price, saleStamp(tx.TransactionDate)); err != nil {
			log.Printf("Warning: FIFO sale-match backfill user=%d stock=%d source=%s: %v",
				userID, stockID, source, err)
			return err
		}
	}

	if _, err := recomputeUserStock(db, userID, stockID, source); err != nil {
		log.Printf("Warning: recompute after FIFO backfill user=%d stock=%d source=%s: %v",
			userID, stockID, source, err)
	}
	return nil
}
