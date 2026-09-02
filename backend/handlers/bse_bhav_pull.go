package handlers

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"financetracker/bsebhav"
	"financetracker/models"

	"github.com/gin-gonic/gin"
)

// PullBSEBhavDaily downloads today's BSE equity bhavcopy and upserts Global_Stocks by ISIN.
func (h *Handler) PullBSEBhavDaily() error {
	result, err := bsebhav.PullAndImport(h.DB, time.Now())
	summary := &ImportSummary{
		Created: result.Created,
		Updated: result.Updated,
		Skipped: result.Skipped,
		Errors:  result.Errors,
	}
	if err != nil {
		_ = RecordImportStatus(h.DB, models.ImportKindBSEBhav, models.ImportSourceCron, err, summary)
		return err
	}

	var runErr error
	if result.Created == 0 && result.Updated == 0 && result.Errors > 0 {
		runErr = fmt.Errorf("BSE bhav import changed 0 rows with %d errors (file %s)", result.Errors, result.Filename)
	}

	if recErr := RecordImportStatus(h.DB, models.ImportKindBSEBhav, models.ImportSourceCron, runErr, summary); recErr != nil {
		log.Printf("PullBSEBhavDaily: record status: %v", recErr)
	}

	log.Printf(
		"PullBSEBhavDaily: file=%s trade_date=%s created=%d updated=%d skipped=%d errors=%d",
		result.Filename,
		result.TradeDate.Format("2006-01-02"),
		result.Created,
		result.Updated,
		result.Skipped,
		result.Errors,
	)
	return runErr
}

// PullBSEBhavDailyAdmin runs the same BSE bhav pull as the weekday 23:00 IST cron.
func (h *Handler) PullBSEBhavDailyAdmin(c *gin.Context) {
	if err := h.PullBSEBhavDaily(); err != nil {
		log.Printf("PullBSEBhavDailyAdmin: FAIL: %v", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// ImportBSEBhavAdmin upserts Global_Stocks from an uploaded BSE bhav CSV.
func (h *Handler) ImportBSEBhavAdmin(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "file is required (multipart field name: file)"})
		return
	}
	f, err := file.Open()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not open uploaded file"})
		return
	}
	defer f.Close()

	data, err := io.ReadAll(f)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not read uploaded file"})
		return
	}

	filename := file.Filename
	if filename == "" {
		filename = "bse_bhav.csv"
	}

	result, err := bsebhav.ImportCSV(h.DB, bytes.NewReader(data), filename)
	summary := &ImportSummary{
		Created: result.Created,
		Updated: result.Updated,
		Skipped: result.Skipped,
		Errors:  result.Errors,
	}
	if err != nil {
		_ = RecordImportStatus(h.DB, models.ImportKindBSEBhav, models.ImportSourceManual, err, summary)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	_ = RecordImportStatus(h.DB, models.ImportKindBSEBhav, models.ImportSourceManual, nil, summary)
	c.JSON(http.StatusOK, result)
}
