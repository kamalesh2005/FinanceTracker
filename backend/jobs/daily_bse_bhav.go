package jobs

import (
	"log"
	"sync/atomic"
	"time"
)

// BSEBhavPuller is the subset of Handler used by the weekday BSE bhav cron.
type BSEBhavPuller interface {
	PullBSEBhavDaily() error
}

// StartDailyBSEBhavCron runs PullBSEBhavDaily Mon–Fri at 23:00 Asia/Kolkata.
func StartDailyBSEBhavCron(puller BSEBhavPuller) {
	go runDailyBSEBhavCron(puller)
}

func runDailyBSEBhavCron(puller BSEBhavPuller) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("DailyBSEBhavCron: failed to load Asia/Kolkata: %v; using FixedZone IST", err)
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}

	log.Printf("DailyBSEBhavCron: scheduler started (Mon–Fri 23:00 IST)")

	var running atomic.Bool
	for {
		now := time.Now().In(ist)
		next := nextWeekdayElevenPM(now)
		wait := time.Until(next)
		if wait > 0 {
			log.Printf("DailyBSEBhavCron: next run at %s (in %s)", next.Format(time.RFC3339), wait.Round(time.Second))
			time.Sleep(wait)
		}

		if !running.CompareAndSwap(false, true) {
			log.Printf("DailyBSEBhavCron: previous run still in progress; skipping")
			continue
		}
		func() {
			defer running.Store(false)
			log.Printf("DailyBSEBhavCron: tick at %s", time.Now().In(ist).Format(time.RFC3339))
			if err := puller.PullBSEBhavDaily(); err != nil {
				log.Printf("DailyBSEBhavCron: FAIL: %v", err)
			} else {
				log.Printf("DailyBSEBhavCron: completed")
			}
		}()
	}
}

// nextWeekdayElevenPM returns the next Mon–Fri 23:00 IST at or after now
// (if now is exactly 23:00:00 on a weekday, returns now).
func nextWeekdayElevenPM(now time.Time) time.Time {
	ist := now.Location()
	candidate := time.Date(now.Year(), now.Month(), now.Day(), 23, 0, 0, 0, ist)
	if now.After(candidate) {
		candidate = candidate.AddDate(0, 0, 1)
	}
	for candidate.Weekday() == time.Saturday || candidate.Weekday() == time.Sunday {
		candidate = candidate.AddDate(0, 0, 1)
	}
	return candidate
}
