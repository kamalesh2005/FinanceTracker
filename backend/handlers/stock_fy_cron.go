package handlers

import (
	"log"
	"math"
	"strings"
	"sync"
	"time"

	"financetracker/dailyclose"
	"financetracker/models"

	"gorm.io/gorm"
)

var (
	stockFYTriggerMu   sync.Mutex
	stockFYTriggerFn   func()
	stockFYRunMu       sync.Mutex
	stockFYRunning     bool
	stockFYPending     bool
)

// RegisterStockFYBackfillTrigger sets the callback invoked when pull_data flips to Y.
func RegisterStockFYBackfillTrigger(fn func()) {
	stockFYTriggerMu.Lock()
	defer stockFYTriggerMu.Unlock()
	stockFYTriggerFn = fn
}

func triggerStockFYBackfill() {
	stockFYTriggerMu.Lock()
	fn := stockFYTriggerFn
	stockFYTriggerMu.Unlock()
	if fn != nil {
		fn()
	}
}

// RequestStockFYBackfill scans pull_data=Y incompletes and backfills missing FY LTPs.
// Concurrent calls coalesce into one extra run after the current finishes.
func (h *Handler) RequestStockFYBackfill() {
	stockFYRunMu.Lock()
	if stockFYRunning {
		stockFYPending = true
		stockFYRunMu.Unlock()
		return
	}
	stockFYRunning = true
	stockFYRunMu.Unlock()

	go func() {
		for {
			h.runStockFYBackfillOnce()
			stockFYRunMu.Lock()
			if !stockFYPending {
				stockFYRunning = false
				stockFYRunMu.Unlock()
				return
			}
			stockFYPending = false
			stockFYRunMu.Unlock()
		}
	}()
}

func (h *Handler) runStockFYBackfillOnce() {
	queue, err := h.BuildStockFYBackfillQueue()
	if err != nil {
		log.Printf("StockFYBackfill: queue FAIL: %v", err)
		return
	}
	if len(queue) == 0 {
		log.Printf("StockFYBackfill: nothing to do")
		return
	}
	log.Printf("StockFYBackfill: queued %d stocks (pull_data=Y incomplete)", len(queue))
	const batchSize = 50
	for i := 0; i < len(queue); i += batchSize {
		end := i + batchSize
		if end > len(queue) {
			end = len(queue)
		}
		ok, fail := h.BackfillStockFYLTPs(queue[i:end])
		log.Printf("StockFYBackfill: batch %d-%d ok=%d fail=%d", i+1, end, ok, fail)
		if end < len(queue) {
			time.Sleep(2 * time.Second) // light pacing vs Yahoo
		}
	}
	log.Printf("StockFYBackfill: finished")
}

// BuildStockFYBackfillQueue returns pull_data=Y stocks with all ltp_fy_* still 0/NULL.
func (h *Handler) BuildStockFYBackfillQueue() ([]models.Stock, error) {
	var incomplete []models.Stock
	if err := h.DB.Where(
		"pull_data = ? AND "+
			"COALESCE(ltp_fy_2020, 0) = 0 AND COALESCE(ltp_fy_2021, 0) = 0 AND "+
			"COALESCE(ltp_fy_2022, 0) = 0 AND COALESCE(ltp_fy_2023, 0) = 0 AND "+
			"COALESCE(ltp_fy_2024, 0) = 0 AND COALESCE(ltp_fy_2025, 0) = 0",
		models.PullDataYes,
	).Order("symbol asc").Find(&incomplete).Error; err != nil {
		return nil, err
	}
	return incomplete, nil
}

// BackfillStockFYLTPs fetches FY-end closes from Yahoo and writes ltp_fy_* columns.
func (h *Handler) BackfillStockFYLTPs(stocks []models.Stock) (ok, fail int) {
	now := time.Now()
	for _, s := range stocks {
		sym := strings.TrimSpace(s.Symbol)
		if sym == "" {
			continue
		}
		ticker := resolveYahooSymbol(sym)
		fy, err := dailyclose.FetchFiscalYearEndCloses(ticker, nil, dailyclose.StockFYLabels)
		if err != nil {
			fail++
			log.Printf("StockFYBackfill: FAIL symbol=%s ticker=%s: %v", sym, ticker, err)
			continue
		}
		updates := map[string]interface{}{"updated_at": now}
		wrote := false
		for _, y := range dailyclose.StockFYLabels {
			if px, okPx := fy[y]; okPx && px > 0 {
				updates[ltpFYColumn(y)] = roundPrice2(px)
				wrote = true
			}
		}
		if !wrote {
			fail++
			log.Printf("StockFYBackfill: no FY closes symbol=%s", sym)
			continue
		}
		if err := h.DB.Model(&models.Stock{}).Where("id = ?", s.ID).Updates(updates).Error; err != nil {
			fail++
			log.Printf("StockFYBackfill: db FAIL symbol=%s: %v", sym, err)
			continue
		}
		ok++
	}
	return ok, fail
}

func ltpFYColumn(fy int) string {
	switch fy {
	case 2020:
		return "ltp_fy_2020"
	case 2021:
		return "ltp_fy_2021"
	case 2022:
		return "ltp_fy_2022"
	case 2023:
		return "ltp_fy_2023"
	case 2024:
		return "ltp_fy_2024"
	case 2025:
		return "ltp_fy_2025"
	default:
		return ""
	}
}

// roundPrice2 rounds a price to 2 decimal places (paisa).
func roundPrice2(v float64) float64 {
	return math.Round(v*100) / 100
}

// RoundExistingStockFYLTPs rounds already-stored FY LTPs to 2 decimals.
func RoundExistingStockFYLTPs(db *gorm.DB) error {
	if db == nil || !db.Migrator().HasTable(&models.Stock{}) {
		return nil
	}
	cols := []string{
		"ltp_fy_2020", "ltp_fy_2021", "ltp_fy_2022",
		"ltp_fy_2023", "ltp_fy_2024", "ltp_fy_2025",
	}
	for _, c := range cols {
		if !db.Migrator().HasColumn(&models.Stock{}, c) {
			continue
		}
		if err := db.Exec(`UPDATE "Global_Stocks" SET ` + c + ` = ROUND((` + c + `)::numeric, 2) WHERE COALESCE(` + c + `, 0) <> 0`).Error; err != nil {
			return err
		}
	}
	log.Printf("RoundExistingStockFYLTPs: rounded ltp_fy_* to 2 decimals")
	return nil
}

func applyStockFYReturns(d *StockWithDetails) {
	if d == nil {
		return
	}
	d.Return2021 = pctReturn(d.LtpFY2020, d.LtpFY2021)
	d.Return2022 = pctReturn(d.LtpFY2021, d.LtpFY2022)
	d.Return2023 = pctReturn(d.LtpFY2022, d.LtpFY2023)
	d.Return2024 = pctReturn(d.LtpFY2023, d.LtpFY2024)
	d.Return2025 = pctReturn(d.LtpFY2024, d.LtpFY2025)
	d.ReturnYTD = pctReturn(d.LtpFY2025, d.CurrentPrice)
}
