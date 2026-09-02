package jobs

import (
	"log"
	"sync/atomic"
	"time"
)

// NonHeldEQYahooRefresher is the subset of Handler used by the catalog EQ Yahoo cron.
type NonHeldEQYahooRefresher interface {
	RefreshNonHeldEQCatalogDaily() error
}

// StartDailyNonHeldEQYahooCron runs RefreshNonHeldEQCatalogDaily once per day at
// 02:00 Asia/Kolkata and resumes on startup if today's quota is not yet met.
func StartDailyNonHeldEQYahooCron(refresher NonHeldEQYahooRefresher) {
	go runDailyNonHeldEQYahooCron(refresher)
	maybeResumeNonHeldEQCatalog(refresher)
}

func runDailyNonHeldEQYahooCron(refresher NonHeldEQYahooRefresher) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("DailyNonHeldEQYahooCron: failed to load Asia/Kolkata: %v; using FixedZone IST", err)
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}

	log.Printf("DailyNonHeldEQYahooCron: scheduler started (daily 02:00 IST)")

	var running atomic.Bool
	for {
		now := time.Now().In(ist)
		next := nextDailyTwoAM(now)
		wait := time.Until(next)
		if wait > 0 {
			log.Printf("DailyNonHeldEQYahooCron: next run at %s (in %s)", next.Format(time.RFC3339), wait.Round(time.Second))
			time.Sleep(wait)
		}

		runNonHeldEQCatalog(refresher, &running)
	}
}

func maybeResumeNonHeldEQCatalog(refresher NonHeldEQYahooRefresher) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}
	now := time.Now().In(ist)
	todayTwo := time.Date(now.Year(), now.Month(), now.Day(), 2, 0, 0, 0, ist)
	if !now.After(todayTwo) {
		return
	}
	go func() {
		var running atomic.Bool
		log.Printf("DailyNonHeldEQYahooCron: startup resume at %s", now.Format(time.RFC3339))
		runNonHeldEQCatalog(refresher, &running)
	}()
}

func runNonHeldEQCatalog(refresher NonHeldEQYahooRefresher, running *atomic.Bool) {
	if !running.CompareAndSwap(false, true) {
		log.Printf("DailyNonHeldEQYahooCron: previous run still in progress; skipping")
		return
	}
	func() {
		defer running.Store(false)
		log.Printf("DailyNonHeldEQYahooCron: tick at %s", time.Now().Format(time.RFC3339))
		if err := refresher.RefreshNonHeldEQCatalogDaily(); err != nil {
			log.Printf("DailyNonHeldEQYahooCron: FAIL: %v", err)
		} else {
			log.Printf("DailyNonHeldEQYahooCron: completed")
		}
	}()
}

// nextDailyTwoAM returns the next 02:00 IST at or after now (if now is exactly
// 02:00:00, returns now).
func nextDailyTwoAM(now time.Time) time.Time {
	ist := now.Location()
	todayTwo := time.Date(now.Year(), now.Month(), now.Day(), 2, 0, 0, 0, ist)
	if !now.After(todayTwo) {
		return todayTwo
	}
	return todayTwo.AddDate(0, 0, 1)
}
