package handlers

import (
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const screenerPageSize = 20

type screenerStockJSON struct {
	ID              uint     `json:"id"`
	Symbol          string   `json:"symbol"`
	Name            string   `json:"name"`
	Industry        string   `json:"industry"`
	MarketCap       string   `json:"market_cap"`
	Trend           string   `json:"trend"`
	AdjustedSTDelta float64  `json:"adjusted_st_delta"`
	AdjustedMTDelta float64  `json:"adjusted_mt_delta"`
	CurrentPrice    float64  `json:"current_price"`
	MA7             float64  `json:"ma7"`
	MA20            float64  `json:"ma20"`
	MA50            float64  `json:"ma50"`
	ConsensusTarget float64  `json:"consensus_target"`
	ConsensusUpside float64  `json:"consensus_upside"`
	ConsensusType   string   `json:"consensus_type"`
	NewsHeadline    string   `json:"news_headline"`
	NewsURL         string   `json:"news_url"`
	InWatchlist     bool     `json:"in_watchlist"`
	Labels          []string `json:"labels"`
	Return2021      *float64 `json:"return_2021,omitempty"`
	Return2022      *float64 `json:"return_2022,omitempty"`
	Return2023      *float64 `json:"return_2023,omitempty"`
	Return2024      *float64 `json:"return_2024,omitempty"`
	Return2025      *float64 `json:"return_2025,omitempty"`
	ReturnYTD       *float64 `json:"return_ytd,omitempty"`
}

func screenerJSONFromStock(s models.Stock, inWatchlist bool, labels []string) screenerStockJSON {
	if labels == nil {
		labels = []string{}
	}
	return screenerStockJSON{
		ID:              s.ID,
		Symbol:          s.Symbol,
		Name:            s.Name,
		Industry:        s.Industry,
		MarketCap:       s.MarketCap,
		Trend:           s.Trend,
		AdjustedSTDelta: s.AdjustedSTDelta,
		AdjustedMTDelta: s.AdjustedMTDelta,
		CurrentPrice:    s.CurrentPrice,
		MA7:             s.MA7,
		MA20:            s.MA20,
		MA50:            s.MA50,
		ConsensusTarget: s.ConsensusTarget,
		ConsensusUpside: s.ConsensusUpside,
		ConsensusType:   s.ConsensusType,
		NewsHeadline:    s.NewsHeadline,
		NewsURL:         s.NewsURL,
		InWatchlist:     inWatchlist,
		Labels:          labels,
		Return2021:      pctReturn(s.LtpFY2020, s.LtpFY2021),
		Return2022:      pctReturn(s.LtpFY2021, s.LtpFY2022),
		Return2023:      pctReturn(s.LtpFY2022, s.LtpFY2023),
		Return2024:      pctReturn(s.LtpFY2023, s.LtpFY2024),
		Return2025:      pctReturn(s.LtpFY2024, s.LtpFY2025),
		ReturnYTD:       pctReturn(s.LtpFY2025, s.CurrentPrice),
	}
}

func normalizeScreenerLabel(raw string) string {
	return strings.Join(strings.Fields(strings.TrimSpace(raw)), " ")
}

// GetScreenerOptions returns distinct industry, consensus_type, and label values.
func (h *Handler) GetScreenerOptions(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	industries := distinctNonEmptyStrings(h.DB, "industry")
	consensusTypes := distinctNonEmptyStrings(h.DB, "consensus_type")
	c.JSON(http.StatusOK, gin.H{
		"industries":      industries,
		"consensus_types": consensusTypes,
		"labels":          screenerLabelOptions(h.DB, userID),
	})
}

func screenerLabelOptions(db *gorm.DB, userID uint) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(models.DefaultScreenerLabels))
	for _, label := range models.DefaultScreenerLabels {
		seen[label] = struct{}{}
		out = append(out, label)
	}
	for _, label := range distinctUserScreenerLabels(db, userID) {
		if _, ok := seen[label]; ok {
			continue
		}
		seen[label] = struct{}{}
		out = append(out, label)
	}
	return out
}

func distinctUserScreenerLabels(db *gorm.DB, userID uint) []string {
	out := []string{}
	if db == nil || userID == 0 {
		return out
	}
	_ = db.Model(&models.UserScreenerStockLabel{}).
		Where("user_id = ?", userID).
		Distinct("label").
		Order("label ASC").
		Pluck("label", &out).Error
	if out == nil {
		return []string{}
	}
	return out
}

func distinctNonEmptyStrings(db *gorm.DB, column string) []string {
	out := []string{}
	if db == nil {
		return out
	}
	_ = db.Model(&models.Stock{}).
		Where(column+" <> ? AND "+column+" IS NOT NULL", "").
		Distinct(column).
		Order(column+" ASC").
		Pluck(column, &out).Error
	if out == nil {
		return []string{}
	}
	return out
}

