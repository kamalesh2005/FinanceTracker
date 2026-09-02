package handlers

import (
	"financetracker/etfimport"
	"financetracker/models"
	"net/http"

	"github.com/gin-gonic/gin"
)

// ImportETFCSVAdmin upserts ETF catalog rows from an uploaded ETF CSV.
func (h *Handler) ImportETFCSVAdmin(c *gin.Context) {
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

	result, err := etfimport.ImportCSV(h.DB, f)
	if err != nil {
		_ = RecordImportStatus(h.DB, models.ImportKindETF, models.ImportSourceManual, err, nil)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_ = RecordImportStatus(h.DB, models.ImportKindETF, models.ImportSourceManual, nil, &ImportSummary{
		Created: result.Created,
		Updated: result.Updated,
		Skipped: result.Skipped,
		Errors:  result.Errors,
	})
	c.JSON(http.StatusOK, result)
}
