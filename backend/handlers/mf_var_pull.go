package handlers

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"financetracker/models"
	"financetracker/nsemf"

	"github.com/gin-gonic/gin"
)

// PullMFVarDaily downloads the latest NSE MF_VAR CSV and imports NAV/haircut
// into Global_MutualFunds, recording mf_var import status.
func (h *Handler) PullMFVarDaily() error {
	result, err := nsemf.PullAndImport(h.DB, time.Now())
	summary := &ImportSummary{
		Created: result.Created,
		Updated: result.Updated,
		Skipped: result.Skipped,
		Errors:  result.Errors,
	}
	if err != nil {
		_ = RecordImportStatus(h.DB, models.ImportKindMFVar, models.ImportSourceCron, err, summary)
		return err
	}

	var runErr error
	if result.Kind != "nav" {
		runErr = fmt.Errorf("expected MF_VAR NAV import, got kind %q", result.Kind)
	} else if result.Updated == 0 && result.Errors > 0 {
		runErr = fmt.Errorf("MF_VAR import updated 0 rows with %d errors", result.Errors)
	}

	if recErr := RecordImportStatus(h.DB, models.ImportKindMFVar, models.ImportSourceCron, runErr, summary); recErr != nil {
		log.Printf("PullMFVarDaily: record status: %v", recErr)
	}

	log.Printf(
		"PullMFVarDaily: kind=%s created=%d updated=%d skipped=%d errors=%d",
		result.Kind, result.Created, result.Updated, result.Skipped, result.Errors,
	)
	return runErr
}

// PullMFVarDailyAdmin runs the same MF_VAR pull as the 22:00 IST cron, on demand.
func (h *Handler) PullMFVarDailyAdmin(c *gin.Context) {
	if err := h.PullMFVarDaily(); err != nil {
		log.Printf("PullMFVarDailyAdmin: FAIL: %v", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
