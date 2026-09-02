package jobs

import (
	"log"
	"sync/atomic"
	"time"
)

// MFNAVRefresher is the subset of Handler used by the daily MF NAV cron.
type MFNAVRefresher interface {
	RefreshAllMutualFundCurrentNAVs() error
}

// StartDailyMFNAVCron runs RefreshAllMutualFundCurrentNAVs once per day at
// 06:00 Asia/Kolkata. Safe to call once from main; runs in a background goroutine.
func StartDailyMFNAVCron(refresher MFNAVRefresher) {
	go runDailyMFNAVCron(refresher)
}

func runDailyMFNAVCron(refresher MFNAVRefresher) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("DailyMFNAVCron: failed to load Asia/Kolkata: %v; using FixedZone IST", err)
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}

	log.Printf("DailyMFNAVCron: scheduler started (daily 06:00 IST)")

	var running atomic.Bool
	for {
		now := time.Now().In(ist)
		next := nextDailySixAM(now)
		wait := time.Until(next)
		if wait > 0 {
			log.Printf("DailyMFNAVCron: next run at %s (in %s)", next.Format(time.RFC3339), wait.Round(time.Second))
			time.Sleep(wait)
		}

		if !running.CompareAndSwap(false, true) {
			log.Printf("DailyMFNAVCron: previous run still in progress; skipping")
			continue
		}
		func() {
			defer running.Store(false)
			log.Printf("DailyMFNAVCron: tick at %s", time.Now().In(ist).Format(time.RFC3339))
			if err := refresher.RefreshAllMutualFundCurrentNAVs(); err != nil {
				log.Printf("DailyMFNAVCron: FAIL: %v", err)
			} else {
				log.Printf("DailyMFNAVCron: completed")
			}
		}()
	}
}
