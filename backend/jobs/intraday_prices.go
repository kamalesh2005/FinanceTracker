package jobs

import (
	"log"
	"sync/atomic"
	"time"
)

// PriceUpdater is the subset of Handler used by the intraday cron.
type PriceUpdater interface {
	UpdateAllCurrentPrices()
}

// StartIntradayPriceCron runs UpdateAllCurrentPrices every 15 minutes during
// Mon–Fri 09:00–15:30 Asia/Kolkata (inclusive of 15:30). Safe to call once
// from main; runs in a background goroutine.
func StartIntradayPriceCron(updater PriceUpdater) {
	go runIntradayPriceCron(updater)
}

func runIntradayPriceCron(updater PriceUpdater) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("IntradayPriceCron: failed to load Asia/Kolkata: %v; using FixedZone IST", err)
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}

	log.Printf("IntradayPriceCron: scheduler started (Mon–Fri 09:00–15:30 IST, every 15m)")

	var running atomic.Bool
	for {
		now := time.Now().In(ist)
		next := nextIntradaySlot(now)
		wait := time.Until(next)
		if wait > 0 {
			log.Printf("IntradayPriceCron: next run at %s (in %s)", next.Format(time.RFC3339), wait.Round(time.Second))
			time.Sleep(wait)
		}

		if !running.CompareAndSwap(false, true) {
			log.Printf("IntradayPriceCron: previous run still in progress; skipping")
			continue
		}
		func() {
			defer running.Store(false)
			log.Printf("IntradayPriceCron: tick at %s", time.Now().In(ist).Format(time.RFC3339))
			updater.UpdateAllCurrentPrices()
		}()
	}
}

// nextIntradaySlot returns the next Mon–Fri quarter-hour in [09:00, 15:30] IST
// at or after now (if now is exactly on a slot, returns now).
func nextIntradaySlot(now time.Time) time.Time {
	ist := now.Location()
	t := ceilToQuarterHour(now)

	for {
		if isWeekday(t) && inMarketWindow(t) {
			return t
		}
		if !isWeekday(t) || afterMarketClose(t) {
			t = nextWeekdayOpen(t)
			continue
		}
		if beforeMarketOpen(t) {
			t = time.Date(t.Year(), t.Month(), t.Day(), 9, 0, 0, 0, ist)
			continue
		}
		t = nextWeekdayOpen(t)
	}
}

func ceilToQuarterHour(t time.Time) time.Time {
	ist := t.Location()
	base := time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), 0, 0, ist)
	if base.Before(t) {
		base = base.Add(time.Minute)
	}
	rem := base.Minute() % 15
	if rem != 0 {
		base = base.Add(time.Duration(15-rem) * time.Minute)
	}
	return base
}

func isWeekday(t time.Time) bool {
	wd := t.Weekday()
	return wd >= time.Monday && wd <= time.Friday
}

func inMarketWindow(t time.Time) bool {
	mins := t.Hour()*60 + t.Minute()
	return mins >= 9*60 && mins <= 15*60+30
}

func beforeMarketOpen(t time.Time) bool {
	return t.Hour()*60+t.Minute() < 9*60
}

func afterMarketClose(t time.Time) bool {
	return t.Hour()*60+t.Minute() > 15*60+30
}

func nextWeekdayOpen(t time.Time) time.Time {
	ist := t.Location()
	day := time.Date(t.Year(), t.Month(), t.Day(), 9, 0, 0, 0, ist).AddDate(0, 0, 1)
	for !isWeekday(day) {
		day = day.AddDate(0, 0, 1)
	}
	return day
}
