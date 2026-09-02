package xirr

import (
	"math"
	"testing"
	"time"
)

func date(y int, m time.Month, d int) time.Time {
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

func datePtr(y int, m time.Month, d int) *time.Time {
	t := date(y, m, d)
	return &t
}

func TestCalculate_OneYearTenPercent(t *testing.T) {
	// 2019-01-01 to 2020-01-01 is 365 days → exactly 10%.
	rate, ok := Calculate([]CashFlow{
		{Date: date(2019, 1, 1), Amount: -1000},
		{Date: date(2020, 1, 1), Amount: 1100},
	})
	if !ok {
		t.Fatal("expected XIRR to converge")
	}
	if math.Abs(rate-0.10) > 1e-6 {
		t.Fatalf("rate=%v want 0.10", rate)
	}
}

func TestCalculate_SameSignRejected(t *testing.T) {
	if _, ok := Calculate([]CashFlow{
		{Date: date(2019, 1, 1), Amount: -100},
		{Date: date(2020, 1, 1), Amount: -50},
	}); ok {
		t.Fatal("expected failure when all cash flows are negative")
	}
}

func TestFlowsFromLots_PartialSellAndRemainder(t *testing.T) {
	sale := date(2020, 1, 1)
	asOf := date(2021, 1, 1)
	flows := FlowsFromLots([]Lot{
		{
			Quantity:         0,
			OriginalQuantity: 4,
			Price:            100,
			TransactionDate:  datePtr(2019, 1, 1),
			SalePrice:        150,
			SaleDate:         &sale,
		},
		{
			Quantity:         6,
			OriginalQuantity: 6,
			Price:            100,
			TransactionDate:  datePtr(2019, 1, 1),
			CurrentPrice:     120,
		},
	}, asOf)

	if len(flows) != 4 {
		t.Fatalf("flows=%d want 4: %+v", len(flows), flows)
	}
	sum := 0.0
	for _, f := range flows {
		sum += f.Amount
	}
	// -400 + 600 + -600 + 720 = 320
	if math.Abs(sum-320) > 1e-9 {
		t.Fatalf("sum=%v want 320", sum)
	}

	rate, ok := Calculate(flows)
	if !ok {
		t.Fatal("expected XIRR to converge")
	}
	if rate <= 0 {
		t.Fatalf("expected positive XIRR, got %v", rate)
	}
}

func TestFlowsFromLots_SkipsZeroedLotsWithoutSale(t *testing.T) {
	asOf := date(2021, 1, 1)
	flows := FlowsFromLots([]Lot{
		{
			Quantity:         0,
			OriginalQuantity: 10,
			Price:            100,
			TransactionDate:  datePtr(2019, 1, 1),
		},
		{
			Quantity:         1,
			OriginalQuantity: 1,
			Price:            50,
			TransactionDate:  datePtr(2020, 1, 1),
			CurrentPrice:     60,
		},
	}, asOf)
	if len(flows) != 2 {
		t.Fatalf("flows=%d want 2 (replaced lot skipped): %+v", len(flows), flows)
	}
}

func TestFlowsFromLots_SkipsMissingBuyDate(t *testing.T) {
	sale := date(2020, 1, 1)
	asOf := date(2021, 1, 1)
	flows := FlowsFromLots([]Lot{
		{
			Quantity:         10,
			OriginalQuantity: 10,
			Price:            100,
			CurrentPrice:     120,
		},
		{
			Quantity:         0,
			OriginalQuantity: 4,
			Price:            50,
			SalePrice:        80,
			SaleDate:         &sale,
		},
		{
			Quantity:         2,
			OriginalQuantity: 2,
			Price:            40,
			TransactionDate:  datePtr(2019, 6, 1),
			CurrentPrice:     50,
		},
	}, asOf)
	if len(flows) != 2 {
		t.Fatalf("flows=%d want 2 (undated lots skipped): %+v", len(flows), flows)
	}
}
