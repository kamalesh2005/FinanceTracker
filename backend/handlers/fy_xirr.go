package handlers

import (
	"strings"
	"time"

	"financetracker/models"
	"financetracker/xirr"
)

// FY cutoffs for dashboard Since FY25 / FY26 YTD return adjustments.
var (
	fy25Start = time.Date(2025, time.April, 1, 0, 0, 0, 0, time.UTC)
	fy26Start = time.Date(2026, time.April, 1, 0, 0, 0, 0, time.UTC)
	fy24End   = time.Date(2025, time.March, 31, 0, 0, 0, 0, time.UTC)
	fy25End   = time.Date(2026, time.March, 31, 0, 0, 0, 0, time.UTC)
)

// stockFYPrices holds catalog prices used for FY-adjusted XIRR.
type stockFYPrices struct {
	Current   float64
	LtpFY2024 float64
	LtpFY2025 float64
}

// mfFYPrices holds global MF NAV levels for FY-adjusted XIRR.
type mfFYPrices struct {
	Current   float64
	NavFY2024 float64
	NavFY2025 float64
}

func dateOnlyUTC(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

func buyDateOrNil(t *time.Time) *time.Time {
	if t == nil || t.IsZero() {
		return nil
	}
	d := dateOnlyUTC(*t)
	return &d
}

// simpleReturnFromAdjustedLots is the period return (end/start - 1), not annualized.
// Dashboard FY25+ / FY26 use this so figures match fund-level pctReturn and Nifty YTD.
func simpleReturnFromAdjustedLots(xlots []xirr.Lot, asOf time.Time) *float64 {
	flows := xirr.FlowsFromLots(xlots, asOf)
	invested := 0.0
	returned := 0.0
	for _, f := range flows {
		if f.Amount < -1e-12 {
			invested += -f.Amount
		} else if f.Amount > 1e-12 {
			returned += f.Amount
		}
	}
	if invested <= 1e-12 {
		return nil
	}
	r := (returned - invested) / invested
	return &r
}

// xirrStockSinceFY25 computes by-account FY25 period return with LTP_FY buy substitution.
func xirrStockSinceFY25(lots []models.UserStockTransaction, prices map[uint]stockFYPrices) *float64 {
	xlots := make([]xirr.Lot, 0, len(lots))
	for _, lot := range lots {
		if lot.Type != models.TransactionTypeBuy {
			continue
		}
		px, ok := prices[lot.StockID]
		if !ok || px.LtpFY2025 <= 0 {
			continue // missing FY25 MTM — ignore stock
		}
		buy := buyDateOrNil(lot.TransactionDate)
		if buy != nil && !buy.Before(fy26Start) {
			continue // bought after FY25
		}
		price := lot.Price
		date := buy
		if buy == nil || buy.Before(fy25Start) {
			if px.LtpFY2024 <= 0 {
				continue
			}
			d := fy24End
			date = &d
			price = px.LtpFY2024
		}
		xlots = append(xlots, xirr.Lot{
			Quantity:         lot.Quantity,
			OriginalQuantity: lot.OriginalQuantity,
			Price:            price,
			TransactionDate:  date,
			SalePrice:        lot.SalePrice,
			SaleDate:         lot.SaleDate,
			CurrentPrice:     px.LtpFY2025,
		})
	}
	return simpleReturnFromAdjustedLots(xlots, fy25End)
}

// xirrStockFY26YTD computes by-account FY26 YTD return with LTP_FY buy substitution.
func xirrStockFY26YTD(lots []models.UserStockTransaction, prices map[uint]stockFYPrices, asOf time.Time) *float64 {
	xlots := make([]xirr.Lot, 0, len(lots))
	for _, lot := range lots {
		if lot.Type != models.TransactionTypeBuy {
			continue
		}
		px, ok := prices[lot.StockID]
		if !ok || px.Current <= 0 {
			continue
		}
		buy := buyDateOrNil(lot.TransactionDate)
		price := lot.Price
		date := buy
		if buy == nil || buy.Before(fy26Start) {
			if px.LtpFY2025 <= 0 {
				continue
			}
			d := fy25End
			date = &d
			price = px.LtpFY2025
		}
		xlots = append(xlots, xirr.Lot{
			Quantity:         lot.Quantity,
			OriginalQuantity: lot.OriginalQuantity,
			Price:            price,
			TransactionDate:  date,
			SalePrice:        lot.SalePrice,
			SaleDate:         lot.SaleDate,
			CurrentPrice:     px.Current,
		})
	}
	return simpleReturnFromAdjustedLots(xlots, asOf)
}

func mfLotISIN(lot models.UserMutualFundTransaction) string {
	return strings.ToUpper(strings.TrimSpace(lot.ISIN))
}

// xirrMFSinceFY25 computes by-account FY25 period return from MF buy lots (same rules as stocks).
func xirrMFSinceFY25(lots []models.UserMutualFundTransaction, prices map[string]mfFYPrices) *float64 {
	xlots := make([]xirr.Lot, 0, len(lots))
	for _, lot := range lots {
		if lot.Type != models.TransactionTypeBuy {
			continue
		}
		key := mfLotISIN(lot)
		px, ok := prices[key]
		if !ok || px.NavFY2025 <= 0 {
			continue // missing FY25 MTM — ignore fund
		}
		buy := buyDateOrNil(lot.TransactionDate)
		if buy != nil && !buy.Before(fy26Start) {
			continue // bought after FY25
		}
		price := lot.Price
		date := buy
		if buy == nil || buy.Before(fy25Start) {
			if px.NavFY2024 <= 0 {
				continue
			}
			d := fy24End
			date = &d
			price = px.NavFY2024
		}
		xlots = append(xlots, xirr.Lot{
			Quantity:         lot.Quantity,
			OriginalQuantity: lot.OriginalQuantity,
			Price:            price,
			TransactionDate:  date,
			SalePrice:        lot.SalePrice,
			SaleDate:         lot.SaleDate,
			CurrentPrice:     px.NavFY2025,
		})
	}
	return simpleReturnFromAdjustedLots(xlots, fy25End)
}

// xirrMFFY26YTD computes by-account FY26 YTD return from MF buy lots (same rules as stocks).
func xirrMFFY26YTD(lots []models.UserMutualFundTransaction, prices map[string]mfFYPrices, asOf time.Time) *float64 {
	xlots := make([]xirr.Lot, 0, len(lots))
	for _, lot := range lots {
		if lot.Type != models.TransactionTypeBuy {
			continue
		}
		key := mfLotISIN(lot)
		px, ok := prices[key]
		if !ok || px.Current <= 0 {
			continue
		}
		buy := buyDateOrNil(lot.TransactionDate)
		price := lot.Price
		date := buy
		if buy == nil || buy.Before(fy26Start) {
			if px.NavFY2025 <= 0 {
				continue
			}
			d := fy25End
			date = &d
			price = px.NavFY2025
		}
		xlots = append(xlots, xirr.Lot{
			Quantity:         lot.Quantity,
			OriginalQuantity: lot.OriginalQuantity,
			Price:            price,
			TransactionDate:  date,
			SalePrice:        lot.SalePrice,
			SaleDate:         lot.SaleDate,
			CurrentPrice:     px.Current,
		})
	}
	return simpleReturnFromAdjustedLots(xlots, asOf)
}