// SearchScreener queries Global_Stocks with optional filters, 20 per page.
func (h *Handler) SearchScreener(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	page := 1
	if raw := strings.TrimSpace(c.Query("page")); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			page = n
		}
	}

	q := h.DB.Model(&models.Stock{}).Where("UPPER(series) = ?", "EQ")
	q = applyInFilter(q, "industry", queryValues(c, "industry"))
	q = applyInFilter(q, "market_cap", queryValues(c, "market_cap"))
	q = applyInFilter(q, "trend", queryValues(c, "trend"))
	q = applyInFilter(q, "consensus_type", queryValues(c, "consensus_type"))
	q = applyGreaterThan(q, "adjusted_st_delta", c.Query("adj_st_min"))
	q = applyGreaterThan(q, "adjusted_mt_delta", c.Query("adj_mt_min"))
	q = applyGreaterThan(q, "consensus_upside", c.Query("consensus_upside_min"))
	q = applyNameLike(q, c.Query("name_like"))

	labelFilter := queryValues(c, "label")
	labelMap := screenerLabelsByUser(h.DB, userID)

	var stocks []models.Stock
	var total int64
	if len(labelFilter) > 0 {
		if err := q.Order("symbol ASC").Find(&stocks).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		filtered := make([]models.Stock, 0, len(stocks))
		for _, s := range stocks {
			if stockMatchesLabelFilter(labelMap[s.ID], labelFilter) {
				filtered = append(filtered, s)
			}
		}
		total = int64(len(filtered))
		offset := (page - 1) * screenerPageSize
		end := offset + screenerPageSize
		if offset > len(filtered) {
			stocks = []models.Stock{}
		} else {
			if end > len(filtered) {
				end = len(filtered)
			}
			stocks = filtered[offset:end]
		}
	} else {
		if err := q.Count(&total).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		offset := (page - 1) * screenerPageSize
		if err := q.Order("symbol ASC").Offset(offset).Limit(screenerPageSize).Find(&stocks).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	watched := watchlistStockIDs(h.DB, userID)
	items := make([]screenerStockJSON, 0, len(stocks))
	for _, s := range stocks {
		_, in := watched[s.ID]
		items = append(items, screenerJSONFromStock(s, in, labelMap[s.ID]))
	}

	c.JSON(http.StatusOK, gin.H{
		"items":     items,
		"total":     total,
		"page":      page,
		"page_size": screenerPageSize,
	})
}

func stockMatchesLabelFilter(stockLabels, selected []string) bool {
	selectedSet := map[string]struct{}{}
	includeUnlabeled := false
	for _, label := range selected {
		if label == models.ScreenerLabelUnlabeled {
			includeUnlabeled = true
			continue
		}
		selectedSet[label] = struct{}{}
	}
	if len(stockLabels) == 0 {
		return includeUnlabeled
	}
	for _, label := range stockLabels {
		if _, ok := selectedSet[label]; ok {
			return true
		}
	}
	return false
}

func screenerLabelsByUser(db *gorm.DB, userID uint) map[uint][]string {
	out := map[uint][]string{}
	if db == nil || userID == 0 {
		return out
	}
	var rows []models.UserScreenerStockLabel
	_ = db.Where("user_id = ?", userID).Order("label ASC").Find(&rows).Error
	for _, row := range rows {
		out[row.StockID] = append(out[row.StockID], row.Label)
	}
	return out
}

func applyGreaterThan(q *gorm.DB, column, raw string) *gorm.DB {
	if v, ok := parseOptionalFloat(raw); ok {
		q = q.Where(column+" > ?", v)
	}
	return q
}

func applyNameLike(q *gorm.DB, raw string) *gorm.DB {
	needle := strings.TrimSpace(raw)
	if needle == "" {
		return q
	}
	pattern := "%" + escapeLikePattern(strings.ToLower(needle)) + "%"
	return q.Where("LOWER(name) LIKE ? ESCAPE '\\'", pattern)
}

func escapeLikePattern(s string) string {
	replacer := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return replacer.Replace(s)
}

func queryValues(c *gin.Context, key string) []string {
	seen := map[string]struct{}{}
	out := []string{}
	for _, raw := range c.QueryArray(key) {
		for _, part := range strings.Split(raw, ",") {
			part = strings.TrimSpace(part)
			if part == "" {
				continue
			}
			if _, ok := seen[part]; ok {
				continue
			}
			seen[part] = struct{}{}
			out = append(out, part)
		}
	}
	return out
}

