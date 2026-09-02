package jobs

import (
	"log"
	"sync/atomic"
	"time"

	"financetracker/models"
)

// StockReviewEmailSender sends weekday stock review emails.
type StockReviewEmailSender interface {
	SendStockReviewEmails(source string, filterUserID *uint) error
}

// StartDailyStockReviewEmailCron runs SendStockReviewEmails Mon–Fri at 12:30 IST.
func StartDailyStockReviewEmailCron(sender StockReviewEmailSender) {
	go runDailyStockReviewEmailCron(sender)
}

func runDailyStockReviewEmailCron(sender StockReviewEmailSender) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("DailyStockReviewEmailCron: failed to load Asia/Kolkata: %v; using FixedZone IST", err)
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}

	log.Printf("DailyStockReviewEmailCron: scheduler started (Mon–Fri 12:30 IST)")

	var running atomic.Bool
	for {
		now := time.Now().In(ist)
		next := nextWeekday1230IST(now, ist)
		wait := time.Until(next)
		if wait > 0 {
			log.Printf("DailyStockReviewEmailCron: next run at %s (in %s)", next.Format(time.RFC3339), wait.Round(time.Second))
			time.Sleep(wait)
		}

		if !running.CompareAndSwap(false, true) {
			log.Printf("DailyStockReviewEmailCron: previous run still in progress; skipping")
			continue
		}
		func() {
			defer running.Store(false)
			log.Printf("DailyStockReviewEmailCron: tick at %s", time.Now().In(ist).Format(time.RFC3339))
			if err := sender.SendStockReviewEmails(models.ImportSourceCron, nil); err != nil {
				log.Printf("DailyStockReviewEmailCron: FAIL: %v", err)
			} else {
				log.Printf("DailyStockReviewEmailCron: completed")
			}
		}()
	}
}

// nextWeekday1230IST returns the next Mon–Fri 12:30 slot in IST.
func nextWeekday1230IST(now time.Time, loc *time.Location) time.Time {
	candidate := time.Date(now.Year(), now.Month(), now.Day(), 12, 30, 0, 0, loc)
	if !now.Before(candidate) {
		candidate = candidate.Add(24 * time.Hour)
	}
	for candidate.Weekday() == time.Saturday || candidate.Weekday() == time.Sunday {
		candidate = candidate.Add(24 * time.Hour)
	}
	return candidate
}
