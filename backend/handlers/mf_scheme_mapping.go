package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func normalizeMFMappingIgnore(v string) string {
	switch strings.ToUpper(strings.TrimSpace(v)) {
	case "Y":
		return "Y"
	default:
		return "N"
	}
}

func normalizeMFMappingNotes(v string) (string, error) {
	notes := strings.TrimSpace(v)
	if len(notes) > 200 {
		return "", fmt.Errorf("notes must be at most 200 characters")
	}
	return notes, nil
}

func (h *Handler) GetMFSchemeMappings(c *gin.Context) {
	query := h.DB.Model(&models.MFSchemeMapping{}).Order("source_scheme_name ASC")
	if q := strings.TrimSpace(c.Query("q")); q != "" {
		like := "%" + q + "%"
		query = query.Where(
			"source_scheme_name ILIKE ? OR mapped_isin ILIKE ? OR source_format ILIKE ? OR notes ILIKE ?",
			like, like, like, like,
		)
	}
	var mappings []models.MFSchemeMapping
	if err := query.Find(&mappings).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if mappings == nil {
		mappings = []models.MFSchemeMapping{}
	}
	c.JSON(http.StatusOK, mappings)
}

// GetUnmappedMFSchemes lists Global_MFSchemeMappings with optional filters.
// Query: q, unmapped (default true), ignore (default N; Y | N | all).
// Unmapped = mapped_isin empty (same criteria as before).
func (h *Handler) GetUnmappedMFSchemes(c *gin.Context) {
	qFilter := strings.TrimSpace(c.Query("q"))
	unmappedOnly := true
	if raw := strings.TrimSpace(strings.ToLower(c.Query("unmapped"))); raw != "" {
		unmappedOnly = raw == "true" || raw == "1" || raw == "yes"
	}
	ignoreFilter := strings.ToUpper(strings.TrimSpace(c.Query("ignore")))
	if ignoreFilter == "" {
		ignoreFilter = "N"
	}

	query := h.DB.Model(&models.MFSchemeMapping{})
	if qFilter != "" {
		like := "%" + qFilter + "%"
		query = query.Where(
			"source_scheme_name ILIKE ? OR mapped_isin ILIKE ? OR notes ILIKE ?",
			like, like, like,
		)
	}
	if unmappedOnly {
		query = query.Where("mapped_isin IS NULL OR TRIM(mapped_isin) = ''")
	}
	switch ignoreFilter {
	case "Y":
		query = query.Where("UPPER(TRIM(COALESCE(ignore,''))) = ?", "Y")
	case "ALL", "*":
		// no ignore filter
	default: // N
		query = query.Where("ignore IS NULL OR TRIM(ignore) = '' OR UPPER(TRIM(ignore)) = ?", "N")
	}

	var mappings []models.MFSchemeMapping
	if err := query.Order("source_scheme_name ASC").Find(&mappings).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if mappings == nil {
		mappings = []models.MFSchemeMapping{}
	}
	c.JSON(http.StatusOK, mappings)
}

// backfillUserMutualFundsFromMapping fills catalog fields on holdings that still lack ISIN
// for the given broker source scheme name.
func backfillUserMutualFundsFromMapping(db *gorm.DB, sourceSchemeName, mappedISIN string) error {
	sourceSchemeName = strings.TrimSpace(sourceSchemeName)
	mappedISIN = strings.ToUpper(strings.TrimSpace(mappedISIN))
	if sourceSchemeName == "" || mappedISIN == "" {
		return nil
	}
	g, err := findGlobalMutualFundByISIN(db, mappedISIN)
	if err != nil {
		return err
	}
	updates := map[string]interface{}{
		"isin":        g.ISIN,
		"scheme_code": g.Symbol,
		"scheme_name": g.SchemeName,
	}
	if g.CurrentNAV > 0 {
		updates["current_nav"] = g.CurrentNAV
	}
	if err := db.Model(&models.MutualFund{}).
		Where(
			"LOWER(TRIM(source_scheme_name)) = ? AND (isin IS NULL OR TRIM(isin) = '')",
			strings.ToLower(sourceSchemeName),
		).
		Updates(updates).Error; err != nil {
		return err
	}
	// Keep ledger rows aligned once admin maps an unmatched scheme.
	return db.Model(&models.UserMutualFundTransaction{}).
		Where(
			"LOWER(TRIM(source_scheme_name)) = ? AND (isin IS NULL OR TRIM(isin) = '')",
			strings.ToLower(sourceSchemeName),
		).
		Update("isin", g.ISIN).Error
}

func (h *Handler) CreateMFSchemeMapping(c *gin.Context) {
	var req models.MFSchemeMapping
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	notes, err := normalizeMFMappingNotes(req.Notes)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.SourceSchemeName = strings.TrimSpace(req.SourceSchemeName)
	req.MappedISIN = strings.ToUpper(strings.TrimSpace(req.MappedISIN))
	req.SourceFormat = strings.TrimSpace(req.SourceFormat)
	req.Ignore = normalizeMFMappingIgnore(req.Ignore)
	req.Notes = notes
	if req.SourceSchemeName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "source_scheme_name is required"})
		return
	}
	if req.MappedISIN != "" {
		if _, err := findGlobalMutualFundByISIN(h.DB, req.MappedISIN); err != nil {
			if err == gorm.ErrRecordNotFound {
				c.JSON(http.StatusBadRequest, gin.H{"error": "mapped_isin not found in Global_MutualFunds catalog"})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	if err := h.DB.Create(&req).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if req.Ignore != "Y" && req.MappedISIN != "" {
		if err := backfillUserMutualFundsFromMapping(h.DB, req.SourceSchemeName, req.MappedISIN); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	c.JSON(http.StatusCreated, req)
}

func (h *Handler) UpdateMFSchemeMapping(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var mapping models.MFSchemeMapping
	if err := h.DB.First(&mapping, uint(id)).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "mapping not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var req models.MFSchemeMapping
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	notes, err := normalizeMFMappingNotes(req.Notes)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	name := strings.TrimSpace(req.SourceSchemeName)
	if name == "" {
		name = mapping.SourceSchemeName
	}
	mappedISIN := strings.ToUpper(strings.TrimSpace(req.MappedISIN))
	if mappedISIN != "" {
		if _, err := findGlobalMutualFundByISIN(h.DB, mappedISIN); err != nil {
			if err == gorm.ErrRecordNotFound {
				c.JSON(http.StatusBadRequest, gin.H{"error": "mapped_isin not found in Global_MutualFunds catalog"})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	mapping.SourceSchemeName = name
	mapping.MappedISIN = mappedISIN
	if sf := strings.TrimSpace(req.SourceFormat); sf != "" {
		mapping.SourceFormat = sf
	}
	mapping.Ignore = normalizeMFMappingIgnore(req.Ignore)
	mapping.Notes = notes

	if err := h.DB.Save(&mapping).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if mapping.Ignore != "Y" && mappedISIN != "" {
		if err := backfillUserMutualFundsFromMapping(h.DB, mapping.SourceSchemeName, mappedISIN); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	c.JSON(http.StatusOK, mapping)
}

func (h *Handler) DeleteMFSchemeMapping(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var mapping models.MFSchemeMapping
	if err := h.DB.First(&mapping, uint(id)).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "mapping not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if err := h.DB.Delete(&mapping).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "mapping deleted"})
}