func applyInFilter(q *gorm.DB, column string, values []string) *gorm.DB {
	if len(values) == 0 {
		return q
	}
	return q.Where(column+" IN ?", values)
}

func parseOptionalFloat(raw string) (float64, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return 0, false
	}
	v, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		return 0, false
	}
	return v, true
}

func watchlistStockIDs(db *gorm.DB, userID uint) map[uint]struct{} {
	out := map[uint]struct{}{}
	if db == nil || userID == 0 {
		return out
	}
	var ids []uint
	_ = db.Model(&models.UserWatchlist{}).
		Where("user_id = ?", userID).
		Pluck("stock_id", &ids).Error
	for _, id := range ids {
		out[id] = struct{}{}
	}
	return out
}

// GetWatchlist returns the caller's curated catalog rows.
func (h *Handler) GetWatchlist(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var rows []models.UserWatchlist
	if err := h.DB.Preload("Stock").
		Where("user_id = ?", userID).
		Order("created_at ASC").
		Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	labelMap := screenerLabelsByUser(h.DB, userID)
	items := make([]screenerStockJSON, 0, len(rows))
	for _, row := range rows {
		items = append(items, screenerJSONFromStock(row.Stock, true, labelMap[row.StockID]))
	}
	c.JSON(http.StatusOK, items)
}

// AddToWatchlist upserts a catalog stock onto the caller's watchlist and
// marks pull_data=Y so Yahoo crons (and background enrich) fill LTP/DMA/news.
func (h *Handler) AddToWatchlist(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var body struct {
		StockID uint `json:"stock_id"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.StockID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "stock_id is required"})
		return
	}

	var stock models.Stock
	if err := h.DB.First(&stock, body.StockID).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "stock not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	row := models.UserWatchlist{UserID: userID, StockID: stock.ID}
	if err := h.DB.Where("user_id = ? AND stock_id = ?", userID, stock.ID).
		FirstOrCreate(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	markStockPullDataY(h.DB, stock.ID)
	stock.PullData = models.PullDataYes
	h.enqueueStockYahooEnrichment([]models.Stock{stock}, models.SourceFormatManual)

	labelMap := screenerLabelsByUser(h.DB, userID)
	c.JSON(http.StatusCreated, screenerJSONFromStock(stock, true, labelMap[stock.ID]))
}

// RemoveFromWatchlist deletes the caller's watchlist row. pull_data stays Y.
func (h *Handler) RemoveFromWatchlist(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	stockID, err := strconv.ParseUint(c.Param("stock_id"), 10, 64)
	if err != nil || stockID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "stock_id is required"})
		return
	}
	res := h.DB.Where("user_id = ? AND stock_id = ?", userID, uint(stockID)).
		Delete(&models.UserWatchlist{})
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
		return
	}
	if res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "not on watchlist"})
		return
	}
	c.Status(http.StatusNoContent)
}

// AddScreenerLabel assigns a label to a catalog stock for the caller.
func (h *Handler) AddScreenerLabel(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var body struct {
		StockID uint   `json:"stock_id"`
		Label   string `json:"label"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.StockID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "stock_id and label are required"})
		return
	}
	label := normalizeScreenerLabel(body.Label)
	if label == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "label is required"})
		return
	}

	var stock models.Stock
	if err := h.DB.First(&stock, body.StockID).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "stock not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	row := models.UserScreenerStockLabel{
		UserID:  userID,
		StockID: stock.ID,
		Label:   label,
	}
	if err := h.DB.Where("user_id = ? AND stock_id = ? AND label = ?", userID, stock.ID, label).
		FirstOrCreate(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	labelMap := screenerLabelsByUser(h.DB, userID)
	_, inWatchlist := watchlistStockIDs(h.DB, userID)[stock.ID]
	c.JSON(http.StatusCreated, screenerJSONFromStock(stock, inWatchlist, labelMap[stock.ID]))
}

// RemoveScreenerLabel removes one label from a catalog stock for the caller.
func (h *Handler) RemoveScreenerLabel(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	stockID, err := strconv.ParseUint(c.Param("stock_id"), 10, 64)
	if err != nil || stockID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "stock_id is required"})
		return
	}
	rawLabel, err := url.PathUnescape(c.Param("label"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "label is required"})
		return
	}
	label := normalizeScreenerLabel(rawLabel)
	if label == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "label is required"})
		return
	}

	res := h.DB.Where("user_id = ? AND stock_id = ? AND label = ?", userID, uint(stockID), label).
		Delete(&models.UserScreenerStockLabel{})
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
		return
	}
	if res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "label not found"})
		return
	}
	c.Status(http.StatusNoContent)
}
