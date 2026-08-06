package handlers

import (
	"financetracker/etfimport"
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
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}
