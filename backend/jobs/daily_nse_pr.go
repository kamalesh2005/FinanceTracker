package jobs

import (
	"log"
	"sync/atomic"
	"time"
)

// NSEPRPuller is the subset of Handler used by the daily NSE PR cron.
type NSEPRPuller interface {
	PullNSEPRDaily() error
}

// StartDailyNSEPRCron runs PullNSEPRDaily once per day at 22:00 Asia/Kolkata.
func StartDailyNSEPRCron(puller NSEPRPuller) {
	go runDailyNSEPRCron(puller)
}

func runDailyNSEPRCron(puller NSEPRPuller) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("DailyNSEPRCron: failed to load Asia/Kolkata: %v; using FixedZone IST", err)
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}

	log.Printf("DailyNSEPRCron: scheduler started (daily 22:00 IST)")

	var running atomic.Bool
	for {
		now := time.Now().In(ist)
		next := nextDailyTenPM(now)
		wait := time.Until(next)
		if wait > 0 {
			log.Printf("DailyNSEPRCron: next run at %s (in %s)", next.Format(time.RFC3339), wait.Round(time.Second))
			time.Sleep(wait)
		}

		if !running.CompareAndSwap(false, true) {
			log.Printf("DailyNSEPRCron: previous run still in progress; skipping")
			continue
		}
		func() {
			defer running.Store(false)
			log.Printf("DailyNSEPRCron: tick at %s", time.Now().In(ist).Format(time.RFC3339))
			if err := puller.PullNSEPRDaily(); err != nil {
				log.Printf("DailyNSEPRCron: FAIL: %v", err)
			} else {
				log.Printf("DailyNSEPRCron: completed")
			}
		}()
	}
}

// nextDailyTenPM returns the next 22:00 IST at or after now (if now is exactly
// 22:00:00, returns now).
func nextDailyTenPM(now time.Time) time.Time {
	ist := now.Location()
	todayTen := time.Date(now.Year(), now.Month(), now.Day(), 22, 0, 0, 0, ist)
	if !now.After(todayTen) {
		return todayTen
	}
	return todayTen.AddDate(0, 0, 1)
}
