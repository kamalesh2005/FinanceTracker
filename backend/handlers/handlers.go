package handlers

import (
	"encoding/json"
	"financetracker/auth"
	"financetracker/dailyclose"
	"financetracker/middleware"
	"financetracker/models"
	"financetracker/trendlyne"
	"financetracker/trendrules"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const consensusRefreshIntervalDays = 3

// consensusDevFetchLimit > 0: development mode — always refetch the first N user
// holdings on every refresh (ignore 3-day cache). Set to 0 for production.
const consensusDevFetchLimit = 5

// StockWithDetails embeds Stock with one User_Stocks position (per source).
type StockWithDetails struct {
	models.Stock
	Source                string     `json:"source"`
	Quantity              float64    `json:"quantity"`
	AverageBuyPrice       float64    `json:"average_buy_price"`
	LastBuyPrice          float64    `json:"last_buy_price"`
	LastBuyDate           *time.Time `json:"last_buy_date"`
	LastBuyTrend          string     `json:"last_buy_trend"`
	LastSalePrice         float64    `json:"last_sale_price"`
	LastSaleDate          *time.Time `json:"last_sale_date"`
	LastSaleTrend         string     `json:"last_sale_trend"`
	LastHoldPrice         float64    `json:"last_hold_price"`
	LastHoldDate          *time.Time `json:"last_hold_date"`
	LastHoldTrend         string     `json:"last_hold_trend"`
	SetBuyPrice           float64    `json:"set_buy_price"`
	SetProfitBookingPrice float64    `json:"set_profit_booking_price"`
	SetStopLossPrice      float64    `json:"set_stop_loss_price"`
	BSHClearDate          *time.Time `json:"bsh_clear_date"`
	Notes                 string     `json:"notes"`
	XIRR                  *float64   `json:"xirr"`
	// Computed FY YoY / YTD % returns from Global_Stocks FY-end LTPs (not persisted).
	Return2021 *float64 `json:"return_2021,omitempty"`
	Return2022 *float64 `json:"return_2022,omitempty"`
	Return2023 *float64 `json:"return_2023,omitempty"`
	Return2024 *float64 `json:"return_2024,omitempty"`
	Return2025 *float64 `json:"return_2025,omitempty"`
	ReturnYTD  *float64 `json:"return_ytd,omitempty"`
}

func yahooChartURL(symbol, suffix, query string) string {
	return yahooChartURLDirect(resolveYahooSymbol(symbol), suffix, query)
}

func yahooChartURLDirect(ticker, suffix, query string) string {
	return fmt.Sprintf(
		"https://query1.finance.yahoo.com/v8/finance/chart/%s%s?%s",
		url.PathEscape(ticker),
		suffix,
		query,
	)
}

type Handler struct {
	DB             *gorm.DB
	GoogleVerifier auth.GoogleTokenVerifier
	// SkipBackgroundYahooEnrichment disables the post-import Yahoo/ISIN
	// goroutine. Tests set this so sqlite runs do not hit the network.
	SkipBackgroundYahooEnrichment bool
}

func NewHandler(db *gorm.DB) *Handler {
	return &Handler{
		DB:             db,
		GoogleVerifier: auth.DefaultGoogleVerifier(),
	}
}

func isSameCalendarDay(t *time.Time, today time.Time) bool {
	if t == nil {
		return false
	}
	loc := today.Location()
	local := t.In(loc)
	d := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, loc)
	return d.Equal(today)
}

func needsConsensusRefresh(last *time.Time, today time.Time) bool {
	if last == nil {
		return true
	}
	loc := today.Location()
	local := last.In(loc)
	fetchedDay := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, loc)
	return today.Sub(fetchedDay) >= time.Duration(consensusRefreshIntervalDays)*24*time.Hour
}

func (h *Handler) stocksWithHoldings(stocks []models.Stock, userID uint) []StockWithDetails {
	if len(stocks) == 0 {
		return []StockWithDetails{}
	}

	byID := make(map[uint]models.Stock, len(stocks))
	ids := make([]uint, 0, len(stocks))
	for _, stock := range stocks {
		byID[stock.ID] = stock
		ids = append(ids, stock.ID)
	}

	var positions []models.UserStock
	h.DB.Where("user_id = ? AND stock_id IN ?", userID, ids).
		Order("stock_id asc, source asc").
		Find(&positions)

	var lots []models.UserStockTransaction
	if len(ids) > 0 {
		h.DB.Where("user_id = ? AND stock_id IN ? AND type = ?", userID, ids, models.TransactionTypeBuy).
			Find(&lots)
	}
	lotsByKey := map[string][]models.UserStockTransaction{}
	for _, lot := range lots {
		src := strings.TrimSpace(lot.Source)
		if src == "" {
			src = models.SourceManualAdd
		}
		key := fmt.Sprintf("%d\x00%s", lot.StockID, src)
		lotsByKey[key] = append(lotsByKey[key], lot)
	}
	asOf := time.Now()

	stocksWithDetails := make([]StockWithDetails, 0, len(positions))
	for _, pos := range positions {
		stock, ok := byID[pos.StockID]
		if !ok {
			continue
		}
		source := strings.TrimSpace(pos.Source)
		if source == "" {
			source = models.SourceManualAdd
		}
		key := fmt.Sprintf("%d\x00%s", pos.StockID, source)
		xirrVal := xirrRateFromLots(lotsByKey[key], map[uint]float64{stock.ID: stock.CurrentPrice}, asOf)
		detail := StockWithDetails{
			Stock:                 stock,
			Source:                source,
			Quantity:              pos.Quantity,
			AverageBuyPrice:       pos.AvgBuyPrice,
			LastBuyPrice:          pos.LastBuyPrice,
			LastBuyDate:           pos.LastBuyDate,
			LastBuyTrend:          pos.LastBuyTrend,
			LastSalePrice:         pos.LastSalePrice,
			LastSaleDate:          pos.LastSaleDate,
			LastSaleTrend:         pos.LastSaleTrend,
			LastHoldPrice:         pos.LastHoldPrice,
			LastHoldDate:          pos.LastHoldDate,
			LastHoldTrend:         pos.LastHoldTrend,
			SetBuyPrice:           pos.SetBuyPrice,
			SetProfitBookingPrice: pos.SetProfitBookingPrice,
			SetStopLossPrice:      pos.SetStopLossPrice,
			BSHClearDate:          pos.BSHClearDate,
			Notes:                 pos.Notes,
			XIRR:                  xirrVal,
		}
		applyStockFYReturns(&detail)
		stocksWithDetails = append(stocksWithDetails, detail)
	}
	return stocksWithDetails
}

func (h *Handler) stocksForUser(userID uint) ([]models.Stock, error) {
	var stockIDs []uint
	if err := h.DB.Model(&models.UserStock{}).
		Where("user_id = ?", userID).
		Distinct("stock_id").
		Pluck("stock_id", &stockIDs).Error; err != nil {
		return nil, err
	}
	if len(stockIDs) == 0 {
		return []models.Stock{}, nil
	}
	var stocks []models.Stock
	if err := h.DB.Where("id IN ?", stockIDs).Find(&stocks).Error; err != nil {
		return nil, err
	}
	return stocks, nil
}

// Stock handlers
func (h *Handler) GetStocks(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	// Always scope to the caller's holdings (one row per source+stock).
	// Admin catalog browsing uses GET /admin/stocks — never load Global_Stocks here.
	stocks, err := h.stocksForUser(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.stocksWithHoldings(stocks, userID))
}

func (h *Handler) CreateStock(c *gin.Context) {
	var stock models.Stock
	if err := c.ShouldBindJSON(&stock); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	if stock.PullData != models.PullDataYes {
		stock.PullData = models.PullDataNo
	}

	// Fetch sector, industry, market cap, sixth high/low, and MAs (one Yahoo 1y call) if not fetched today
	if stock.LastFetchedDate == nil || stock.LastFetchedDate.Before(today) {
		if sector, industry, err := fetchYahooFinanceAssetProfile(stock.Symbol); err == nil {
			if sector != "" {
				stock.Sector = sector
			}
			if industry != "" {
				stock.Industry = industry
			}
		}
		if marketCap, err := fetchYahooFinanceMarketCap(stock.Symbol); err == nil {
			stock.MarketCap = classifyMarketCap(marketCap)
		}
		if res, err := dailyclose.SyncYahooHistory(h.DB, stock.Symbol, resolveYahooSymbol(stock.Symbol), nil, now); err == nil && !res.Skipped {
			if res.SixthHigh > 0 {
				stock.SixthHighestPrice = res.SixthHigh
			}
			if res.SixthLow > 0 {
				stock.SixthLowestPrice = res.SixthLow
			}
			if res.MA7 > 0 {
				stock.MA7, stock.MA20, stock.MA50 = res.MA7, res.MA20, res.MA50
			}
			stock.LastFetchedDate = &now
			stock.LastTrendFetchedDate = &now
		}
	}

	if err := h.DB.Create(&stock).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, stock)
}

func (h *Handler) GetStock(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var stock models.Stock
	if err := h.DB.First(&stock, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
		return
	}
	c.JSON(http.StatusOK, stock)
}

// LookupStockBySymbol returns a Global_Stocks row by symbol (no holdings required).
// Used by Manual Add to prefill buy price from an existing LTP.
func (h *Handler) LookupStockBySymbol(c *gin.Context) {
	symbol := strings.ToUpper(strings.TrimSpace(c.Query("symbol")))
	if symbol == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "symbol is required"})
		return
	}
	var stock models.Stock
	if err := h.DB.Where("UPPER(symbol) = ?", symbol).First(&stock).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "stock not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"symbol":        stock.Symbol,
		"name":          stock.Name,
		"current_price": stock.CurrentPrice,
	})
}

// SearchStocks returns Global_Stocks catalog matches for Manual Add autocomplete.
func (h *Handler) SearchStocks(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	if len(q) < 1 {
		c.JSON(http.StatusOK, []gin.H{})
		return
	}
	limit := 20
	if raw := strings.TrimSpace(c.Query("limit")); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 && n <= 50 {
			limit = n
		}
	}

	upperQ := strings.ToUpper(q)
	likePrefix := upperQ + "%"
	likeContains := "%" + q + "%"
	var stocks []models.Stock
	err := h.DB.
		Where("UPPER(symbol) LIKE ? OR name ILIKE ?", likePrefix, likeContains).
		Order("symbol ASC").
		Limit(limit * 3).
		Find(&stocks).Error
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	sort.SliceStable(stocks, func(i, j int) bool {
		si, sj := strings.ToUpper(stocks[i].Symbol), strings.ToUpper(stocks[j].Symbol)
		pi, pj := strings.HasPrefix(si, upperQ), strings.HasPrefix(sj, upperQ)
		if pi != pj {
			return pi
		}
		return si < sj
	})
	if len(stocks) > limit {
		stocks = stocks[:limit]
	}

	out := make([]gin.H, 0, len(stocks))
	for _, s := range stocks {
		out = append(out, gin.H{
			"symbol":        s.Symbol,
			"name":          s.Name,
			"current_price": s.CurrentPrice,
		})
	}
	c.JSON(http.StatusOK, out)
}

// markStockPullDataY sets pull_data=Y so Yahoo crons include this catalog row.
// When the value actually flips to Y, schedules an FY-end LTP backfill for all
// pull_data=Y stocks that still lack FY closes.
func markStockPullDataY(db *gorm.DB, stockID uint) {
	if stockID == 0 || db == nil {
		return
	}
	res := db.Model(&models.Stock{}).
		Where("id = ? AND pull_data <> ?", stockID, models.PullDataYes).
		Update("pull_data", models.PullDataYes)
	if res.Error != nil {
		return
	}
	if res.RowsAffected > 0 {
		triggerStockFYBackfill()
	}
}

