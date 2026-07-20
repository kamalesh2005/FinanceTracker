package handlers

import (
	"financetracker/models"
	"net/http"
	"strconv"
	"strings"
	"sync"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

var (
	symbolCacheMu sync.RWMutex
	symbolCache   = map[string]string{}
)

// defaultSymbolMappings seeds the master table on first run.
var defaultSymbolMappings = []models.SymbolMapping{
	{SourceSymbol: "HERHON", YahooSymbol: "HEROMOTOCO", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "MAHMAH", YahooSymbol: "M&M", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "TATCOV", YahooSymbol: "TMCV", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "TATMOT", YahooSymbol: "TMPV", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "TVSMOT", YahooSymbol: "TVSMOTOR", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "AXIBAN", YahooSymbol: "AXISBANK", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "HDFBAN", YahooSymbol: "HDFCBANK", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "ICIBAN", YahooSymbol: "ICICIBANK", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "IDFBAN", YahooSymbol: "IDFCFIRSTB", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "STABAN", YahooSymbol: "SBIN", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "ORICEM", YahooSymbol: "ORIENTCEM", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "STACEM", YahooSymbol: "STARCEMENT", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "ULTCEM", YahooSymbol: "ULTRACEMCO", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "CORINT", YahooSymbol: "COROMANDEL", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "DLFLIM", YahooSymbol: "DLF", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "GREIN", YahooSymbol: "GREENPLY", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "NAGCON", YahooSymbol: "NCC", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "PHOMIL", YahooSymbol: "PHOENIXLTD", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "CROGR", YahooSymbol: "CROMPTON", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "HDFGOL", YahooSymbol: "HDFCGOLD", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "ICIGOL", YahooSymbol: "GOLDIETF", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "ICINIF", YahooSymbol: "NIFTYIETF", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "REL150", YahooSymbol: "MID150BEES", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "GODCON", YahooSymbol: "GODREJCP", SourceFormat: models.SourceFormatICICIDirect},
	{SourceSymbol: "TITIND", YahooSymbol: "TITAN", SourceFormat: models.SourceFormatICICIDirect},
}

// SeedAndLoadSymbolMappings inserts defaults when empty, then loads the in-memory cache.
func SeedAndLoadSymbolMappings(db *gorm.DB) error {
	var count int64
	if err := db.Model(&models.SymbolMapping{}).Count(&count).Error; err != nil {
		return err
	}
	if count == 0 {
		for i := range defaultSymbolMappings {
			defaultSymbolMappings[i].SourceSymbol = strings.ToUpper(strings.TrimSpace(defaultSymbolMappings[i].SourceSymbol))
			defaultSymbolMappings[i].YahooSymbol = strings.TrimSpace(defaultSymbolMappings[i].YahooSymbol)
		}
		if err := db.Create(&defaultSymbolMappings).Error; err != nil {
			return err
		}
	}
	return ReloadSymbolCache(db)
}

// ReloadSymbolCache refreshes the runtime symbol lookup cache from the DB.
func ReloadSymbolCache(db *gorm.DB) error {
	var mappings []models.SymbolMapping
	if err := db.Find(&mappings).Error; err != nil {
		return err
	}
	next := make(map[string]string, len(mappings))
	for _, m := range mappings {
		key := strings.ToUpper(strings.TrimSpace(m.SourceSymbol))
		if key == "" || m.YahooSymbol == "" {
			continue
		}
		next[key] = strings.TrimSpace(m.YahooSymbol)
	}
	symbolCacheMu.Lock()
	symbolCache = next
	symbolCacheMu.Unlock()
	return nil
}

func setSymbolCacheEntry(sourceSymbol, yahooSymbol string) {
	key := strings.ToUpper(strings.TrimSpace(sourceSymbol))
	yahooSymbol = strings.TrimSpace(yahooSymbol)
	if key == "" || yahooSymbol == "" {
		return
	}
	symbolCacheMu.Lock()
	symbolCache[key] = yahooSymbol
	symbolCacheMu.Unlock()
}

func resolveYahooSymbol(symbol string) string {
	key := strings.ToUpper(strings.TrimSpace(symbol))
	symbolCacheMu.RLock()
	mapped, ok := symbolCache[key]
	symbolCacheMu.RUnlock()
	if ok && mapped != "" {
		return mapped
	}
	return symbol
}

// UnmappedStockView is a portfolio stock that needs mapping attention.
type UnmappedStockView struct {
	models.Stock
	YahooSymbol    string `json:"yahoo_symbol"`
	ISIN           string `json:"isin"`
	HasMapping     bool   `json:"has_mapping"`
	NeedsAttention bool   `json:"needs_attention"`
	Reason         string `json:"reason"`
}

func (h *Handler) GetSymbolMappings(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	format := strings.TrimSpace(c.Query("source_format"))

	query := h.DB.Model(&models.SymbolMapping{}).Order("source_symbol ASC")
	if q != "" {
		like := "%" + strings.ToUpper(q) + "%"
		query = query.Where(
			"UPPER(source_symbol) LIKE ? OR UPPER(yahoo_symbol) LIKE ? OR UPPER(COALESCE(isin,'')) LIKE ? OR UPPER(COALESCE(notes,'')) LIKE ?",
			like, like, like, like,
		)
	}
	if format != "" {
		query = query.Where("source_format = ?", format)
	}

	var mappings []models.SymbolMapping
	if err := query.Find(&mappings).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, mappings)
}

