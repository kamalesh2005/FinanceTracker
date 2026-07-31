package jobs

import (
	"log"
	"sync/atomic"
	"time"
)

// YahooFullRefresher is the subset of Handler used by the daily Yahoo cron.
type YahooFullRefresher interface {
	RefreshAllStockPricesAndTrends() error
}

// StartDailyYahooRefreshCron runs RefreshAllStockPricesAndTrends once per day
// at 06:00 Asia/Kolkata. Safe to call once from main; runs in a background
// goroutine.
func StartDailyYahooRefreshCron(refresher YahooFullRefresher) {
	go runDailyYahooRefreshCron(refresher)
}

func runDailyYahooRefreshCron(refresher YahooFullRefresher) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("DailyYahooRefreshCron: failed to load Asia/Kolkata: %v; using FixedZone IST", err)
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}

	log.Printf("DailyYahooRefreshCron: scheduler started (daily 06:00 IST)")

	var running atomic.Bool
	for {
		now := time.Now().In(ist)
		next := nextDailySixAM(now)
		wait := time.Until(next)
		if wait > 0 {
			log.Printf("DailyYahooRefreshCron: next run at %s (in %s)", next.Format(time.RFC3339), wait.Round(time.Second))
			time.Sleep(wait)
		}

		if !running.CompareAndSwap(false, true) {
			log.Printf("DailyYahooRefreshCron: previous run still in progress; skipping")
			continue
		}
		func() {
			defer running.Store(false)
			log.Printf("DailyYahooRefreshCron: tick at %s", time.Now().In(ist).Format(time.RFC3339))
			if err := refresher.RefreshAllStockPricesAndTrends(); err != nil {
				log.Printf("DailyYahooRefreshCron: FAIL: %v", err)
			} else {
				log.Printf("DailyYahooRefreshCron: completed")
			}
		}()
	}
}

// nextDailySixAM returns the next 06:00 IST at or after now (if now is exactly
// 06:00:00, returns now).
func nextDailySixAM(now time.Time) time.Time {
	ist := now.Location()
	todaySix := time.Date(now.Year(), now.Month(), now.Day(), 6, 0, 0, 0, ist)
	if !now.After(todaySix) {
		return todaySix
	}
	return todaySix.AddDate(0, 0, 1)
}