// BackfillPullDataFromHoldings sets pull_data=Y for any Global_Stocks row
// referenced by User_Stocks or Inv_Ch_Holdings, and normalizes blank values to N.
func BackfillPullDataFromHoldings(db *gorm.DB) error {
	if err := db.Exec(`
		UPDATE "Global_Stocks"
		SET pull_data = ?
		WHERE id IN (SELECT DISTINCT stock_id FROM "User_Stocks")
		  AND (pull_data IS NULL OR pull_data = '' OR pull_data <> ?)
	`, models.PullDataYes, models.PullDataYes).Error; err != nil {
		return err
	}
	if db.Migrator().HasTable(&models.InvChHolding{}) {
		if err := db.Exec(`
			UPDATE "Global_Stocks"
			SET pull_data = ?
			WHERE id IN (SELECT DISTINCT stock_id FROM "Inv_Ch_Holdings")
			  AND (pull_data IS NULL OR pull_data = '' OR pull_data <> ?)
		`, models.PullDataYes, models.PullDataYes).Error; err != nil {
			return err
		}
	}
	return db.Exec(`
		UPDATE "Global_Stocks"
		SET pull_data = ?
		WHERE pull_data IS NULL OR pull_data = ''
	`, models.PullDataNo).Error
}

func (h *Handler) UpdateStock(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var stock models.Stock
	if err := h.DB.First(&stock, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
		return
	}
	if err := c.ShouldBindJSON(&stock); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.DB.Save(&stock).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, stock)
}

