package jobs

import (
	"log"
	"time"

	"financetracker/models"
)

const (
	mfYEBackfillBatchSize = 50
	mfYEBackfillInterval  = 30 * time.Minute
)

// MFYearEndBackfiller builds the prioritized queue and writes FY-end NAVs.
type MFYearEndBackfiller interface {
	BuildMFYearEndBackfillQueue() ([]models.GlobalMutualFund, error)
	BackfillMFYearEndNAVs(funds []models.GlobalMutualFund) (ok, fail int)
}

// StartMFYearEndNAVBackfill runs once after server start: held incomplete MFs
// first, then remaining catalog incompletes, in batches of 50 every 30 minutes.
func StartMFYearEndNAVBackfill(backfiller MFYearEndBackfiller) {
	go runMFYearEndNAVBackfill(backfiller)
}

func runMFYearEndNAVBackfill(backfiller MFYearEndBackfiller) {
	log.Printf("MFYEBackfill: starting queue build")
	queue, err := backfiller.BuildMFYearEndBackfillQueue()
	if err != nil {
		log.Printf("MFYEBackfill: queue build FAIL: %v", err)
		return
	}
	if len(queue) == 0 {
		log.Printf("MFYEBackfill: nothing to do (all year-end NAVs present or no symbols)")
		return
	}
	log.Printf("MFYEBackfill: queued %d funds (held-first, then catalog; batch=%d interval=%s)",
		len(queue), mfYEBackfillBatchSize, mfYEBackfillInterval)

	for i := 0; i < len(queue); i += mfYEBackfillBatchSize {
		end := i + mfYEBackfillBatchSize
		if end > len(queue) {
			end = len(queue)
		}
		batch := queue[i:end]
		batchNum := (i / mfYEBackfillBatchSize) + 1
		totalBatches := (len(queue) + mfYEBackfillBatchSize - 1) / mfYEBackfillBatchSize
		log.Printf("MFYEBackfill: batch %d/%d size=%d", batchNum, totalBatches, len(batch))
		ok, fail := backfiller.BackfillMFYearEndNAVs(batch)
		log.Printf("MFYEBackfill: batch %d/%d done ok=%d fail=%d", batchNum, totalBatches, ok, fail)

		if end < len(queue) {
			log.Printf("MFYEBackfill: sleeping %s before next batch", mfYEBackfillInterval)
			time.Sleep(mfYEBackfillInterval)
		}
	}
	log.Printf("MFYEBackfill: finished")
}
