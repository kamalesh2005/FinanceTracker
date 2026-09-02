package handlers

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"financetracker/models"
	"financetracker/nsepr"

	"github.com/gin-gonic/gin"
)

// PullNSEPRDaily downloads the latest NSE PR zip, imports prDDMMYYYY.csv into
// existing stocks + daily closes, and records status for etf + closes kinds.
func (h *Handler) PullNSEPRDaily() error {
	result, err := nsepr.PullAndImport(h.DB, time.Now())
	summary := &ImportSummary{
		Updated:   result.Updated,
		Skipped:   result.Skipped,
		Unmatched: result.Unmatched,
		Errors:    result.Errors,
	}
	if err != nil {
		_ = RecordImportStatus(h.DB, models.ImportKindETF, models.ImportSourceCron, err, summary)
		_ = RecordImportStatus(h.DB, models.ImportKindCloses, models.ImportSourceCron, err, summary)
		return err
	}

	var runErr error
	if result.Updated == 0 && result.Errors > 0 {
		runErr = fmt.Errorf("PR import updated 0 stocks with %d errors (file %s)", result.Errors, result.Filename)
	}

	if err := RecordImportStatus(h.DB, models.ImportKindETF, models.ImportSourceCron, runErr, summary); err != nil {
		log.Printf("PullNSEPRDaily: record etf status: %v", err)
	}
	if err := RecordImportStatus(h.DB, models.ImportKindCloses, models.ImportSourceCron, runErr, summary); err != nil {
		log.Printf("PullNSEPRDaily: record closes status: %v", err)
	}

	log.Printf(
		"PullNSEPRDaily: file=%s trade_date=%s updated=%d skipped=%d unmatched=%d errors=%d",
		result.Filename,
		result.TradeDate.Format("2006-01-02"),
		result.Updated,
		result.Skipped,
		result.Unmatched,
		result.Errors,
	)
	return runErr
}

// PullNSEPRDailyAdmin runs the same NSE PR pull as the 22:00 IST cron, on demand.
func (h *Handler) PullNSEPRDailyAdmin(c *gin.Context) {
	if err := h.PullNSEPRDaily(); err != nil {
		log.Printf("PullNSEPRDailyAdmin: FAIL: %v", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