// UpdateStockHoldings replaces the user's Manual Add position with the given quantity and buy price.
// Symbol is accepted for compatibility but cannot be changed — holdings stay on the existing stock.
func (h *Handler) UpdateStockHoldings(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stock id"})
		return
	}

	var req struct {
		Symbol   string  `json:"symbol"`
		Quantity float64 `json:"quantity"`
		Price    float64 `json:"price"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := validateBuyQuantityPrice(req.Quantity, req.Price); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := middleware.CurrentUserID(c)
	watchList := h.userUsesWatchList(userID)
	if watchList {
		req.Quantity = 1
	}

	var stock models.Stock
	if err := h.DB.First(&stock, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
		return
	}
	markStockPullDataY(h.DB, stock.ID)

	var userPosCount int64
	if err := h.DB.Model(&models.UserStock{}).
		Where("user_id = ? AND stock_id = ? AND source = ?", userID, stock.ID, models.SourceManualAdd).
		Count(&userPosCount).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if userPosCount == 0 {
		c.JSON(http.StatusForbidden, gin.H{"error": "no Manual Add holdings for this stock"})
		return
	}

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}

	if err := replaceManualAddPosition(tx, userID, stock.ID, req.Quantity, req.Price, time.Now()); err != nil {
		tx.Rollback()
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	details := h.stocksWithHoldings([]models.Stock{stock}, userID)
	if len(details) == 0 {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load updated holding"})
		return
	}
	updated := details[0]
	for _, d := range details {
		if d.Source == models.SourceManualAdd {
			updated = d
			break
		}
	}
	c.JSON(http.StatusOK, updated)
}

// DeleteStockHoldings removes the current user's holding (and ledger) for a stock+source.
// It does not delete the shared stock master row.
func (h *Handler) DeleteStockHoldings(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stock id"})
		return
	}

	source := normalizeSource(c.Query("source"))
	userID := middleware.CurrentUserID(c)

	var pos models.UserStock
	if err := h.DB.Where("user_id = ? AND stock_id = ? AND source = ?", userID, uint(id), source).
		First(&pos).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "holding not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}

	if err := tx.Where("user_id = ? AND stock_id = ? AND source = ?", userID, uint(id), source).
		Delete(&models.UserStockTransaction{}).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if err := tx.Delete(&pos).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Holding deleted"})
}

// DeleteAllUserHoldings removes every User_Stocks and User_Stock_Transactions row
// for the current user. Shared catalog rows are left unchanged.
func (h *Handler) DeleteAllUserHoldings(c *gin.Context) {
	userID := middleware.CurrentUserID(c)

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}

	if err := tx.Where("user_id = ?", userID).Delete(&models.UserStockTransaction{}).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	res := tx.Where("user_id = ?", userID).Delete(&models.UserStock{})
	if res.Error != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
		return
	}
	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "All holdings deleted",
		"deleted": res.RowsAffected,
	})
}

func (h *Handler) DeleteStock(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	if err := h.DB.Delete(&models.Stock{}, uint(id)).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Stock deleted"})
}

func (h *Handler) CreateStocksBulk(c *gin.Context) {
	var stocks []models.Stock
	if err := c.ShouldBindJSON(&stocks); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	for i := range stocks {
		if stocks[i].PullData != models.PullDataYes {
			stocks[i].PullData = models.PullDataNo
		}
		// Fetch sector, industry, market cap, sixth high/low, and MAs (one Yahoo 1y call) if not fetched today
		if stocks[i].LastFetchedDate == nil || stocks[i].LastFetchedDate.Before(today) {
			if sector, industry, err := fetchYahooFinanceAssetProfile(stocks[i].Symbol); err == nil {
				if sector != "" {
					stocks[i].Sector = sector
				}
				if industry != "" {
					stocks[i].Industry = industry
				}
			}
			if marketCap, err := fetchYahooFinanceMarketCap(stocks[i].Symbol); err == nil {
				stocks[i].MarketCap = classifyMarketCap(marketCap)
			}
			if res, err := dailyclose.SyncYahooHistory(h.DB, stocks[i].Symbol, resolveYahooSymbol(stocks[i].Symbol), nil, now); err == nil && !res.Skipped {
				if res.SixthHigh > 0 {
					stocks[i].SixthHighestPrice = res.SixthHigh
				}
				if res.SixthLow > 0 {
					stocks[i].SixthLowestPrice = res.SixthLow
				}
				if res.MA7 > 0 {
					stocks[i].MA7, stocks[i].MA20, stocks[i].MA50 = res.MA7, res.MA20, res.MA50
				}
				stocks[i].LastFetchedDate = &now
				stocks[i].LastTrendFetchedDate = &now
			}
		}
	}

	if err := h.DB.Create(&stocks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, stocks)
}

// enrichStockIfNeeded fetches Yahoo LTP, highs/lows, profile, target, and
// Google Finance news when the catalog row is missing those fields. Same path
// as broker import. Tests set SkipBackgroundYahooEnrichment to avoid the network.
func (h *Handler) enrichStockIfNeeded(stock *models.Stock, sourceFormat string) {
	if h == nil || stock == nil || stock.ID == 0 || !needsYahooAnyData(stock) {
		return
	}
	if h.SkipBackgroundYahooEnrichment {
		return
	}
	if sourceFormat == "" {
		sourceFormat = models.SourceFormatManual
	}
	h.applyYahooDataWithAutoMapping(stock, sourceFormat)
	h.persistYahooStockFields(stock)
}

func (h *Handler) enrichCatalogSymbol(symbol, sourceFormat string) {
	stock, err := h.findCatalogStock(symbol)
	if err != nil {
		return
	}
	markStockPullDataY(h.DB, stock.ID)
	stock.PullData = models.PullDataYes
	h.enrichStockIfNeeded(&stock, sourceFormat)
}

func (h *Handler) findOrCreateStock(symbol, name, isin string) (models.Stock, error) {
	stock, err := h.findOrCreateStockRecord(symbol, name, isin)
	if err != nil {
		return stock, err
	}
	h.enrichStockIfNeeded(&stock, models.SourceFormatManual)
	return stock, nil
}

// findOrCreateStockRecord upserts Global_Stocks for symbol/name/ISIN with no Yahoo calls.
func (h *Handler) findOrCreateStockRecord(symbol, name, isin string) (models.Stock, error) {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	rawISIN := strings.ToUpper(strings.TrimSpace(isin))
	name = strings.TrimSpace(name)
	var stock models.Stock
	if err := h.DB.Where("symbol = ?", symbol).First(&stock).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			stock = models.Stock{
				Symbol:   symbol,
				ISIN:     rawISIN,
				Name:     name,
				PullData: models.PullDataYes,
			}
			if err := h.DB.Create(&stock).Error; err != nil {
				return stock, err
			}
			return stock, nil
		}
		return stock, err
	}
	updates := map[string]interface{}{}
	if name != "" && stock.Name != name {
		stock.Name = name
		updates["name"] = name
	}
	if rawISIN != "" && strings.TrimSpace(stock.ISIN) == "" {
		stock.ISIN = rawISIN
		updates["isin"] = rawISIN
	}
	markStockPullDataY(h.DB, stock.ID)
	stock.PullData = models.PullDataYes
	if len(updates) > 0 {
		_ = h.DB.Model(&stock).Updates(updates).Error
	}
	return stock, nil
}

func (h *Handler) enqueueStockYahooEnrichment(stocks []models.Stock, sourceFormat string) {
	if h == nil || h.SkipBackgroundYahooEnrichment || h.DB == nil {
		return
	}
	pending := make([]models.Stock, 0, len(stocks))
	for i := range stocks {
		s := stocks[i]
		if s.ID == 0 || !needsYahooAnyData(&s) {
			continue
		}
		pending = append(pending, s)
	}
	if len(pending) == 0 {
		return
	}
	go func() {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("background yahoo enrichment panic: %v", rec)
			}
		}()
		log.Printf("background yahoo enrichment: starting %d stocks", len(pending))
		for i := range pending {
			s := pending[i]
			h.applyYahooDataWithAutoMapping(&s, sourceFormat)
			h.persistYahooStockFields(&s)
		}
		_ = ReloadSymbolCache(h.DB)
		log.Printf("background yahoo enrichment: done %d stocks", len(pending))
	}()
}

// findCatalogStock looks up an existing Global_Stocks row (no create).
func (h *Handler) findCatalogStock(symbol string) (models.Stock, error) {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	var stock models.Stock
	if err := h.DB.Where("UPPER(symbol) = ?", symbol).First(&stock).Error; err != nil {
		return stock, err
	}
	return stock, nil
}

func (h *Handler) applyYahooDataToStock(symbol string, stock *models.Stock) {
	now := time.Now()

	if sector, industry, err := fetchYahooFinanceAssetProfile(symbol); err == nil {
		if sector != "" {
			stock.Sector = sector
		}
		if industry != "" {
			stock.Industry = industry
		}
	}
	if marketCap, err := fetchYahooFinanceMarketCap(symbol); err == nil {
		stock.MarketCap = classifyMarketCap(marketCap)
	}
	res, err := dailyclose.SyncYahooHistory(h.DB, stock.Symbol, resolveYahooSymbol(symbol), nil, now)
	if err == nil {
		if !res.Skipped {
			if res.SixthHigh > 0 {
				stock.SixthHighestPrice = res.SixthHigh
			}
			if res.SixthLow > 0 {
				stock.SixthLowestPrice = res.SixthLow
			}
			if res.MA7 > 0 {
				stock.MA7, stock.MA20, stock.MA50 = res.MA7, res.MA20, res.MA50
				stock.StockSTDelta, stock.StockMTDelta = res.STDelta, res.MTDelta
			}
			stock.LastFetchedDate = &now
			stock.LastTrendFetchedDate = &now
		}
	} else {
		log.Printf("applyYahooDataToStock [%s]: daily-close sync FAIL: %v", stock.Symbol, err)
	}
	if currentPrice, err := fetchYahooFinancePrice(symbol); err == nil {
		stock.CurrentPrice = currentPrice
		stock.LastPriceFetchedDate = &now
		persistYahooTargetAndNews(h.DB, stock, currentPrice, now, yahooTargetNewsPolicy{})
	}
}

func (h *Handler) persistYahooStockFields(stock *models.Stock) {
	updates := map[string]interface{}{
		"sector":                  stock.Sector,
		"industry":                stock.Industry,
		"market_cap":              stock.MarketCap,
		"sixth_highest_price":     stock.SixthHighestPrice,
		"sixth_lowest_price":      stock.SixthLowestPrice,
		"current_price":           stock.CurrentPrice,
		"last_fetched_date":       stock.LastFetchedDate,
		"last_price_fetched_date": stock.LastPriceFetchedDate,
	}
	if stock.ConsensusTarget > 0 || strings.TrimSpace(stock.ConsensusType) != "" {
		updates["consensus_target"] = stock.ConsensusTarget
		updates["consensus_ltp"] = stock.ConsensusLTP
		updates["consensus_upside"] = stock.ConsensusUpside
		updates["consensus_type"] = stock.ConsensusType
		updates["consensus_date"] = stock.ConsensusDate
		updates["last_consensus_fetched_date"] = stock.LastConsensusFetchedDate
	}
	if strings.TrimSpace(stock.NewsHeadline) != "" {
		updates["news_headline"] = stock.NewsHeadline
		updates["news_url"] = stock.NewsURL
	}
	_ = h.DB.Model(stock).Updates(updates).Error
}

func needsYahooHistoricalData(stock *models.Stock) bool {
	return stock == nil ||
		stock.SixthHighestPrice < 1 ||
		stock.SixthLowestPrice < 1 ||
		strings.TrimSpace(stock.Industry) == ""
}

func needsYahooAnyData(stock *models.Stock) bool {
	return stock == nil || stock.CurrentPrice == 0 || needsYahooHistoricalData(stock)
}

// applyYahooDataWithAutoMapping retries Yahoo fetches after resolving the stock's
// broker symbol from ISIN or name and persisting the symbol mapping.
func (h *Handler) applyYahooDataWithAutoMapping(stock *models.Stock, sourceFormat string) {
	if stock == nil {
		return
	}

	h.applyYahooDataToStock(stock.Symbol, stock)
	if !needsYahooAnyData(stock) {
		return
	}

	if sourceFormat == "" {
		sourceFormat = models.SourceFormatManual
	}

	isin := normalizeISIN(stock.ISIN)
	if isin != "" {
		createdMapping, err := EnsureSymbolMappingFromISIN(h.DB, stock.Symbol, isin, sourceFormat)
		if err != nil {
			log.Printf("stock ISIN auto-map error for %s (%s): %v", stock.Symbol, isin, err)
		} else {
			mapped := resolveYahooSymbol(stock.Symbol)
			log.Printf("stock ISIN auto-map result for %s: isin=%s created=%v yahoo=%s", stock.Symbol, isin, createdMapping, mapped)
			if createdMapping || mapped != stock.Symbol {
				h.applyYahooDataToStock(stock.Symbol, stock)
				log.Printf("stock ISIN auto-map refetch for %s: price=%.2f high6=%.2f low6=%.2f",
					stock.Symbol, stock.CurrentPrice, stock.SixthHighestPrice, stock.SixthLowestPrice)
			}
		}
		if !needsYahooAnyData(stock) {
			return
		}
	}

	name := strings.TrimSpace(stock.Name)
	if name == "" {
		log.Printf("stock auto-map: no name for %s — name fallback skipped", stock.Symbol)
		return
	}

	createdMapping, err := EnsureSymbolMappingFromName(h.DB, stock.Symbol, name, isin, sourceFormat)
	if err != nil {
		log.Printf("stock name auto-map error for %s (%q): %v", stock.Symbol, name, err)
		return
	}
	mapped := resolveYahooSymbol(stock.Symbol)
	log.Printf("stock name auto-map result for %s: name=%q created=%v yahoo=%s", stock.Symbol, name, createdMapping, mapped)
	if createdMapping || mapped != stock.Symbol {
		h.applyYahooDataToStock(stock.Symbol, stock)
		log.Printf("stock name auto-map refetch for %s: price=%.2f high6=%.2f low6=%.2f",
			stock.Symbol, stock.CurrentPrice, stock.SixthHighestPrice, stock.SixthLowestPrice)
	} else {
		log.Printf("stock name auto-map: no mapping created for %s — Yahoo refetch skipped", stock.Symbol)
	}
}

// Transaction handlers
func (h *Handler) CreateBuyTransaction(c *gin.Context) {
	var req struct {
		Symbol          string    `json:"symbol" binding:"required"`
		Quantity        float64   `json:"quantity"`
		Price           float64   `json:"price"`
		TransactionDate time.Time `json:"transaction_date" binding:"required"`
		Source          string    `json:"source"`
		Name            string    `json:"name"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := validateBuyQuantityPrice(req.Quantity, req.Price); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	source := normalizeSource(req.Source)
	stock, err := h.findCatalogStock(req.Symbol)
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "symbol not found in catalog; select a stock from suggestions"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	markStockPullDataY(h.DB, stock.ID)
	stock.PullData = models.PullDataYes
	h.enrichStockIfNeeded(&stock, models.SourceFormatManual)

	userID := middleware.CurrentUserID(c)
	qty := req.Quantity
	if h.userUsesWatchList(userID) {
		qty = 1
	}
	ledger, pos, err := applyManualStockTransaction(
		h.DB, userID, stock.ID, models.TransactionTypeBuy,
		qty, req.Price, req.TransactionDate, source,
	)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if h.userUsesWatchList(userID) && pos.Quantity > 1+1e-9 {
		if err := normalizePositionLotsToOne(h.DB, pos); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	c.JSON(http.StatusCreated, ledger)
}

func (h *Handler) ReplaceSourceBuyTransactions(c *gin.Context) {
	var req struct {
		Source string `json:"source" binding:"required"`
		Items  []struct {
			Symbol          string     `json:"symbol" binding:"required"`
			Quantity        float64    `json:"quantity" binding:"required"`
			Price           float64    `json:"price" binding:"required"`
			TransactionDate *time.Time `json:"transaction_date"`
			Name            string     `json:"name"`
			ISIN            string     `json:"isin"`
			Sector          string     `json:"sector"`
		} `json:"items" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	source := req.Source
	if !models.IsReplaceableImportSource(source) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "source must be a bulk import source, not Manual Add"})
		return
	}

	userID := middleware.CurrentUserID(c)
	watchList := h.userUsesWatchList(userID)

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}

	touchedStockIDs := make(map[uint]struct{})
	result := make([]models.UserStock, 0, len(req.Items))
	deltas := make([]models.UserStockTransaction, 0)

	for _, item := range req.Items {
		normISIN := normalizeISIN(item.ISIN)
		if normISIN == "" && strings.TrimSpace(item.ISIN) != "" {
			log.Printf("import: invalid ISIN for %s: %q", item.Symbol, item.ISIN)
		}

		stock, err := h.findOrCreateStock(item.Symbol, item.Name, item.ISIN)
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		fetchFailed := needsYahooAnyData(&stock)

		createdMapping := false
		if fetchFailed && strings.TrimSpace(item.ISIN) != "" {
			createdMapping, err = EnsureSymbolMappingFromISIN(tx, item.Symbol, item.ISIN, source)
			if err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}
		if createdMapping {
			h.applyYahooDataToStock(item.Symbol, &stock)
			h.persistYahooStockFields(&stock)
		}

		if sector := strings.TrimSpace(item.Sector); sector != "" && strings.TrimSpace(stock.Sector) == "" {
			stock.Sector = sector
			if err := tx.Model(&stock).Update("sector", sector).Error; err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}

		qty := item.Quantity
		if watchList && qty > 0 {
			qty = 1
		}
		currentPrice := stock.CurrentPrice
		if currentPrice <= 0 {
			currentPrice = yahooPriceForUpload(stock.Symbol)
		}
		pos, delta, err := applyUploadPosition(tx, userID, stock.ID, stock.Symbol, source, qty, item.Price, item.TransactionDate, watchList, currentPrice)
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if pos.ID != 0 {
			touchedStockIDs[stock.ID] = struct{}{}
			result = append(result, pos)
		}
		if delta != nil {
			deltas = append(deltas, *delta)
		}
	}

	// Zero positions for this source that were not in the upload.
	var stale []models.UserStock
	if err := tx.Where("user_id = ? AND source = ? AND quantity > 0", userID, source).Find(&stale).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	zeroed := 0
	for _, t := range stale {
		if _, ok := touchedStockIDs[t.StockID]; ok {
			continue
		}
		var catalog models.Stock
		symbol := ""
		if err := tx.First(&catalog, t.StockID).Error; err == nil {
			symbol = catalog.Symbol
		}
		pos, delta, err := applyUploadPosition(tx, userID, t.StockID, symbol, source, 0, t.AvgBuyPrice, nil, false, 0)
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if pos.ID != 0 {
			result = append(result, pos)
		}
		if delta != nil {
			deltas = append(deltas, *delta)
		}
		zeroed++
	}

	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	_ = ReloadSymbolCache(h.DB)

	c.JSON(http.StatusCreated, gin.H{
		"count":        len(result),
		"zeroed":       zeroed,
		"positions":    result,
		"transactions": deltas,
	})
}

func (h *Handler) RebuildSourceLedger(c *gin.Context) {
	var req struct {
		Source string              `json:"source" binding:"required"`
		Items  []ledgerRebuildItem `json:"items" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	source := strings.TrimSpace(req.Source)
	if source != models.SourceICICIDirect {
		c.JSON(http.StatusBadRequest, gin.H{"error": "source must be ICICIDirect"})
		return
	}
	if len(req.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "items cannot be empty"})
		return
	}

	seen := make(map[string]struct{})
	created := make([]models.Stock, 0)
	for _, item := range req.Items {
		symbol := strings.ToUpper(strings.TrimSpace(item.Symbol))
		if symbol == "" {
			continue
		}
		if _, ok := seen[symbol]; ok {
			continue
		}
		seen[symbol] = struct{}{}
		stock, err := h.findOrCreateStockRecord(symbol, item.Name, item.ISIN)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		created = append(created, stock)
	}

	userID := middleware.CurrentUserID(c)
	if err := rebuildICICIDirectLedger(h.DB, userID, req.Items); err != nil {
		status := http.StatusBadRequest
		c.JSON(status, gin.H{"error": err.Error()})
		return
	}
	_ = ReloadSymbolCache(h.DB)
	h.enqueueStockYahooEnrichment(created, models.SourceFormatICICIDirect)

	c.JSON(http.StatusCreated, gin.H{
		"count":  len(req.Items),
		"source": source,
	})
}

