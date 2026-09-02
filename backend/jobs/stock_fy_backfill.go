package jobs

import (
	"log"
)

// StockFYBackfiller builds the pull_data=Y incomplete queue and writes FY-end LTPs.
type StockFYBackfiller interface {
	RequestStockFYBackfill()
}

// StartStockFYBackfill runs once after server start for pull_data=Y stocks
// missing FY-end LTPs. Further runs are triggered when pull_data flips to Y.
func StartStockFYBackfill(backfiller StockFYBackfiller) {
	go func() {
		log.Printf("StockFYBackfill: startup request")
		backfiller.RequestStockFYBackfill()
	}()
}
