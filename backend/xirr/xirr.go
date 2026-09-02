package xirr

import (
	"math"
	"sort"
	"time"
)

// CashFlow is a dated amount. Outflows are negative, inflows are positive.
type CashFlow struct {
	Date   time.Time
	Amount float64
}

// Lot is one buy slice used to build XIRR cash flows. Sell ledger rows are ignored.
type Lot struct {
	Quantity         float64
	OriginalQuantity float64
	Price            float64
	TransactionDate  *time.Time
	SalePrice        float64
	SaleDate         *time.Time
	CurrentPrice     float64
}

const (
	qtyEps     = 1e-9
	amountEps  = 1e-12
	npvTol     = 1e-7
	rateTol    = 1e-10
	maxIter    = 100
	minRate    = -0.999999
	daysInYear = 365.0
)

// FlowsFromLots builds cash flows from matched buy lots.
// Sold lots (sale_price set): -buy on buy date, +sale on sale date.
// Open lots: -buy on buy date, +current on asOf.
// Zeroed lots with no sale (replaced holdings) are skipped.
func FlowsFromLots(lots []Lot, asOf time.Time) []CashFlow {
	flows := make([]CashFlow, 0, len(lots)*2)
	for _, lot := range lots {
		if lot.TransactionDate == nil || lot.TransactionDate.IsZero() {
			continue
		}
		sold := lot.SalePrice > amountEps && lot.SaleDate != nil
		open := lot.Quantity > qtyEps
		switch {
		case sold:
			qty := lot.OriginalQuantity
			if qty <= qtyEps {
				qty = lot.Quantity
			}
			if qty <= qtyEps {
				continue
			}
			flows = append(flows,
				CashFlow{Date: *lot.TransactionDate, Amount: -lot.Price * qty},
				CashFlow{Date: *lot.SaleDate, Amount: lot.SalePrice * qty},
			)
		case open:
			qty := lot.Quantity
			flows = append(flows,
				CashFlow{Date: *lot.TransactionDate, Amount: -lot.Price * qty},
			)
			if lot.CurrentPrice > amountEps {
				flows = append(flows, CashFlow{Date: asOf, Amount: lot.CurrentPrice * qty})
			}
		}
	}
	return flows
}

// Calculate returns the Excel-style XIRR (days/365, Newton–Raphson).
// ok is false when there are not both a positive and a negative cash flow, or it does not converge.
func Calculate(flows []CashFlow) (float64, bool) {
	cleaned := make([]CashFlow, 0, len(flows))
	for _, f := range flows {
		if math.Abs(f.Amount) < amountEps {
			continue
		}
		cleaned = append(cleaned, f)
	}
	if len(cleaned) < 2 {
		return 0, false
	}

	hasPos, hasNeg := false, false
	for _, f := range cleaned {
		if f.Amount > amountEps {
			hasPos = true
		} else if f.Amount < -amountEps {
			hasNeg = true
		}
	}
	if !hasPos || !hasNeg {
		return 0, false
	}

	sort.SliceStable(cleaned, func(i, j int) bool {
		return cleaned[i].Date.Before(cleaned[j].Date)
	})
	t0 := cleaned[0].Date

	npv := func(rate float64) float64 {
		sum := 0.0
		for _, f := range cleaned {
			frac := yearFrac(t0, f.Date)
			sum += f.Amount / math.Pow(1+rate, frac)
		}
		return sum
	}
	dnpv := func(rate float64) float64 {
		sum := 0.0
		for _, f := range cleaned {
			frac := yearFrac(t0, f.Date)
			if frac == 0 {
				continue
			}
			sum += -frac * f.Amount / math.Pow(1+rate, frac+1)
		}
		return sum
	}

	rate := 0.1
	for i := 0; i < maxIter; i++ {
		y := npv(rate)
		if math.Abs(y) < npvTol {
			return rate, true
		}
		dy := dnpv(rate)
		if math.Abs(dy) < amountEps {
			break
		}
		next := rate - y/dy
		if next <= minRate {
			next = minRate
		}
		if math.Abs(next-rate) < rateTol {
			return next, math.Abs(npv(next)) < 1e-5
		}
		rate = next
	}
	return 0, false
}

func yearFrac(start, end time.Time) float64 {
	return end.Sub(start).Hours() / 24.0 / daysInYear
}