func (h *Handler) MergeSourceLedger(c *gin.Context) {
	var req struct {
		Source string              `json:"source" binding:"required"`
		Items  []partialLedgerItem `json:"items" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	source := strings.TrimSpace(req.Source)
	if !models.IsPartialLedgerImportSource(source) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "source must be HDFCSec, Zerodha, or Manual Bulk Upload"})
		return
	}
	if len(req.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "items cannot be empty"})
		return
	}

	resolved, unmapped, created, err := h.resolvePartialLedgerItems(source, req.Items)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if len(resolved) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":    "no mappable trade rows",
			"unmapped": unmapped,
		})
		return
	}

	userID := middleware.CurrentUserID(c)
	if err := mergePartialTradeLedger(h.DB, userID, source, resolved); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	_ = ReloadSymbolCache(h.DB)
	sourceFormat := models.SourceFormatManual
	switch source {
	case models.SourceHDFCSec:
		sourceFormat = "HDFCSec"
	case models.SourceZerodha:
		sourceFormat = "Zerodha"
	}
	h.enqueueStockYahooEnrichment(created, sourceFormat)

	c.JSON(http.StatusCreated, gin.H{
		"count":    len(resolved),
		"source":   source,
		"unmapped": unmapped,
	})
}

// resolvePartialLedgerItems maps upload rows to stock IDs.
// HDFCSec: name lookup only (unmapped names skipped). Zerodha/Bulk: symbol or ISIN, create if needed.
func (h *Handler) resolvePartialLedgerItems(source string, items []partialLedgerItem) (
	resolved []resolvedPartialItem,
	unmapped []string,
	created []models.Stock,
	err error,
) {
	unmappedSet := map[string]struct{}{}
	seenCreate := map[uint]struct{}{}

	// HDFCSec matches by company name; load Global_Stocks once (avoids N full-table scans).
	var nameIndex map[string]models.Stock
	if source == models.SourceHDFCSec {
		idx, loadErr := loadStockNameIndex(h.DB)
		if loadErr != nil {
			return nil, nil, nil, loadErr
		}
		nameIndex = idx
	}

	for _, item := range items {
		action := strings.TrimSpace(item.Action)
		if action == "" || item.Quantity <= 1e-9 || item.TransactionDate.IsZero() {
			continue
		}
		var stock models.Stock
		switch source {
		case models.SourceHDFCSec:
			name := strings.TrimSpace(item.Name)
			if name == "" {
				name = strings.TrimSpace(item.Symbol)
			}
			if name == "" {
				continue
			}
			found, ok := lookupStockByNormalizedName(nameIndex, name)
			if !ok {
				if _, seen := unmappedSet[name]; !seen {
					unmappedSet[name] = struct{}{}
					unmapped = append(unmapped, name)
				}
				continue
			}
			stock = found
		default:
			symbol := strings.ToUpper(strings.TrimSpace(item.Symbol))
			isin := strings.ToUpper(strings.TrimSpace(item.ISIN))
			if symbol == "" && isin != "" {
				found, ok, findErr := findStockByISIN(h.DB, isin)
				if findErr != nil {
					return nil, nil, nil, findErr
				}
				if ok {
					stock = found
				} else {
					// Cannot invent a symbol from ISIN alone without a ticker.
					key := "ISIN:" + isin
					if _, seen := unmappedSet[key]; !seen {
						unmappedSet[key] = struct{}{}
						unmapped = append(unmapped, key)
					}
					continue
				}
			} else if symbol == "" {
				continue
			} else {
				s, createErr := h.findOrCreateStockRecord(symbol, item.Name, item.ISIN)
				if createErr != nil {
					return nil, nil, nil, createErr
				}
				stock = s
			}
		}
		if _, ok := seenCreate[stock.ID]; !ok {
			seenCreate[stock.ID] = struct{}{}
			created = append(created, stock)
		}
		resolved = append(resolved, resolvedPartialItem{
			StockID:            stock.ID,
			Action:             action,
			Quantity:           item.Quantity,
			Price:              item.Price,
			TransactionDate:    item.TransactionDate,
			Brokerage:          item.Brokerage,
			TransactionCharges: item.TransactionCharges,
			StampDuty:          item.StampDuty,
			Segment:            item.Segment,
			STT:                item.STT,
			Exchange:           item.Exchange,
		})
	}
	return resolved, unmapped, created, nil
}

func (h *Handler) CreateSellTransaction(c *gin.Context) {
	var req struct {
		Symbol          string    `json:"symbol" binding:"required"`
		Quantity        float64   `json:"quantity" binding:"required"`
		Price           float64   `json:"price" binding:"required"`
		TransactionDate time.Time `json:"transaction_date" binding:"required"`
		Source          string    `json:"source"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := middleware.CurrentUserID(c)
	source := normalizeSource(req.Source)

	var stock models.Stock
	if err := h.DB.Where("symbol = ?", req.Symbol).First(&stock).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	ledger, _, err := applyManualStockTransaction(
		h.DB, userID, stock.ID, models.TransactionTypeSell,
		req.Quantity, req.Price, req.TransactionDate, source,
	)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, ledger)
}

// MarkStockHold sets last hold price/date on User_Stocks for recommendation baseline.
func (h *Handler) MarkStockHold(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stock id"})
		return
	}

	var req struct {
		Source string     `json:"source"`
		Price  float64    `json:"price" binding:"required"`
		HeldAt *time.Time `json:"held_at"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.Price <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "price must be greater than 0"})
		return
	}

	userID := middleware.CurrentUserID(c)
	source := normalizeSource(req.Source)
	heldAt := time.Now()
	if req.HeldAt != nil {
		heldAt = *req.HeldAt
	}

	var stock models.Stock
	if err := h.DB.First(&stock, uint(id)).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var pos models.UserStock
	if err := h.DB.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stock.ID, source).
		First(&pos).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "holding not found for this source"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	pos.LastHoldPrice = req.Price
	pos.LastHoldDate = &heldAt
	pos.LastHoldTrend = strings.TrimSpace(stock.Trend)
	clearPriceThresholds(&pos)
	pos.BSHClearDate = nil
	if err := h.DB.Save(&pos).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"stock_id":        pos.StockID,
		"source":          pos.Source,
		"last_hold_price": pos.LastHoldPrice,
		"last_hold_date":  pos.LastHoldDate,
	})
}

// SetStockThresholds updates buy / book-profit / stop-loss price thresholds on User_Stocks.
func (h *Handler) SetStockThresholds(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stock id"})
		return
	}

	var req struct {
		Source                string  `json:"source"`
		SetBuyPrice           float64 `json:"set_buy_price"`
		SetProfitBookingPrice float64 `json:"set_profit_booking_price"`
		SetStopLossPrice      float64 `json:"set_stop_loss_price"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.SetBuyPrice < 0 || req.SetProfitBookingPrice < 0 || req.SetStopLossPrice < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "threshold prices cannot be negative"})
		return
	}

	userID := middleware.CurrentUserID(c)
	source := normalizeSource(req.Source)

	var stock models.Stock
	if err := h.DB.First(&stock, uint(id)).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var pos models.UserStock
	if err := h.DB.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stock.ID, source).
		First(&pos).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "holding not found for this source"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	pos.SetBuyPrice = req.SetBuyPrice
	pos.SetProfitBookingPrice = req.SetProfitBookingPrice
	pos.SetStopLossPrice = req.SetStopLossPrice
	if err := h.DB.Save(&pos).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"stock_id":                 pos.StockID,
		"source":                   pos.Source,
		"set_buy_price":            pos.SetBuyPrice,
		"set_profit_booking_price": pos.SetProfitBookingPrice,
		"set_stop_loss_price":      pos.SetStopLossPrice,
	})
}

const maxStockNotesRunes = 200

// SetStockNotes updates the free-text note on a User_Stocks holding.
func (h *Handler) SetStockNotes(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stock id"})
		return
	}

	var req struct {
		Source string `json:"source"`
		Notes  string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	notes := strings.TrimSpace(req.Notes)
	if utf8.RuneCountInString(notes) > maxStockNotesRunes {
		c.JSON(http.StatusBadRequest, gin.H{"error": "notes cannot exceed 200 characters"})
		return
	}

	userID := middleware.CurrentUserID(c)
	source := normalizeSource(req.Source)

	var stock models.Stock
	if err := h.DB.First(&stock, uint(id)).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var pos models.UserStock
	if err := h.DB.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stock.ID, source).
		First(&pos).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "holding not found for this source"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	pos.Notes = notes
	if err := h.DB.Save(&pos).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"stock_id": pos.StockID,
		"source":   pos.Source,
		"notes":    pos.Notes,
	})
}

func (h *Handler) GetTransactions(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	symbol := c.Query("symbol")
	var transactions []models.UserStockTransaction

	query := h.DB.Preload("Stock").Where("user_id = ?", userID)
	if symbol != "" {
		var stock models.Stock
		if err := h.DB.Where("symbol = ?", symbol).First(&stock).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
			return
		}
		query = query.Where("stock_id = ?", stock.ID)
	}

	if err := query.Order("transaction_date DESC").Find(&transactions).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if transactions == nil {
		transactions = []models.UserStockTransaction{}
	}

	c.JSON(http.StatusOK, transactions)
}

func (h *Handler) GetStockTransactions(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	symbol := c.Param("symbol")

	var stock models.Stock
	if err := h.DB.Where("symbol = ?", symbol).First(&stock).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
		return
	}

	var transactions []models.UserStockTransaction
	if err := h.DB.Where("user_id = ? AND stock_id = ?", userID, stock.ID).
		Order("transaction_date DESC").
		Find(&transactions).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if transactions == nil {
		transactions = []models.UserStockTransaction{}
	}

	c.JSON(http.StatusOK, transactions)
}

func fetchYahooFinancePrice(symbol string) (float64, error) {
	return fetchYahooFinancePriceForTicker(resolveYahooSymbol(symbol))
}

func fetchYahooFinancePriceForTicker(nseBase string) (float64, error) {
	nseBase = strings.TrimSpace(nseBase)
	if nseBase == "" {
		return 0, fmt.Errorf("empty ticker")
	}
	// Prefer Indian exchanges so short codes like TMCV don't match unrelated US tickers.
	suffixes := []string{".NS", ".BO", ""}
	client := &http.Client{Timeout: 8 * time.Second}

	for _, suffix := range suffixes {
		reqURL := yahooChartURLDirect(nseBase, suffix, "interval=1d&range=1d")
		req, err := http.NewRequest("GET", reqURL, nil)
		if err != nil {
			continue
		}
		req.Header.Set("User-Agent", "Mozilla/5.0")

		resp, err := client.Do(req)
		if err != nil || resp.StatusCode != http.StatusOK {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}
		defer resp.Body.Close()

		var result struct {
			Chart struct {
				Result []struct {
					Meta struct {
						RegularMarketPrice float64 `json:"regularMarketPrice"`
					} `json:"meta"`
				} `json:"result"`
				Error interface{} `json:"error"`
			} `json:"chart"`
		}

		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
			continue
		}
		if result.Chart.Error != nil {
			continue
		}
		if len(result.Chart.Result) > 0 && result.Chart.Result[0].Meta.RegularMarketPrice > 0 {
			return result.Chart.Result[0].Meta.RegularMarketPrice, nil
		}
	}
	return 0, fmt.Errorf("price not found for %s", nseBase)
}

