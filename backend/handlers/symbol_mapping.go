package handlers

import (
	"financetracker/dailyclose"
	"financetracker/models"
	"financetracker/nseimport"
	"io"
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
	if mappings == nil {
		mappings = []models.SymbolMapping{}
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
	if err := h.DB.Where("pull_data = ?", models.PullDataYes).Order("symbol ASC").Find(&stocks).Error; err != nil {
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
	result = make([]UnmappedStockView, 0)
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

// GetAllStocksAdmin returns a paginated Global_Stocks page for admins.
// Query: q, series, listing_category, pull_data, page (1-based), page_size (default 50, max 100).
func (h *Handler) GetAllStocksAdmin(c *gin.Context) {
	page := 1
	if raw := strings.TrimSpace(c.Query("page")); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			page = n
		}
	}
	pageSize := 50
	if raw := strings.TrimSpace(c.Query("page_size")); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			pageSize = n
		}
	}
	if pageSize > 100 {
		pageSize = 100
	}

	q := h.DB.Model(&models.Stock{})
	if search := strings.TrimSpace(c.Query("q")); search != "" {
		like := "%" + search + "%"
		q = q.Where("symbol ILIKE ? OR name ILIKE ? OR sector ILIKE ? OR industry ILIKE ?", like, like, like, like)
	}
	if series := strings.TrimSpace(c.Query("series")); series != "" {
		q = q.Where("UPPER(series) = ?", strings.ToUpper(series))
	}
	if cat := strings.TrimSpace(c.Query("listing_category")); cat != "" {
		q = q.Where("listing_category ILIKE ?", strings.TrimSpace(cat))
	}
	if pull := strings.ToUpper(strings.TrimSpace(c.Query("pull_data"))); pull == models.PullDataYes || pull == models.PullDataNo {
		q = q.Where("pull_data = ?", pull)
	}

	var total int64
	if err := q.Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var stocks []models.Stock
	offset := (page - 1) * pageSize
	if err := q.Order("symbol ASC").Offset(offset).Limit(pageSize).Find(&stocks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"items":     stocks,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// ImportNSECatalogAdmin upserts Global_Stocks from an uploaded NSE_All CSV.
func (h *Handler) ImportNSECatalogAdmin(c *gin.Context) {
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

	result, err := nseimport.ImportCSV(h.DB, f)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := BackfillPullDataFromHoldings(h.DB); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "import succeeded but pull_data backfill failed: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// ImportClosingPricesAdmin upserts one day's closes from a BSE gain/loss xlsx (glDDMMYYYY.xlsx).
// Does not recalculate MAs or sixth-high/low.
func (h *Handler) ImportClosingPricesAdmin(c *gin.Context) {
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

	result, err := dailyclose.ImportClosingPricesXLSX(h.DB, data, file.Filename)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// UpdateStockAdminFields lets admins correct Yahoo-sourced fields (sector, industry, name).
func (h *Handler) UpdateStockAdminFields(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var stock models.Stock
	if err := h.DB.First(&stock, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
		return
	}

	var req struct {
		Name     *string `json:"name"`
		Sector   *string `json:"sector"`
		Industry *string `json:"industry"`
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
	if req.Industry != nil {
		stock.Industry = strings.TrimSpace(*req.Industry)
		updates["industry"] = stock.Industry
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