func (h *Handler) CreateSymbolMapping(c *gin.Context) {
	var req models.SymbolMapping
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.SourceSymbol = strings.ToUpper(strings.TrimSpace(req.SourceSymbol))
	req.YahooSymbol = strings.TrimSpace(req.YahooSymbol)
	req.ISIN = normalizeISIN(req.ISIN)
	if req.SourceSymbol == "" || req.YahooSymbol == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "source_symbol and yahoo_symbol are required"})
		return
	}
	if req.SourceFormat == "" {
		req.SourceFormat = models.SourceFormatManual
	}

	if err := h.DB.Create(&req).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	_ = ReloadSymbolCache(h.DB)
	h.invalidateStockFetch(req.SourceSymbol)
	c.JSON(http.StatusCreated, req)
}

func (h *Handler) UpdateSymbolMapping(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var mapping models.SymbolMapping
	if err := h.DB.First(&mapping, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "mapping not found"})
		return
	}

	var req models.SymbolMapping
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	oldSource := mapping.SourceSymbol
	mapping.SourceSymbol = strings.ToUpper(strings.TrimSpace(req.SourceSymbol))
	mapping.YahooSymbol = strings.TrimSpace(req.YahooSymbol)
	mapping.ISIN = normalizeISIN(req.ISIN)
	mapping.SourceFormat = strings.TrimSpace(req.SourceFormat)
	mapping.Notes = req.Notes
	if mapping.SourceSymbol == "" || mapping.YahooSymbol == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "source_symbol and yahoo_symbol are required"})
		return
	}
	if mapping.SourceFormat == "" {
		mapping.SourceFormat = models.SourceFormatManual
	}

	if err := h.DB.Save(&mapping).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	_ = ReloadSymbolCache(h.DB)
	h.invalidateStockFetch(oldSource)
	h.invalidateStockFetch(mapping.SourceSymbol)
	c.JSON(http.StatusOK, mapping)
}

func (h *Handler) DeleteSymbolMapping(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var mapping models.SymbolMapping
	if err := h.DB.First(&mapping, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "mapping not found"})
		return
	}
	if err := h.DB.Delete(&mapping).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	_ = ReloadSymbolCache(h.DB)
	c.JSON(http.StatusOK, gin.H{"message": "mapping deleted"})
}

func (h *Handler) GetUnmappedStocks(c *gin.Context) {
	var stocks []models.Stock
	if err := h.DB.Order("symbol ASC").Find(&stocks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var mappings []models.SymbolMapping
	h.DB.Find(&mappings)
	bySource := make(map[string]models.SymbolMapping, len(mappings))
	for _, m := range mappings {
		bySource[strings.ToUpper(m.SourceSymbol)] = m
	}

	var result []UnmappedStockView
	for _, stock := range stocks {
		key := strings.ToUpper(stock.Symbol)
		mapping, hasMapping := bySource[key]
		yahoo := resolveYahooSymbol(stock.Symbol)
		fetchFailed := needsYahooAnyData(&stock)

		reason := ""
		needsAttention := false
		if !hasMapping && fetchFailed {
			needsAttention = true
			reason = "No symbol mapping and Yahoo data missing"
		} else if hasMapping && fetchFailed {
			needsAttention = true
			reason = "Mapped but Yahoo data still missing — mapping may be incorrect"
		} else if !hasMapping {
			// Works without mapping (native NSE symbol) — skip from unmapped list
			continue
		} else {
			continue
		}

		yahooSymbol := yahoo
		isin := normalizeISIN(stock.ISIN)
		if hasMapping {
			yahooSymbol = mapping.YahooSymbol
			if mapping.ISIN != "" {
				isin = mapping.ISIN
			}
		} else {
			yahooSymbol = ""
		}

		result = append(result, UnmappedStockView{
			Stock:          stock,
			YahooSymbol:    yahooSymbol,
			ISIN:           isin,
			HasMapping:     hasMapping,
			NeedsAttention: needsAttention,
			Reason:         reason,
		})
	}

	c.JSON(http.StatusOK, result)
}

// UpdateStockAdminFields lets admins correct Yahoo-sourced fields (sector, name).
func (h *Handler) UpdateStockAdminFields(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var stock models.Stock
	if err := h.DB.First(&stock, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
		return
	}

	var req struct {
		Name   *string `json:"name"`
		Sector *string `json:"sector"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updates := map[string]interface{}{}
	if req.Name != nil {
		stock.Name = strings.TrimSpace(*req.Name)
		updates["name"] = stock.Name
	}
	if req.Sector != nil {
		stock.Sector = strings.TrimSpace(*req.Sector)
		updates["sector"] = stock.Sector
	}
	if len(updates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no fields to update"})
		return
	}

	if err := h.DB.Model(&stock).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, stock)
}

func (h *Handler) invalidateStockFetch(sourceSymbol string) {
	key := strings.ToUpper(strings.TrimSpace(sourceSymbol))
	if key == "" {
		return
	}
	h.DB.Model(&models.Stock{}).
		Where("UPPER(symbol) = ?", key).
		Updates(map[string]interface{}{
			"last_fetched_date":   nil,
			"sixth_highest_price": 0,
			"sixth_lowest_price":  0,
			"current_price":       0,
		})
}