func fetchYahooFinanceAssetProfile(symbol string) (sector, industry string, err error) {
	suffixes := []string{".NS", ".BO", ""}
	resolved := resolveYahooSymbol(symbol)

	for _, suffix := range suffixes {
		reqURL := fmt.Sprintf(
			"https://query1.finance.yahoo.com/v10/finance/quoteSummary/%s%s?modules=assetProfile",
			url.PathEscape(resolved),
			suffix,
		)
		req, err := http.NewRequest("GET", reqURL, nil)
		if err != nil {
			continue
		}

		resp, err := yahooDo(req)
		if err != nil || resp.StatusCode != http.StatusOK {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}

		var result struct {
			QuoteSummary struct {
				Result []struct {
					AssetProfile struct {
						Sector   string `json:"sector"`
						Industry string `json:"industry"`
					} `json:"assetProfile"`
				} `json:"result"`
				Error interface{} `json:"error"`
			} `json:"quoteSummary"`
		}

		decodeErr := json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		if decodeErr != nil {
			continue
		}
		if result.QuoteSummary.Error != nil {
			continue
		}
		if len(result.QuoteSummary.Result) > 0 {
			ap := result.QuoteSummary.Result[0].AssetProfile
			if ap.Sector != "" || ap.Industry != "" {
				sector, industry := ap.Sector, ap.Industry
				if industry == "" && sector != "" {
					industry = sector
				}
				return sector, industry, nil
			}
		}
	}

	// Fallback: Use a simple sector mapping for common Indian stocks
	sectorMap := map[string]string{
		"TCS":        "Technology",
		"INFY":       "Technology",
		"WIPRO":      "Technology",
		"HCLTECH":    "Technology",
		"RELIANCE":   "Energy",
		"ADANIENT":   "Conglomerates",
		"ADANIPORTS": "Infrastructure",
		"ADANIGREEN": "Energy",
		"BAJFINANCE": "Financial Services",
		"HDFCBANK":   "Financial Services",
		"ICICIBANK":  "Financial Services",
		"SBIN":       "Financial Services",
		"KOTAKBANK":  "Financial Services",
		"AXISBANK":   "Financial Services",
		"ITC":        "Consumer Goods",
		"HINDUNILVR": "Consumer Goods",
		"NESTLEIND":  "Consumer Goods",
		"TATAMOTORS": "Automobile",
		"TMPV":       "Automobile",
		"TMCV":       "Automobile",
		"M&M":        "Automobile",
		"MARUTI":     "Automobile",
		"HEROMOTOCO": "Automobile",
		"TVSMOTOR":   "Automobile",
		"LT":         "Infrastructure",
		"SUNPHARMA":  "Healthcare",
		"DRREDDY":    "Healthcare",
		"CIPLA":      "Healthcare",
		"ULTRACEMCO": "Materials",
		"ORIENTCEM":  "Materials",
		"STARCEMENT": "Materials",
		"ACC":        "Materials",
		"TITAN":      "Consumer Cyclical",
		"GODREJCP":   "Consumer Defensive",
		"DLF":        "Real Estate",
		"PHOENIXLTD": "Real Estate",
		"COROMANDEL": "Basic Materials",
		"CROMPTON":   "Consumer Cyclical",
		"GREENPLY":   "Basic Materials",
		"NCC":        "Industrials",
		"JIOFIN":     "Financial Services",
		"IDFCFIRSTB": "Financial Services",
		"HDFCGOLD":   "Financial Services",
		"GOLDIETF":   "Financial Services",
		"NIFTYIETF":  "Financial Services",
		"MID150BEES": "Financial Services",
	}

	if s, exists := sectorMap[resolved]; exists {
		return s, s, nil
	}
	if s, exists := sectorMap[symbol]; exists {
		return s, s, nil
	}

	return "", "", fmt.Errorf("sector not found for %s", symbol)
}

// classifyMarketCap maps Yahoo marketCap (INR rupees for .NS/.BO) to Indian segment labels.
func classifyMarketCap(value float64) string {
	if value <= 0 {
		return ""
	}
	const (
		crore       = 1e7
		largeCapMin = 20000 * crore // ₹20,000 crore
		midCapMin   = 5000 * crore  // ₹5,000 crore
	)
	if value >= largeCapMin {
		return "Large Cap"
	}
	if value >= midCapMin {
		return "Mid Cap"
	}
	return "Small Cap"
}

func fetchYahooFinanceMarketCap(symbol string) (float64, error) {
	suffixes := []string{".NS", ".BO", ""}
	resolved := resolveYahooSymbol(symbol)

	for _, suffix := range suffixes {
		reqURL := fmt.Sprintf(
			"https://query1.finance.yahoo.com/v10/finance/quoteSummary/%s%s?modules=summaryDetail,price",
			url.PathEscape(resolved),
			suffix,
		)
		req, err := http.NewRequest("GET", reqURL, nil)
		if err != nil {
			continue
		}

		resp, err := yahooDo(req)
		if err != nil || resp.StatusCode != http.StatusOK {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}

		var result struct {
			QuoteSummary struct {
				Result []struct {
					SummaryDetail struct {
						MarketCap struct {
							Raw float64 `json:"raw"`
						} `json:"marketCap"`
					} `json:"summaryDetail"`
					Price struct {
						MarketCap struct {
							Raw float64 `json:"raw"`
						} `json:"marketCap"`
					} `json:"price"`
				} `json:"result"`
				Error interface{} `json:"error"`
			} `json:"quoteSummary"`
		}

		decodeErr := json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		if decodeErr != nil {
			continue
		}
		if result.QuoteSummary.Error != nil {
			continue
		}
		if len(result.QuoteSummary.Result) == 0 {
			continue
		}
		row := result.QuoteSummary.Result[0]
		if row.SummaryDetail.MarketCap.Raw > 0 {
			return row.SummaryDetail.MarketCap.Raw, nil
		}
		if row.Price.MarketCap.Raw > 0 {
			return row.Price.MarketCap.Raw, nil
		}
	}

	return 0, fmt.Errorf("market cap not found for %s", symbol)
}

func fetchSixthHighestPrice(symbol string) (float64, error) {
	suffixes := []string{".NS", ".BO", ""}
	client := &http.Client{Timeout: 10 * time.Second}

	for _, suffix := range suffixes {
		reqURL := yahooChartURL(symbol, suffix, "interval=1d&range=1y")
		req, err := http.NewRequest("GET", reqURL, nil)
		if err != nil {
			continue
		}
		req.Header.Set("User-Agent", "Mozilla/5.0")

		resp, err := client.Do(req)
		if err != nil || resp.StatusCode != http.StatusOK {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}
		defer resp.Body.Close()

		var result struct {
			Chart struct {
				Result []struct {
					Indicators struct {
						Quote []struct {
							High []interface{} `json:"high"`
						} `json:"quote"`
					} `json:"indicators"`
				} `json:"result"`
				Error interface{} `json:"error"`
			} `json:"chart"`
		}

		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
			continue
		}
		if result.Chart.Error != nil || len(result.Chart.Result) == 0 {
			continue
		}

		chartResult := result.Chart.Result[0]
		if len(chartResult.Indicators.Quote) == 0 {
			continue
		}

		var highs []float64
		for _, v := range chartResult.Indicators.Quote[0].High {
			if v != nil {
				if f, ok := v.(float64); ok && f > 0 {
					highs = append(highs, f)
				}
			}
		}

		if len(highs) < 6 {
			return 0, fmt.Errorf("insufficient data for %s", symbol)
		}

		// Sort in descending order
		for i := 0; i < len(highs); i++ {
			for j := i + 1; j < len(highs); j++ {
				if highs[i] < highs[j] {
					highs[i], highs[j] = highs[j], highs[i]
				}
			}
		}

		// Return the 6th highest (index 5)
		return highs[5], nil
	}
	return 0, fmt.Errorf("data not found for %s", symbol)
}

func fetchSixthLowestPrice(symbol string) (float64, error) {
	suffixes := []string{".NS", ".BO", ""}
	client := &http.Client{Timeout: 10 * time.Second}

	for _, suffix := range suffixes {
		reqURL := yahooChartURL(symbol, suffix, "interval=1d&range=1y")
		req, err := http.NewRequest("GET", reqURL, nil)
		if err != nil {
			continue
		}
		req.Header.Set("User-Agent", "Mozilla/5.0")

		resp, err := client.Do(req)
		if err != nil || resp.StatusCode != http.StatusOK {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}
		defer resp.Body.Close()

		var result struct {
			Chart struct {
				Result []struct {
					Indicators struct {
						Quote []struct {
							Low []interface{} `json:"low"`
						} `json:"quote"`
					} `json:"indicators"`
				} `json:"result"`
				Error interface{} `json:"error"`
			} `json:"chart"`
		}

		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
			continue
		}
		if result.Chart.Error != nil || len(result.Chart.Result) == 0 {
			continue
		}

		chartResult := result.Chart.Result[0]
		if len(chartResult.Indicators.Quote) == 0 {
			continue
		}

		var lows []float64
		for _, v := range chartResult.Indicators.Quote[0].Low {
			if v != nil {
				if f, ok := v.(float64); ok && f > 0 {
					lows = append(lows, f)
				}
			}
		}

		if len(lows) < 6 {
			return 0, fmt.Errorf("insufficient data for %s", symbol)
		}

		// Sort in ascending order
		for i := 0; i < len(lows); i++ {
			for j := i + 1; j < len(lows); j++ {
				if lows[i] > lows[j] {
					lows[i], lows[j] = lows[j], lows[i]
				}
			}
		}

		// Return the 6th lowest (index 5)
		return lows[5], nil
	}
	return 0, fmt.Errorf("data not found for %s", symbol)
}

type StockTrend struct {
	StockID         uint    `json:"stock_id"`
	Symbol          string  `json:"symbol"`
	CurrentPrice    float64 `json:"current_price"`
	MA7             float64 `json:"ma7"`
	MA20            float64 `json:"ma20"`
	MA50            float64 `json:"ma50"`
	StockSTDelta    float64 `json:"stock_st_delta"`
	MarketSTDelta   float64 `json:"market_st_delta"`
	AdjustedSTDelta float64 `json:"adjusted_st_delta"`
	StockMTDelta    float64 `json:"stock_mt_delta"`
	MarketMTDelta   float64 `json:"market_mt_delta"`
	AdjustedMTDelta float64 `json:"adjusted_mt_delta"`
	Trend           string  `json:"trend"`
}

func calcSimpleMovingAverage(closes []float64, period int) float64 {
	if len(closes) < period || period <= 0 {
		return 0
	}
	sum := 0.0
	for _, c := range closes[len(closes)-period:] {
		sum += c
	}
	return sum / float64(period)
}

func calcDelta(shorter, longer float64) float64 {
	if longer <= 0 {
		return 0
	}
	return ((shorter - longer) / longer) * 100
}

func fetchMovingAverages(symbol string) (currentPrice, ma7, ma20, ma50, stDelta, mtDelta float64, err error) {
	suffixes := []string{".NS", ".BO", ""}
	client := &http.Client{Timeout: 10 * time.Second}

	for _, suffix := range suffixes {
		reqURL := yahooChartURL(symbol, suffix, "interval=1d&range=3mo")
		req, e := http.NewRequest("GET", reqURL, nil)
		if e != nil {
			continue
		}
		req.Header.Set("User-Agent", "Mozilla/5.0")

		resp, e := client.Do(req)
		if e != nil || resp.StatusCode != http.StatusOK {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}
		defer resp.Body.Close()

		var result struct {
			Chart struct {
				Result []struct {
					Meta struct {
						RegularMarketPrice float64 `json:"regularMarketPrice"`
					} `json:"meta"`
					Indicators struct {
						Quote []struct {
							Close []interface{} `json:"close"`
						} `json:"quote"`
					} `json:"indicators"`
				} `json:"result"`
				Error interface{} `json:"error"`
			} `json:"chart"`
		}

		if e := json.NewDecoder(resp.Body).Decode(&result); e != nil {
			continue
		}
		if result.Chart.Error != nil || len(result.Chart.Result) == 0 {
			continue
		}

		chartResult := result.Chart.Result[0]
		currentPrice = chartResult.Meta.RegularMarketPrice

		if len(chartResult.Indicators.Quote) == 0 {
			continue
		}

		var closes []float64
		for _, v := range chartResult.Indicators.Quote[0].Close {
			if v != nil {
				if f, ok := v.(float64); ok && f > 0 {
					closes = append(closes, f)
				}
			}
		}

		if len(closes) < 7 {
			return 0, 0, 0, 0, 0, 0, fmt.Errorf("insufficient data for %s", symbol)
		}

		ma7 = calcSimpleMovingAverage(closes, 7)
		ma20 = calcSimpleMovingAverage(closes, 20)
		ma50 = calcSimpleMovingAverage(closes, 50)
		if ma20 > 0 {
			stDelta = calcDelta(ma7, ma20)
		}
		if ma50 > 0 {
			mtDelta = calcDelta(ma20, ma50)
		}

		return currentPrice, ma7, ma20, ma50, stDelta, mtDelta, nil
	}
	return 0, 0, 0, 0, 0, 0, fmt.Errorf("data not found for %s", symbol)
}

