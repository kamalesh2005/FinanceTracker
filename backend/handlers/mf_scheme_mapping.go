package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

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

func (h *Handler) GetUnmappedMFSchemes(c *gin.Context) {
	var mappings []models.MFSchemeMapping
	err := h.DB.
		Where("mapped_isin IS NULL OR TRIM(mapped_isin) = ''").
		Order("source_scheme_name ASC").
		Find(&mappings).Error
	if err != nil {
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
	return db.Model(&models.MutualFund{}).
		Where(
			"LOWER(TRIM(source_scheme_name)) = ? AND (isin IS NULL OR TRIM(isin) = '')",
			strings.ToLower(sourceSchemeName),
		).
		Updates(updates).Error
}

func (h *Handler) CreateMFSchemeMapping(c *gin.Context) {
	var req models.MFSchemeMapping
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.SourceSchemeName = strings.TrimSpace(req.SourceSchemeName)
	req.MappedISIN = strings.ToUpper(strings.TrimSpace(req.MappedISIN))
	req.SourceFormat = strings.TrimSpace(req.SourceFormat)
	req.Notes = strings.TrimSpace(req.Notes)
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
	if req.MappedISIN != "" {
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
	mapping.Notes = strings.TrimSpace(req.Notes)

	if err := h.DB.Save(&mapping).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if mappedISIN != "" {
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
