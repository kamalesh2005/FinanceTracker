package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var stockImportStatusKinds = []string{
	models.ImportKindNSE,
	models.ImportKindETF,
	models.ImportKindCloses,
	models.ImportKindBSEBhav,
}

var mfImportStatusKinds = []string{
	models.ImportKindMFCatalog,
	models.ImportKindMFVar,
}

var emailImportStatusKinds = []string{
	models.ImportKindStockReviewEmail,
}

var allImportStatusKinds = append(append(append([]string{}, stockImportStatusKinds...), mfImportStatusKinds...), emailImportStatusKinds...)

// EnsureImportStatuses creates stock + MF status rows if missing.
func EnsureImportStatuses(db *gorm.DB) error {
	for _, kind := range allImportStatusKinds {
		row := models.StockDataImportStatus{Kind: kind}
		if err := db.Clauses(clause.OnConflict{DoNothing: true}).Create(&row).Error; err != nil {
			return err
		}
	}
	return nil
}

// ImportSummary is optional counts stored as JSON on success/failure.
type ImportSummary struct {
	Created   int `json:"created,omitempty"`
	Updated   int `json:"updated,omitempty"`
	Skipped   int `json:"skipped,omitempty"`
	Unmatched int `json:"unmatched,omitempty"`
	Errors    int `json:"errors,omitempty"`
}

// RecordImportStatus upserts last-attempt metadata for one import kind.
// On failure, last_success_at is preserved.
func RecordImportStatus(db *gorm.DB, kind, source string, runErr error, summary *ImportSummary) error {
	kind = strings.TrimSpace(kind)
	source = strings.TrimSpace(source)
	if kind == "" {
		return nil
	}
	_ = EnsureImportStatuses(db)

	now := time.Now().UTC()
	status := models.ImportStatusSuccess
	errMsg := ""
	if runErr != nil {
		status = models.ImportStatusFailure
		errMsg = runErr.Error()
		if len(errMsg) > 1024 {
			errMsg = errMsg[:1024]
		}
	}

	summaryJSON := ""
	if summary != nil {
		if b, err := json.Marshal(summary); err == nil {
			summaryJSON = string(b)
		}
	}

	updates := map[string]interface{}{
		"last_attempt_at":   now,
		"last_status":       status,
		"last_error":        errMsg,
		"last_source":       source,
		"last_summary_json": summaryJSON,
		"updated_at":        now,
	}
	if runErr == nil {
		updates["last_success_at"] = now
	}

	return db.Model(&models.StockDataImportStatus{}).
		Where("kind = ?", kind).
		Updates(updates).Error
}

func importStatusesForKinds(db *gorm.DB, kinds []string) ([]models.StockDataImportStatus, error) {
	if err := EnsureImportStatuses(db); err != nil {
		return nil, err
	}
	var rows []models.StockDataImportStatus
	if err := db.Where("kind IN ?", kinds).Find(&rows).Error; err != nil {
		return nil, err
	}
	byKind := make(map[string]models.StockDataImportStatus, len(rows))
	for _, r := range rows {
		byKind[r.Kind] = r
	}
	out := make([]models.StockDataImportStatus, 0, len(kinds))
	for _, kind := range kinds {
		if r, ok := byKind[kind]; ok {
			out = append(out, r)
		} else {
			out = append(out, models.StockDataImportStatus{Kind: kind})
		}
	}
	return out, nil
}

// GetStockImportStatusAdmin returns status for nse / etf / closes uploads.
func (h *Handler) GetStockImportStatusAdmin(c *gin.Context) {
	out, err := importStatusesForKinds(h.DB, stockImportStatusKinds)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, out)
}

// GetMFImportStatusAdmin returns status for mf_catalog / mf_var uploads.
func (h *Handler) GetMFImportStatusAdmin(c *gin.Context) {
	out, err := importStatusesForKinds(h.DB, mfImportStatusKinds)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, out)
}
