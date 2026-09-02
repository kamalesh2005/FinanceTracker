package jobs

import (
	"log"
	"sync/atomic"
	"time"
)

// MFVarPuller is the subset of Handler used by the daily MF_VAR cron.
type MFVarPuller interface {
	PullMFVarDaily() error
}

// StartDailyMFVarCron runs PullMFVarDaily once per day at 22:00 Asia/Kolkata.
func StartDailyMFVarCron(puller MFVarPuller) {
	go runDailyMFVarCron(puller)
}

func runDailyMFVarCron(puller MFVarPuller) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("DailyMFVarCron: failed to load Asia/Kolkata: %v; using FixedZone IST", err)
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}

	log.Printf("DailyMFVarCron: scheduler started (daily 22:00 IST)")

	var running atomic.Bool
	for {
		now := time.Now().In(ist)
		next := nextDailyTenPM(now)
		wait := time.Until(next)
		if wait > 0 {
			log.Printf("DailyMFVarCron: next run at %s (in %s)", next.Format(time.RFC3339), wait.Round(time.Second))
			time.Sleep(wait)
		}

		if !running.CompareAndSwap(false, true) {
			log.Printf("DailyMFVarCron: previous run still in progress; skipping")
			continue
		}
		func() {
			defer running.Store(false)
			log.Printf("DailyMFVarCron: tick at %s", time.Now().In(ist).Format(time.RFC3339))
			if err := puller.PullMFVarDaily(); err != nil {
				log.Printf("DailyMFVarCron: FAIL: %v", err)
			} else {
				log.Printf("DailyMFVarCron: completed")
			}
		}()
	}
}