func classifyTrend(rs trendrules.Ruleset, currentPrice, ma7, ma20, ma50, adjustedSTDelta, adjustedMTDelta float64) string {
	return trendrules.Evaluate(rs, trendrules.Inputs{
		CurrPrice:       currentPrice,
		MA7:             ma7,
		MA20:            ma20,
		MA50:            ma50,
		AdjustedSTDelta: adjustedSTDelta,
		AdjustedMTDelta: adjustedMTDelta,
	})
}

func needsTrendData(stock *models.Stock, today time.Time) bool {
	if stock == nil {
		return true
	}
	if !isSameCalendarDay(stock.LastTrendFetchedDate, today) {
		return true
	}
	if stock.MA7 == 0 || stock.MA20 == 0 || stock.MA50 == 0 {
		return true
	}
	trend := strings.TrimSpace(stock.Trend)
	return trend == "" || trend == "unknown"
}

func applyTrendToStock(
	rs trendrules.Ruleset,
	stock *models.Stock,
	currentPrice, ma7, ma20, ma50, sensexMA7, sensexMA20, sensexMA50, stockSTDelta, marketSTDelta, stockMTDelta, marketMTDelta float64,
	now time.Time,
) {
	adjustedSTDelta := stockSTDelta - marketSTDelta
	adjustedMTDelta := stockMTDelta - marketMTDelta
	stock.MA7 = ma7
	stock.MA20 = ma20
	stock.MA50 = ma50
	stock.SensexMA7 = sensexMA7
	stock.SensexMA20 = sensexMA20
	stock.SensexMA50 = sensexMA50
	stock.StockSTDelta = stockSTDelta
	stock.MarketSTDelta = marketSTDelta
	stock.AdjustedSTDelta = adjustedSTDelta
	stock.StockMTDelta = stockMTDelta
	stock.MarketMTDelta = marketMTDelta
	stock.AdjustedMTDelta = adjustedMTDelta
	stock.Trend = classifyTrend(rs, currentPrice, ma7, ma20, ma50, adjustedSTDelta, adjustedMTDelta)
	stock.LastTrendFetchedDate = &now
	if currentPrice > 0 {
		stock.CurrentPrice = currentPrice
	}
}

func (h *Handler) persistTrendFields(stock *models.Stock) {
	updates := map[string]interface{}{
		"ma7":                     stock.MA7,
		"ma20":                    stock.MA20,
		"ma50":                    stock.MA50,
		"sensex_ma7":              stock.SensexMA7,
		"sensex_ma20":             stock.SensexMA20,
		"sensex_ma50":             stock.SensexMA50,
		"stock_st_delta":          stock.StockSTDelta,
		"market_st_delta":         stock.MarketSTDelta,
		"adjusted_st_delta":       stock.AdjustedSTDelta,
		"stock_mt_delta":          stock.StockMTDelta,
		"market_mt_delta":         stock.MarketMTDelta,
		"adjusted_mt_delta":       stock.AdjustedMTDelta,
		"trend":                   stock.Trend,
		"last_trend_fetched_date": stock.LastTrendFetchedDate,
	}
	if stock.CurrentPrice > 0 {
		updates["current_price"] = stock.CurrentPrice
	}
	_ = h.DB.Model(stock).Updates(updates).Error
}

func stockTrendFromStock(stock models.Stock) StockTrend {
	price := stock.CurrentPrice
	return StockTrend{
		StockID:         stock.ID,
		Symbol:          stock.Symbol,
		CurrentPrice:    price,
		MA7:             stock.MA7,
		MA20:            stock.MA20,
		MA50:            stock.MA50,
		StockSTDelta:    stock.StockSTDelta,
		MarketSTDelta:   stock.MarketSTDelta,
		AdjustedSTDelta: stock.AdjustedSTDelta,
		StockMTDelta:    stock.StockMTDelta,
		MarketMTDelta:   stock.MarketMTDelta,
		AdjustedMTDelta: stock.AdjustedMTDelta,
		Trend:           stock.Trend,
	}
}

func (h *Handler) fetchAndPersistStockTrend(stock *models.Stock, rs trendrules.Ruleset, sensexMA7, sensexMA20, sensexMA50, marketSTDelta, marketMTDelta float64, now time.Time) error {
	res, err := dailyclose.SyncYahooHistory(h.DB, stock.Symbol, resolveYahooSymbol(stock.Symbol), nil, now)
	if err != nil {
		return err
	}
	if sensexMA7 == 0 && sensexMA20 == 0 {
		sensexMA7, sensexMA20, sensexMA50 = stock.SensexMA7, stock.SensexMA20, stock.SensexMA50
		marketSTDelta, marketMTDelta = stock.MarketSTDelta, stock.MarketMTDelta
	}
	price := res.LatestClose
	if price <= 0 {
		price = stock.CurrentPrice
	}
	applyTrendToStock(rs, stock, price, res.MA7, res.MA20, res.MA50, sensexMA7, sensexMA20, sensexMA50, res.STDelta, marketSTDelta, res.MTDelta, marketMTDelta, now)
	if !res.Skipped {
		if res.SixthHigh > 0 {
			stock.SixthHighestPrice = res.SixthHigh
		}
		if res.SixthLow > 0 {
			stock.SixthLowestPrice = res.SixthLow
		}
		stock.LastFetchedDate = &now
	}
	h.persistTrendFields(stock)
	if !res.Skipped && (res.SixthHigh > 0 || res.SixthLow > 0) {
		_ = h.DB.Model(stock).Updates(map[string]interface{}{
			"sixth_highest_price": stock.SixthHighestPrice,
			"sixth_lowest_price":  stock.SixthLowestPrice,
			"last_fetched_date":   stock.LastFetchedDate,
		}).Error
	}
	return nil
}

func (h *Handler) syncSensexHistory(now time.Time) (dailyclose.SyncResult, error) {
	res, err := dailyclose.SyncYahooHistory(h.DB, dailyclose.SensexSymbol, dailyclose.SensexYahooTicker, []string{""}, now)
	if err != nil {
		return res, err
	}
	if res.MA7 == 0 && res.MA20 == 0 {
		if ma7, ma20, ma50, _, _, ok := dailyclose.LoadLatestMAs(h.DB, dailyclose.SensexSymbol); ok {
			res.MA7, res.MA20, res.MA50 = ma7, ma20, ma50
			res.STDelta = calcDelta(ma7, ma20)
			res.MTDelta = calcDelta(ma20, ma50)
		}
	}
	return res, nil
}

type HistoricalDataPoint struct {
	Date  string  `json:"date"`
	Price float64 `json:"price"`
}

func (h *Handler) GetStockHistory(c *gin.Context) {
	symbol := c.Query("symbol")
	if symbol == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "symbol is required"})
		return
	}

	suffixes := []string{".NS", ".BO", ""}
	client := &http.Client{Timeout: 10 * time.Second}
	history := make([]HistoricalDataPoint, 0)

	for _, suffix := range suffixes {
		reqURL := yahooChartURL(symbol, suffix, "interval=1d&range=1y")
		req, e := http.NewRequest("GET", reqURL, nil)
		if e != nil {
			continue
		}
		req.Header.Set("User-Agent", "Mozilla/5.0")

		resp, e := client.Do(req)
		if e != nil || resp.StatusCode != http.StatusOK {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}
		defer resp.Body.Close()

		var result struct {
			Chart struct {
				Result []struct {
					Timestamp  []int64 `json:"timestamp"`
					Indicators struct {
						Quote []struct {
							Close []interface{} `json:"close"`
						} `json:"quote"`
					} `json:"indicators"`
				} `json:"result"`
				Error interface{} `json:"error"`
			} `json:"chart"`
		}

		if e := json.NewDecoder(resp.Body).Decode(&result); e != nil {
			continue
		}
		if result.Chart.Error != nil || len(result.Chart.Result) == 0 {
			continue
		}

		chartResult := result.Chart.Result[0]
		if len(chartResult.Indicators.Quote) == 0 {
			continue
		}

		closes := chartResult.Indicators.Quote[0].Close
		timestamps := chartResult.Timestamp

		for i := 0; i < len(timestamps); i++ {
			if i < len(closes) && closes[i] != nil {
				if f, ok := closes[i].(float64); ok && f > 0 {
					date := time.Unix(timestamps[i], 0).Format("2006-01-02")
					history = append(history, HistoricalDataPoint{
						Date:  date,
						Price: f,
					})
				}
			}
		}

		if len(history) > 0 {
			break
		}
	}

	if len(history) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "historical data not found"})
		return
	}

	c.JSON(http.StatusOK, history)
}

