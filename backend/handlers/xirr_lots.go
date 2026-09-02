package handlers

import (
	"time"

	"financetracker/models"
	"financetracker/xirr"
)

func xirrRateFromLots(lots []models.UserStockTransaction, currentByStock map[uint]float64, asOf time.Time) *float64 {
	xlots := make([]xirr.Lot, 0, len(lots))
	for _, lot := range lots {
		if lot.Type != models.TransactionTypeBuy {
			continue
		}
		xlots = append(xlots, xirr.Lot{
			Quantity:         lot.Quantity,
			OriginalQuantity: lot.OriginalQuantity,
			Price:            lot.Price,
			TransactionDate:  lot.TransactionDate,
			SalePrice:        lot.SalePrice,
			SaleDate:         lot.SaleDate,
			CurrentPrice:     currentByStock[lot.StockID],
		})
	}
	rate, ok := xirr.Calculate(xirr.FlowsFromLots(xlots, asOf))
	if !ok {
		return nil
	}
	return &rate
}

func xirrRateFromMFLots(lots []models.UserMutualFundTransaction, currentByISIN map[string]float64, asOf time.Time) *float64 {
	xlots := make([]xirr.Lot, 0, len(lots))
	for _, lot := range lots {
		if lot.Type != models.TransactionTypeBuy {
			continue
		}
		key := mfLotISIN(lot)
		xlots = append(xlots, xirr.Lot{
			Quantity:         lot.Quantity,
			OriginalQuantity: lot.OriginalQuantity,
			Price:            lot.Price,
			TransactionDate:  lot.TransactionDate,
			SalePrice:        lot.SalePrice,
			SaleDate:         lot.SaleDate,
			CurrentPrice:     currentByISIN[key],
		})
	}
	rate, ok := xirr.Calculate(xirr.FlowsFromLots(xlots, asOf))
	if !ok {
		return nil
	}
	return &rate
}