func (h *Handler) GetStockTrends(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	stocks, err := h.stocksForUser(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	trends := make([]StockTrend, 0, len(stocks))

	needsFetch := false
	for i := range stocks {
		if needsTrendData(&stocks[i], today) {
			needsFetch = true
			break
		}
	}

	var sensexMA7, sensexMA20, sensexMA50, marketSTDelta, marketMTDelta float64
	if needsFetch {
		if sx, err := h.syncSensexHistory(now); err == nil {
			sensexMA7, sensexMA20, sensexMA50 = sx.MA7, sx.MA20, sx.MA50
			marketSTDelta, marketMTDelta = sx.STDelta, sx.MTDelta
		}
	}

	trendRS := h.loadTrendRuleset()
	for i := range stocks {
		stock := &stocks[i]
		if !needsTrendData(stock, today) {
			trends = append(trends, stockTrendFromStock(*stock))
			continue
		}

		if err := h.fetchAndPersistStockTrend(stock, trendRS, sensexMA7, sensexMA20, sensexMA50, marketSTDelta, marketMTDelta, now); err != nil {
			trends = append(trends, StockTrend{
				StockID:      stock.ID,
				Symbol:       stock.Symbol,
				CurrentPrice: stock.CurrentPrice,
				Trend:        "unknown",
			})
			continue
		}
		trends = append(trends, stockTrendFromStock(*stock))
	}

	c.JSON(http.StatusOK, trends)
}

func (h *Handler) RefreshStockPrices(c *gin.Context) {
	if err := h.RefreshAllStockPricesAndTrends(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	userID := middleware.CurrentUserID(c)
	userStocks, err := h.stocksForUser(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.stocksWithHoldings(userStocks, userID))
}

// RefreshAllStockPricesAndTrends fetches Yahoo prices, historical highs/lows, and
// trend MAs for every Global_Stocks row (shared across users). Skips fields
// already fetched today. Used by POST /stocks/refresh-prices and the daily cron.
func (h *Handler) RefreshAllStockPricesAndTrends() error {
	var stocks []models.Stock
	if err := h.DB.Where("pull_data = ?", models.PullDataYes).Find(&stocks).Error; err != nil {
		return err
	}
	h.refreshStockPricesAndTrendsBatch(stocks, "RefreshStockPrices", yahooTargetNewsPolicy{}, false, 0)
	if err := h.RefreshNifty50CurrentValue(); err != nil {
		log.Printf("RefreshStockPrices: Nifty50 FAIL: %v", err)
	}
	return nil
}

// refreshConsensusForUserHoldings scrapes Trendlyne consensus targets for the
// current user's held symbols. In dev (consensusDevFetchLimit > 0) only the
// first N holdings are refreshed on every call; otherwise uses the 3-day cache.
func (h *Handler) refreshConsensusForUserHoldings(userID uint, today, now time.Time) {
	userStocks, err := h.stocksForUser(userID)
	if err != nil {
		log.Printf("RefreshStockConsensus: load user stocks FAIL: %v", err)
		return
	}
	sort.Slice(userStocks, func(i, j int) bool {
		return strings.ToUpper(userStocks[i].Symbol) < strings.ToUpper(userStocks[j].Symbol)
	})

	toFetch := make([]*models.Stock, 0)
	for i := range userStocks {
		if needsConsensusRefresh(userStocks[i].LastConsensusFetchedDate, today) {
			toFetch = append(toFetch, &userStocks[i])
		}
	}
	stale := len(toFetch)
	if stale == 0 {
		log.Printf("RefreshStockConsensus: all %d user holdings fresh", len(userStocks))
		return
	}
	// In dev each refresh scrapes only a slice of the stale holdings, so the
	// portfolio fills in progressively instead of re-fetching the same symbols.
	if consensusDevFetchLimit > 0 && stale > consensusDevFetchLimit {
		toFetch = toFetch[:consensusDevFetchLimit]
	}
	if consensusDevFetchLimit > 0 {
		log.Printf("RefreshStockConsensus: DEV mode — fetching %d of %d stale (%d holdings)",
			len(toFetch), stale, len(userStocks))
	} else {
		log.Printf("RefreshStockConsensus: refreshing %d of %d user holdings", len(toFetch), len(userStocks))
	}

	for _, s := range toFetch {
		result, usedSymbol, err := h.fetchConsensusWithMappedFallback(s)
		if err != nil {
			logConsensusFetchError(s.Symbol, usedSymbol, err)
			// Stamp the attempt so a permanently failing symbol doesn't block
			// the rest of the portfolio from being refreshed.
			s.LastConsensusFetchedDate = &now
			h.DB.Model(s).Update("last_consensus_fetched_date", now)
			continue
		}

		updates := map[string]interface{}{
			"trendlyne_url":               result.URL,
			"consensus_ltp":               result.LTP,
			"consensus_target":            result.Target,
			"consensus_upside":            result.Upside,
			"consensus_type":              result.Type,
			"last_consensus_fetched_date": now,
		}
		s.TrendlyneURL = result.URL
		s.ConsensusLTP = result.LTP
		s.ConsensusTarget = result.Target
		s.ConsensusUpside = result.Upside
		s.ConsensusType = result.Type
		s.LastConsensusFetchedDate = &now
		if result.HasDate {
			d := result.Date
			updates["consensus_date"] = d
			s.ConsensusDate = &d
		}

		if err := h.DB.Model(s).Updates(updates).Error; err != nil {
			log.Printf("RefreshStockConsensus [%s]: DB FAIL: %v", s.Symbol, err)
			continue
		}
		if !strings.EqualFold(usedSymbol, s.Symbol) {
			log.Printf("RefreshStockConsensus [%s]: OK via mapped=%s target=%.2f upside=%.2f type=%s url=%s",
				s.Symbol, usedSymbol, result.Target, result.Upside, result.Type, result.URL)
		} else {
			log.Printf("RefreshStockConsensus [%s]: OK target=%.2f upside=%.2f type=%s url=%s",
				s.Symbol, result.Target, result.Upside, result.Type, result.URL)
		}
	}
}

// consensusLookupCandidates returns symbols to try for Trendlyne, preferring the
// stock's source symbol then Global_SymbolMappings.yahoo_symbol when distinct.
// If the cached URL already belongs to the mapped symbol, start with the mapped
// symbol so we skip a known-failing source lookup.
func consensusLookupCandidates(sourceSymbol, mappedSymbol, cachedURL string) []string {
	source := strings.ToUpper(strings.TrimSpace(sourceSymbol))
	mapped := strings.ToUpper(strings.TrimSpace(mappedSymbol))
	cachedURL = strings.TrimSpace(cachedURL)

	hasDistinctMapped := mapped != "" && !strings.EqualFold(mapped, source)
	if hasDistinctMapped && cachedURL != "" && trendlyne.ValidateReportURL(mapped, cachedURL) {
		return []string{mapped}
	}

	out := make([]string, 0, 2)
	if source != "" {
		out = append(out, source)
	}
	if hasDistinctMapped {
		out = append(out, mapped)
	}
	return out
}

func shouldRetryConsensusWithMappedSymbol(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "URL_NOT_FOUND") || strings.Contains(msg, "PARSE_FAIL")
}

func pageURLForConsensusLookup(symbol, cachedURL string) string {
	cachedURL = strings.TrimSpace(cachedURL)
	if cachedURL == "" {
		return ""
	}
	if trendlyne.ValidateReportURL(symbol, cachedURL) {
		return cachedURL
	}
	return ""
}

func (h *Handler) fetchConsensusWithMappedFallback(s *models.Stock) (*trendlyne.ConsensusResult, string, error) {
	mapped := resolveYahooSymbol(s.Symbol)
	candidates := consensusLookupCandidates(s.Symbol, mapped, s.TrendlyneURL)
	var lastErr error
	lastSymbol := s.Symbol
	for i, sym := range candidates {
		pageURL := pageURLForConsensusLookup(sym, s.TrendlyneURL)
		if i > 0 {
			log.Printf("RefreshStockConsensus [%s]: retrying with mapped=%s", s.Symbol, sym)
		}
		result, err := trendlyne.FetchConsensus(sym, pageURL)
		if err == nil {
			return result, sym, nil
		}
		lastErr = err
		lastSymbol = sym
		if i+1 < len(candidates) && shouldRetryConsensusWithMappedSymbol(err) {
			continue
		}
		break
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("no consensus lookup candidates")
	}
	return nil, lastSymbol, lastErr
}

func logConsensusFetchError(sourceSymbol, usedSymbol string, err error) {
	msg := err.Error()
	prefix := sourceSymbol
	if usedSymbol != "" && !strings.EqualFold(usedSymbol, sourceSymbol) {
		prefix = fmt.Sprintf("%s via mapped=%s", sourceSymbol, usedSymbol)
	}
	switch {
	case strings.Contains(msg, "URL_NOT_FOUND"):
		log.Printf("RefreshStockConsensus [%s]: URL_NOT_FOUND: %v", prefix, err)
	case strings.Contains(msg, "FETCH_FAIL"):
		log.Printf("RefreshStockConsensus [%s]: FETCH_FAIL: %v", prefix, err)
	case strings.Contains(msg, "PARSE_FAIL"):
		log.Printf("RefreshStockConsensus [%s]: PARSE_FAIL: %v", prefix, err)
	default:
		log.Printf("RefreshStockConsensus [%s]: FAIL: %v", prefix, err)
	}
}

// Mutual Fund handlers
func (h *Handler) GetMutualFunds(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var mfs []models.MutualFund
	if err := h.DB.Where("user_id = ?", userID).Find(&mfs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if mfs == nil {
		mfs = []models.MutualFund{}
	}
	enrichUserMutualFundsNAV(h.DB, mfs)
	c.JSON(http.StatusOK, mfs)
}

func applyCatalogToUserMF(db *gorm.DB, mf *models.MutualFund) error {
	isin := strings.ToUpper(strings.TrimSpace(mf.ISIN))
	if isin == "" {
		return fmt.Errorf("isin is required (select a scheme from the catalog)")
	}
	global, err := findGlobalMutualFundByISIN(db, isin)
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return fmt.Errorf("isin not found in Global_MutualFunds catalog")
		}
		return err
	}
	mf.ISIN = global.ISIN
	if strings.TrimSpace(mf.SchemeCode) == "" {
		mf.SchemeCode = global.Symbol
	}
	if strings.TrimSpace(mf.SchemeName) == "" {
		mf.SchemeName = global.SchemeName
	}
	if mf.CurrentNAV <= 0 && global.CurrentNAV > 0 {
		mf.CurrentNAV = global.CurrentNAV
	}
	return nil
}

func (h *Handler) CreateMutualFund(c *gin.Context) {
	var mf models.MutualFund
	if err := c.ShouldBindJSON(&mf); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	mf.UserID = middleware.CurrentUserID(c)
	if strings.TrimSpace(mf.Source) == "" {
		mf.Source = models.SourceManualAdd
	}
	if h.userUsesWatchList(mf.UserID) {
		mf.Quantity = 1
	}
	if err := applyCatalogToUserMF(h.DB, &mf); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}
	if err := tx.Create(&mf).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if strings.TrimSpace(mf.Source) == models.SourceManualAdd {
		var txDate *time.Time
		if !mf.PurchaseDate.IsZero() {
			d := mf.PurchaseDate
			txDate = &d
		}
		if err := replaceManualAddMFPosition(
			tx, mf.UserID, mf.ISIN, mf.SourceSchemeName, mf.Quantity, mf.NAV, txDate,
		); err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	list := []models.MutualFund{mf}
	enrichUserMutualFundsNAV(h.DB, list)
	c.JSON(http.StatusCreated, list[0])
}

func (h *Handler) GetMutualFund(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var mf models.MutualFund
	if err := h.DB.Where("id = ? AND user_id = ?", uint(id), userID).First(&mf).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Mutual Fund not found"})
		return
	}
	list := []models.MutualFund{mf}
	enrichUserMutualFundsNAV(h.DB, list)
	c.JSON(http.StatusOK, list[0])
}

func (h *Handler) UpdateMutualFund(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var existing models.MutualFund
	if err := h.DB.Where("id = ? AND user_id = ?", uint(id), userID).First(&existing).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Mutual Fund not found"})
		return
	}
	var mf models.MutualFund
	if err := c.ShouldBindJSON(&mf); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	mf.ID = uint(id)
	mf.UserID = userID
	if strings.TrimSpace(mf.Source) == "" {
		mf.Source = models.SourceManualAdd
	}
	if h.userUsesWatchList(userID) {
		mf.Quantity = 1
	}
	// Legacy rows without ISIN may keep free-text edit until linked.
	if strings.TrimSpace(mf.ISIN) == "" && strings.TrimSpace(existing.ISIN) != "" {
		mf.ISIN = existing.ISIN
	}
	if strings.TrimSpace(mf.ISIN) != "" {
		if err := applyCatalogToUserMF(h.DB, &mf); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
	}

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}
	if err := tx.Save(&mf).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if strings.TrimSpace(mf.Source) == models.SourceManualAdd {
		var txDate *time.Time
		if !mf.PurchaseDate.IsZero() {
			d := mf.PurchaseDate
			txDate = &d
		}
		// If ISIN/name changed, clear ledger under the old key first.
		oldISIN := strings.ToUpper(strings.TrimSpace(existing.ISIN))
		newISIN := strings.ToUpper(strings.TrimSpace(mf.ISIN))
		oldName := strings.TrimSpace(existing.SourceSchemeName)
		newName := strings.TrimSpace(mf.SourceSchemeName)
		if oldISIN != newISIN || strings.ToLower(oldName) != strings.ToLower(newName) {
			if err := deleteMFTransactionsForHolding(tx, userID, existing.ISIN, existing.SourceSchemeName, existing.Source); err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}
		if err := replaceManualAddMFPosition(
			tx, userID, mf.ISIN, mf.SourceSchemeName, mf.Quantity, mf.NAV, txDate,
		); err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	list := []models.MutualFund{mf}
	enrichUserMutualFundsNAV(h.DB, list)
	c.JSON(http.StatusOK, list[0])
}

func (h *Handler) DeleteMutualFund(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var existing models.MutualFund
	if err := h.DB.Where("id = ? AND user_id = ?", uint(id), userID).First(&existing).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Mutual Fund not found"})
		return
	}

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}
	if err := deleteMFTransactionsForHolding(tx, userID, existing.ISIN, existing.SourceSchemeName, existing.Source); err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	res := tx.Where("id = ? AND user_id = ?", uint(id), userID).Delete(&models.MutualFund{})
	if res.Error != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
		return
	}
	if res.RowsAffected == 0 {
		tx.Rollback()
		c.JSON(http.StatusNotFound, gin.H{"error": "Mutual Fund not found"})
		return
	}
	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Mutual Fund deleted"})
}

// DeleteAllUserMutualFunds removes every User_MutualFunds and
// User_MutualFund_Transactions row for the current user. Shared catalog rows
// are left unchanged.
func (h *Handler) DeleteAllUserMutualFunds(c *gin.Context) {
	userID := middleware.CurrentUserID(c)

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}

	if err := tx.Where("user_id = ?", userID).Delete(&models.UserMutualFundTransaction{}).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	res := tx.Where("user_id = ?", userID).Delete(&models.MutualFund{})
	if res.Error != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
		return
	}
	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "All mutual funds deleted",
		"deleted": res.RowsAffected,
	})
}

// Portfolio handlers
func (h *Handler) GetPortfolio(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	stocks, err := h.stocksForUser(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	var mfs []models.MutualFund
	h.DB.Where("user_id = ?", userID).Find(&mfs)
	enrichUserMutualFundsNAV(h.DB, mfs)

	c.JSON(http.StatusOK, gin.H{
		"stocks":       h.stocksWithHoldings(stocks, userID),
		"mutual_funds": mfs,
	})
}

func (h *Handler) GetPortfolioSummary(c *gin.Context) {
	userID := middleware.CurrentUserID(c)

	// Build stock totals directly from User_Stocks so every source/account is included,
	// independent of catalog-wide queries or N+1 lookups.
	var positions []models.UserStock
	if err := h.DB.Where("user_id = ? AND quantity > 0", userID).Find(&positions).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var lots []models.UserStockTransaction
	if err := h.DB.Where("user_id = ? AND type = ?", userID, models.TransactionTypeBuy).
		Find(&lots).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	stockIDs := make([]uint, 0, len(positions))
	seenStock := map[uint]struct{}{}
	for _, pos := range positions {
		if _, ok := seenStock[pos.StockID]; ok {
			continue
		}
		seenStock[pos.StockID] = struct{}{}
		stockIDs = append(stockIDs, pos.StockID)
	}
	stockCount := len(seenStock)
	for _, lot := range lots {
		if _, ok := seenStock[lot.StockID]; ok {
			continue
		}
		if lot.Quantity <= 1e-9 {
			continue
		}
		seenStock[lot.StockID] = struct{}{}
		stockIDs = append(stockIDs, lot.StockID)
	}
	priceByID := map[uint]float64{}
	stockFYByID := map[uint]stockFYPrices{}
	if len(stockIDs) > 0 {
		var stocks []models.Stock
		if err := h.DB.Select("id, current_price, ltp_fy_2024, ltp_fy_2025").
			Where("id IN ?", stockIDs).Find(&stocks).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		for _, s := range stocks {
			priceByID[s.ID] = s.CurrentPrice
			stockFYByID[s.ID] = stockFYPrices{
				Current:   s.CurrentPrice,
				LtpFY2024: s.LtpFY2024,
				LtpFY2025: s.LtpFY2025,
			}
		}
	}

	var mfs []models.MutualFund
	if err := h.DB.Where("user_id = ? AND quantity > 0", userID).Find(&mfs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var mfLots []models.UserMutualFundTransaction
	if err := h.DB.Where("user_id = ? AND type = ?", userID, models.TransactionTypeBuy).
		Find(&mfLots).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	mfFYByISIN := map[string]mfFYPrices{}
	navByISIN := map[string]float64{}
	isinList := make([]string, 0)
	seenISIN := map[string]struct{}{}
	addISIN := func(raw string) {
		isin := strings.ToUpper(strings.TrimSpace(raw))
		if isin == "" {
			return
		}
		if _, ok := seenISIN[isin]; ok {
			return
		}
		seenISIN[isin] = struct{}{}
		isinList = append(isinList, isin)
	}
	for _, mf := range mfs {
		addISIN(mf.ISIN)
	}
	for _, lot := range mfLots {
		addISIN(lot.ISIN)
	}
	if len(isinList) > 0 {
		var globals []models.GlobalMutualFund
		if err := h.DB.Select("isin, current_nav, nav_fy_2024, nav_fy_2025").
			Where("UPPER(isin) IN ?", isinList).Find(&globals).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		for _, g := range globals {
			key := strings.ToUpper(strings.TrimSpace(g.ISIN))
			mfFYByISIN[key] = mfFYPrices{
				Current:   g.CurrentNAV,
				NavFY2024: g.NavFY2024,
				NavFY2025: g.NavFY2025,
			}
			navByISIN[key] = g.CurrentNAV
		}
	}
	// Unmatched holdings (no ISIN): fall back to broker current NAV for open-lot current value.
	navByUnmatchedName := map[string]float64{}
	for _, mf := range mfs {
		if strings.TrimSpace(mf.ISIN) != "" {
			continue
		}
		name := strings.ToLower(strings.TrimSpace(mf.SourceSchemeName))
		if name == "" || mf.CurrentNAV <= 0 {
			continue
		}
		navByUnmatchedName[name] = mf.CurrentNAV
	}

	totalInvested := 0.0
	currentValue := 0.0

	type sourceTotals struct {
		invested float64
		current  float64
		count    int
	}
	bySourceMap := map[string]sourceTotals{}
	byMFSourceMap := map[string]sourceTotals{}
	seenStockBySource := map[string]map[uint]struct{}{}
	seenMFBySource := map[string]map[string]struct{}{}

	for _, pos := range positions {
		src := strings.TrimSpace(pos.Source)
		if src == "" {
			src = models.SourceManualAdd
		}
		invested := pos.AvgBuyPrice * pos.Quantity
		current := priceByID[pos.StockID] * pos.Quantity
		totalInvested += invested
		currentValue += current

		t := bySourceMap[src]
		t.invested += invested
		t.current += current
		bySourceMap[src] = t

		seen := seenStockBySource[src]
		if seen == nil {
			seen = map[uint]struct{}{}
			seenStockBySource[src] = seen
		}
		seen[pos.StockID] = struct{}{}
	}

	// MF invested/current from open buy lots (same cost basis as stock open-lot recompute).
	seenMF := map[string]struct{}{}
	for _, lot := range mfLots {
		if lot.Quantity <= 1e-9 {
			continue
		}
		src := strings.TrimSpace(lot.Source)
		if src == "" {
			src = models.SourceManualAdd
		}
		invested := lot.Price * lot.Quantity
		isin := mfLotISIN(lot)
		currentNAV := navByISIN[isin]
		if currentNAV <= 0 && isin == "" {
			currentNAV = navByUnmatchedName[strings.ToLower(strings.TrimSpace(lot.SourceSchemeName))]
		}
		current := currentNAV * lot.Quantity
		totalInvested += invested
		currentValue += current

		t := byMFSourceMap[src]
		t.invested += invested
		t.current += current
		byMFSourceMap[src] = t

		key := isin
		if key == "" {
			key = strings.ToLower(strings.TrimSpace(lot.SourceSchemeName))
			if key == "" {
				key = fmt.Sprintf("lot:%d", lot.ID)
			}
		}
		seenMF[key] = struct{}{}
		seen := seenMFBySource[src]
		if seen == nil {
			seen = map[string]struct{}{}
			seenMFBySource[src] = seen
		}
		seen[key] = struct{}{}
	}
	mfCount := len(seenMF)

	for src, seen := range seenStockBySource {
		t := bySourceMap[src]
		t.count = len(seen)
		bySourceMap[src] = t
	}
	for src, seen := range seenMFBySource {
		t := byMFSourceMap[src]
		t.count = len(seen)
		byMFSourceMap[src] = t
	}

	profitLoss := currentValue - totalInvested

	profitLossPct := 0.0
	if totalInvested > 0 {
		profitLossPct = (profitLoss / totalInvested) * 100
	}

	asOf := time.Now()
	stockXIRR := xirrRateFromLots(lots, priceByID, asOf)
	lotsBySource := map[string][]models.UserStockTransaction{}
	for _, lot := range lots {
		src := strings.TrimSpace(lot.Source)
		if src == "" {
			src = models.SourceManualAdd
		}
		lotsBySource[src] = append(lotsBySource[src], lot)
	}
	mfLotsBySource := map[string][]models.UserMutualFundTransaction{}
	for _, lot := range mfLots {
		src := strings.TrimSpace(lot.Source)
		if src == "" {
			src = models.SourceManualAdd
		}
		mfLotsBySource[src] = append(mfLotsBySource[src], lot)
	}

	sourceNames := make([]string, 0, len(bySourceMap))
	for name := range bySourceMap {
		sourceNames = append(sourceNames, name)
	}
	sort.Strings(sourceNames)

	bySource := make([]gin.H, 0, len(sourceNames))
	for _, name := range sourceNames {
		t := bySourceMap[name]
		pl := t.current - t.invested
		plPct := 0.0
		if t.invested > 0 {
			plPct = (pl / t.invested) * 100
		}
		srcLots := lotsBySource[name]
		bySource = append(bySource, gin.H{
			"source":                 name,
			"count":                  t.count,
			"total_invested":         t.invested,
			"current_value":          t.current,
			"profit_loss":            pl,
			"profit_loss_percentage": plPct,
			"xirr":                   xirrRateFromLots(srcLots, priceByID, asOf),
			"since_fy25":             xirrStockSinceFY25(srcLots, stockFYByID),
			"fy26_ytd":               xirrStockFY26YTD(srcLots, stockFYByID, asOf),
		})
	}

	mfSourceNames := make([]string, 0, len(byMFSourceMap))
	for name := range byMFSourceMap {
		mfSourceNames = append(mfSourceNames, name)
	}
	sort.Strings(mfSourceNames)

	byMFSource := make([]gin.H, 0, len(mfSourceNames))
	for _, name := range mfSourceNames {
		t := byMFSourceMap[name]
		pl := t.current - t.invested
		plPct := 0.0
		if t.invested > 0 {
			plPct = (pl / t.invested) * 100
		}
		srcLots := mfLotsBySource[name]
		byMFSource = append(byMFSource, gin.H{
			"source":                 name,
			"count":                  t.count,
			"total_invested":         t.invested,
			"current_value":          t.current,
			"profit_loss":            pl,
			"profit_loss_percentage": plPct,
			"xirr":                   xirrRateFromMFLots(srcLots, navByISIN, asOf),
			"since_fy25":             xirrMFSinceFY25(srcLots, mfFYByISIN),
			"fy26_ytd":               xirrMFFY26YTD(srcLots, mfFYByISIN, asOf),
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"total_invested":         totalInvested,
		"current_value":          currentValue,
		"profit_loss":            profitLoss,
		"profit_loss_percentage": profitLossPct,
		"stock_xirr":             stockXIRR,
		"stock_count":            stockCount,
		"mf_count":               mfCount,
		"by_source":              bySource,
		"by_mf_source":           byMFSource,
	})
}
