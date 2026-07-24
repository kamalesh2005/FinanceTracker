package handlers

import (
	"encoding/json"
	"financetracker/middleware"
	"financetracker/models"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// StockWithDetails embeds Stock with one User_Stocks position (per source).
type StockWithDetails struct {
	models.Stock
	Source          string     `json:"source"`
	Quantity        float64    `json:"quantity"`
	AverageBuyPrice float64    `json:"average_buy_price"`
	LastBuyPrice    float64    `json:"last_buy_price"`
	LastBuyDate     *time.Time `json:"last_buy_date"`
	LastSalePrice   float64    `json:"last_sale_price"`
	LastSaleDate    *time.Time `json:"last_sale_date"`
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
	DB *gorm.DB
}

func NewHandler(db *gorm.DB) *Handler {
	return &Handler{DB: db}
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

func (h *Handler) stocksWithHoldings(stocks []models.Stock, userID uint) []StockWithDetails {
	stocksWithDetails := make([]StockWithDetails, 0, len(stocks))
	for _, stock := range stocks {
		var positions []models.UserStock
		h.DB.Where("stock_id = ? AND user_id = ? AND quantity > 0", stock.ID, userID).
			Order("source asc").
			Find(&positions)

		for _, pos := range positions {
			source := strings.TrimSpace(pos.Source)
			if source == "" {
				source = models.SourceManualAdd
			}
			stocksWithDetails = append(stocksWithDetails, StockWithDetails{
				Stock:           stock,
				Source:          source,
				Quantity:        pos.Quantity,
				AverageBuyPrice: pos.AvgBuyPrice,
				LastBuyPrice:    pos.LastBuyPrice,
				LastBuyDate:     pos.LastBuyDate,
				LastSalePrice:   pos.LastSalePrice,
				LastSaleDate:    pos.LastSaleDate,
			})
		}
	}
	return stocksWithDetails
}

func (h *Handler) stocksForUser(userID uint) ([]models.Stock, error) {
	var stockIDs []uint
	if err := h.DB.Model(&models.UserStock{}).
		Where("user_id = ? AND quantity > 0", userID).
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
	role, _ := c.Get(middleware.ContextRoleKey)

	var stocks []models.Stock
	var err error
	if role == models.RoleAdmin {
		err = h.DB.Find(&stocks).Error
	} else {
		stocks, err = h.stocksForUser(userID)
	}
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

	// Fetch sector and market cap from Yahoo Finance if not fetched today
	if stock.LastFetchedDate == nil || stock.LastFetchedDate.Before(today) {
		if sector, err := fetchYahooFinanceSector(stock.Symbol); err == nil {
			stock.Sector = sector
		}
		if marketCap, err := fetchYahooFinanceMarketCap(stock.Symbol); err == nil {
			stock.MarketCap = classifyMarketCap(marketCap)
		}

		fetchedHistorical := false
		if sixthHighest, err := fetchSixthHighestPrice(stock.Symbol); err == nil {
			stock.SixthHighestPrice = sixthHighest
			fetchedHistorical = true
		}
		if sixthLowest, err := fetchSixthLowestPrice(stock.Symbol); err == nil {
			stock.SixthLowestPrice = sixthLowest
			fetchedHistorical = true
		}
		if fetchedHistorical {
			stock.LastFetchedDate = &now
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

// UpdateStockHoldings adjusts Manual Add position via buy/sell ledger deltas.
// Optional symbol change moves this user's Manual Add rows to findOrCreateStock(newSymbol).
func (h *Handler) UpdateStockHoldings(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stock id"})
		return
	}

	var req struct {
		Symbol   string  `json:"symbol" binding:"required"`
		Quantity float64 `json:"quantity" binding:"required"`
		Price    float64 `json:"price" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	symbol := strings.ToUpper(strings.TrimSpace(req.Symbol))
	if symbol == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "symbol is required"})
		return
	}
	if req.Quantity <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "quantity must be greater than 0"})
		return
	}
	if req.Price <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "price must be greater than 0"})
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

	var userPosCount int64
	if err := h.DB.Model(&models.UserStock{}).
		Where("user_id = ? AND stock_id = ?", userID, stock.ID).
		Count(&userPosCount).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if userPosCount == 0 {
		c.JSON(http.StatusForbidden, gin.H{"error": "no holdings for this stock"})
		return
	}

	targetStock := stock
	if !strings.EqualFold(strings.TrimSpace(stock.Symbol), symbol) {
		created, err := h.findOrCreateStock(symbol, stock.Name, stock.ISIN)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		targetStock = created
	}

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}

	if targetStock.ID != stock.ID {
		if err := tx.Model(&models.UserStock{}).
			Where("user_id = ? AND stock_id = ?", userID, stock.ID).
			Update("stock_id", targetStock.ID).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if err := tx.Model(&models.UserStockTransaction{}).
			Where("user_id = ? AND stock_id = ?", userID, stock.ID).
			Update("stock_id", targetStock.ID).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	var pos models.UserStock
	err = tx.Where("user_id = ? AND stock_id = ? AND source = ?", userID, targetStock.ID, models.SourceManualAdd).
		First(&pos).Error
	currentQty := 0.0
	if err == nil {
		currentQty = pos.Quantity
	} else if err != gorm.ErrRecordNotFound {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	delta := req.Quantity - currentQty
	txDate := time.Now()
	if delta > 1e-9 {
		if _, _, err := applyManualStockTransaction(tx, userID, targetStock.ID, models.TransactionTypeBuy, delta, req.Price, txDate, models.SourceManualAdd); err != nil {
			tx.Rollback()
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
	} else if delta < -1e-9 {
		if _, _, err := applyManualStockTransaction(tx, userID, targetStock.ID, models.TransactionTypeSell, -delta, req.Price, txDate, models.SourceManualAdd); err != nil {
			tx.Rollback()
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
	}

	if watchList {
		var updated models.UserStock
		if err := tx.Where("user_id = ? AND stock_id = ? AND source = ?", userID, targetStock.ID, models.SourceManualAdd).
			First(&updated).Error; err == nil {
			if err := normalizePositionLotsToOne(tx, updated); err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}
	}

	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	details := h.stocksWithHoldings([]models.Stock{targetStock}, userID)
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
		// Fetch sector and market cap from Yahoo Finance if not fetched today
		if stocks[i].LastFetchedDate == nil || stocks[i].LastFetchedDate.Before(today) {
			if sector, err := fetchYahooFinanceSector(stocks[i].Symbol); err == nil {
				stocks[i].Sector = sector
			}
			if marketCap, err := fetchYahooFinanceMarketCap(stocks[i].Symbol); err == nil {
				stocks[i].MarketCap = classifyMarketCap(marketCap)
			}

			fetchedHistorical := false
			if sixthHighest, err := fetchSixthHighestPrice(stocks[i].Symbol); err == nil {
				stocks[i].SixthHighestPrice = sixthHighest
				fetchedHistorical = true
			}
			if sixthLowest, err := fetchSixthLowestPrice(stocks[i].Symbol); err == nil {
				stocks[i].SixthLowestPrice = sixthLowest
				fetchedHistorical = true
			}
			if fetchedHistorical {
				stocks[i].LastFetchedDate = &now
			}
		}
	}

	if err := h.DB.Create(&stocks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, stocks)
}

func (h *Handler) findOrCreateStock(symbol, name, isin string) (models.Stock, error) {
	rawISIN := strings.ToUpper(strings.TrimSpace(isin))
	var stock models.Stock
	if err := h.DB.Where("symbol = ?", symbol).First(&stock).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			stock = models.Stock{
				Symbol: symbol,
				ISIN:   rawISIN,
				Name:   name,
			}
			h.applyYahooDataWithAutoMapping(&stock, models.SourceFormatManual)

			if err := h.DB.Create(&stock).Error; err != nil {
				return stock, err
			}
			return stock, nil
		}
		return stock, err
	}
	if name != "" && stock.Name != name {
		stock.Name = name
		_ = h.DB.Model(&stock).Update("name", name)
	}
	if rawISIN != "" && strings.TrimSpace(stock.ISIN) == "" {
		stock.ISIN = rawISIN
		_ = h.DB.Model(&stock).Update("isin", rawISIN)
	}
	if stock.CurrentPrice == 0 || stock.SixthHighestPrice < 1 || stock.SixthLowestPrice < 1 {
		h.applyYahooDataWithAutoMapping(&stock, models.SourceFormatManual)
		h.persistYahooStockFields(&stock)
	}
	return stock, nil
}

func applyYahooDataToStock(symbol string, stock *models.Stock) {
	now := time.Now()
	fetchedHistorical := false

	if sector, err := fetchYahooFinanceSector(symbol); err == nil {
		stock.Sector = sector
	}
	if marketCap, err := fetchYahooFinanceMarketCap(symbol); err == nil {
		stock.MarketCap = classifyMarketCap(marketCap)
	}
	if sixthHighest, err := fetchSixthHighestPrice(symbol); err == nil {
		stock.SixthHighestPrice = sixthHighest
		fetchedHistorical = true
	}
	if sixthLowest, err := fetchSixthLowestPrice(symbol); err == nil {
		stock.SixthLowestPrice = sixthLowest
		fetchedHistorical = true
	}
	if currentPrice, err := fetchYahooFinancePrice(symbol); err == nil {
		stock.CurrentPrice = currentPrice
		stock.LastPriceFetchedDate = &now
	}
	if fetchedHistorical {
		stock.LastFetchedDate = &now
	}
}

func (h *Handler) persistYahooStockFields(stock *models.Stock) {
	updates := map[string]interface{}{
		"sector":                  stock.Sector,
		"market_cap":              stock.MarketCap,
		"sixth_highest_price":     stock.SixthHighestPrice,
		"sixth_lowest_price":      stock.SixthLowestPrice,
		"current_price":           stock.CurrentPrice,
		"last_fetched_date":       stock.LastFetchedDate,
		"last_price_fetched_date": stock.LastPriceFetchedDate,
	}
	_ = h.DB.Model(stock).Updates(updates).Error
}

func needsYahooHistoricalData(stock *models.Stock) bool {
	return stock == nil || stock.SixthHighestPrice < 1 || stock.SixthLowestPrice < 1
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

	applyYahooDataToStock(stock.Symbol, stock)
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
				applyYahooDataToStock(stock.Symbol, stock)
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
		applyYahooDataToStock(stock.Symbol, stock)
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
		Quantity        float64   `json:"quantity" binding:"required"`
		Price           float64   `json:"price" binding:"required"`
		TransactionDate time.Time `json:"transaction_date" binding:"required"`
		Source          string    `json:"source"`
		Name            string    `json:"name"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	source := normalizeSource(req.Source)
	stock, err := h.findOrCreateStock(req.Symbol, req.Name, "")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

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
			Symbol          string    `json:"symbol" binding:"required"`
			Quantity        float64   `json:"quantity" binding:"required"`
			Price           float64   `json:"price" binding:"required"`
			TransactionDate time.Time `json:"transaction_date" binding:"required"`
			Name            string    `json:"name"`
			ISIN            string    `json:"isin"`
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
			applyYahooDataToStock(item.Symbol, &stock)
			h.persistYahooStockFields(&stock)
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
	now := time.Now()
	for _, t := range stale {
		if _, ok := touchedStockIDs[t.StockID]; ok {
			continue
		}
		var catalog models.Stock
		symbol := ""
		if err := tx.First(&catalog, t.StockID).Error; err == nil {
			symbol = catalog.Symbol
		}
		pos, delta, err := applyUploadPosition(tx, userID, t.StockID, symbol, source, 0, t.AvgBuyPrice, now, false, 0)
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

func fetchYahooFinanceSector(symbol string) (string, error) {
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
						Sector string `json:"sector"`
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
		if len(result.QuoteSummary.Result) > 0 && result.QuoteSummary.Result[0].AssetProfile.Sector != "" {
			return result.QuoteSummary.Result[0].AssetProfile.Sector, nil
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

	if sector, exists := sectorMap[resolved]; exists {
		return sector, nil
	}
	if sector, exists := sectorMap[symbol]; exists {
		return sector, nil
	}

	return "", fmt.Errorf("sector not found for %s", symbol)
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
	StockID       uint    `json:"stock_id"`
	Symbol        string  `json:"symbol"`
	CurrentPrice  float64 `json:"current_price"`
	MA7           float64 `json:"ma7"`
	MA20          float64 `json:"ma20"`
	StockDelta    float64 `json:"stock_delta"`
	MarketDelta   float64 `json:"market_delta"`
	AdjustedDelta float64 `json:"adjusted_delta"`
	Trend         string  `json:"trend"`
}

func fetchMovingAverages(symbol string) (currentPrice, ma7, ma20, delta float64, err error) {
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

		n := len(closes)
		if n < 7 {
			return 0, 0, 0, 0, fmt.Errorf("insufficient data for %s", symbol)
		}

		sum7 := 0.0
		for _, c := range closes[n-7:] {
			sum7 += c
		}
		ma7 = sum7 / 7

		if n >= 20 {
			sum20 := 0.0
			for _, c := range closes[n-20:] {
				sum20 += c
			}
			ma20 = sum20 / 20
		}

		if ma20 > 0 {
			delta = ((ma7 - ma20) / ma20) * 100
		}

		return currentPrice, ma7, ma20, delta, nil
	}
	return 0, 0, 0, 0, fmt.Errorf("data not found for %s", symbol)
}

func classifyTrend(currentPrice, ma7, ma20, adjustedDelta float64) string {
	trend := "neutral"
	if ma7 > 0 && ma20 > 0 {
		if currentPrice > ma7 && ma7 > ma20 {
			if adjustedDelta > 0 {
				trend = "bullish"
			} else {
				trend = "moderately bullish"
			}
		} else if currentPrice < ma7 && ma7 < ma20 {
			if adjustedDelta < -10 {
				trend = "bearish"
			} else {
				trend = "moderately bearish"
			}
		} else if ma7 > ma20 {
			if adjustedDelta > 0 {
				trend = "moderately bullish"
			} else {
				trend = "neutral"
			}
		} else {
			if adjustedDelta < -10 {
				trend = "moderately bearish"
			} else {
				trend = "neutral"
			}
		}
	}
	return trend
}

func needsTrendData(stock *models.Stock, today time.Time) bool {
	if stock == nil {
		return true
	}
	if !isSameCalendarDay(stock.LastTrendFetchedDate, today) {
		return true
	}
	if stock.MA7 == 0 || stock.MA20 == 0 {
		return true
	}
	trend := strings.TrimSpace(stock.Trend)
	return trend == "" || trend == "unknown"
}

func applyTrendToStock(stock *models.Stock, currentPrice, ma7, ma20, sensexMA7, sensexMA20, stockDelta, marketDelta float64, now time.Time) {
	adjustedDelta := stockDelta - marketDelta
	stock.MA7 = ma7
	stock.MA20 = ma20
	stock.SensexMA7 = sensexMA7
	stock.SensexMA20 = sensexMA20
	stock.StockDelta = stockDelta
	stock.MarketDelta = marketDelta
	stock.AdjustedDelta = adjustedDelta
	stock.Trend = classifyTrend(currentPrice, ma7, ma20, adjustedDelta)
	stock.LastTrendFetchedDate = &now
	if currentPrice > 0 {
		stock.CurrentPrice = currentPrice
	}
}

func (h *Handler) persistTrendFields(stock *models.Stock) {
	updates := map[string]interface{}{
		"ma7":                     stock.MA7,
		"ma20":                    stock.MA20,
		"sensex_ma7":              stock.SensexMA7,
		"sensex_ma20":             stock.SensexMA20,
		"stock_delta":             stock.StockDelta,
		"market_delta":            stock.MarketDelta,
		"adjusted_delta":          stock.AdjustedDelta,
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
		StockID:       stock.ID,
		Symbol:        stock.Symbol,
		CurrentPrice:  price,
		MA7:           stock.MA7,
		MA20:          stock.MA20,
		StockDelta:    stock.StockDelta,
		MarketDelta:   stock.MarketDelta,
		AdjustedDelta: stock.AdjustedDelta,
		Trend:         stock.Trend,
	}
}

func (h *Handler) fetchAndPersistStockTrend(stock *models.Stock, sensexMA7, sensexMA20, marketDelta float64, now time.Time) error {
	currentPrice, ma7, ma20, stockDelta, err := fetchMovingAverages(stock.Symbol)
	if err != nil {
		return err
	}
	applyTrendToStock(stock, currentPrice, ma7, ma20, sensexMA7, sensexMA20, stockDelta, marketDelta, now)
	h.persistTrendFields(stock)
	return nil
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

	var sensexMA7, sensexMA20, marketDelta float64
	if needsFetch {
		_, sensexMA7, sensexMA20, marketDelta, _ = fetchMovingAverages("^BSESN")
	}

	for i := range stocks {
		stock := &stocks[i]
		if !needsTrendData(stock, today) {
			trends = append(trends, stockTrendFromStock(*stock))
			continue
		}

		if err := h.fetchAndPersistStockTrend(stock, sensexMA7, sensexMA20, marketDelta, now); err != nil {
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
	var stocks []models.Stock
	if err := h.DB.Find(&stocks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	log.Printf("RefreshStockPrices: starting for %d stocks", len(stocks))

	needsAnyTrend := false
	for i := range stocks {
		if needsTrendData(&stocks[i], today) {
			needsAnyTrend = true
			break
		}
	}
	var sensexMA7, sensexMA20, marketDelta float64
	if needsAnyTrend {
		_, sensexMA7, sensexMA20, marketDelta, _ = fetchMovingAverages("^BSESN")
		log.Printf("RefreshStockPrices: Sensex MA7=%.2f MA20=%.2f marketDelta=%.2f", sensexMA7, sensexMA20, marketDelta)
	}

	for i := range stocks {
		s := &stocks[i]
		yahoo := resolveYahooSymbol(s.Symbol)
		normISIN := normalizeISIN(s.ISIN)
		log.Printf("RefreshStockPrices [%s]: yahoo=%s isin_raw=%q isin_norm=%q price=%.2f high6=%.2f low6=%.2f",
			s.Symbol, yahoo, s.ISIN, normISIN, s.CurrentPrice, s.SixthHighestPrice, s.SixthLowestPrice)

		priceFetchedToday := isSameCalendarDay(s.LastPriceFetchedDate, today)
		priceErr := ""
		if !priceFetchedToday {
			if price, err := fetchYahooFinancePrice(s.Symbol); err == nil {
				s.CurrentPrice = price
				s.LastPriceFetchedDate = &now
				h.DB.Model(s).Updates(map[string]interface{}{
					"current_price":           price,
					"last_price_fetched_date": now,
				})
				log.Printf("RefreshStockPrices [%s]: price OK %.2f (via %s)", s.Symbol, price, yahoo)
			} else {
				priceErr = err.Error()
				log.Printf("RefreshStockPrices [%s]: price FAIL via %s: %v", s.Symbol, yahoo, err)
			}
		} else {
			log.Printf("RefreshStockPrices [%s]: price skipped (already fetched today)", s.Symbol)
		}

		if s.CurrentPrice == 0 && strings.TrimSpace(s.ISIN) != "" {
			log.Printf("RefreshStockPrices [%s]: attempting ISIN auto-map (price still 0, isin present)", s.Symbol)
			h.applyYahooDataWithAutoMapping(s, models.SourceFormatManual)
			h.persistYahooStockFields(s)
			yahoo = resolveYahooSymbol(s.Symbol)
			log.Printf("RefreshStockPrices [%s]: after ISIN auto-map yahoo=%s price=%.2f", s.Symbol, yahoo, s.CurrentPrice)
		} else if s.CurrentPrice == 0 && strings.TrimSpace(s.ISIN) == "" {
			log.Printf("RefreshStockPrices [%s]: price=0 and no ISIN — cannot auto-map", s.Symbol)
		}

		needsHistorical := s.LastFetchedDate == nil ||
			s.LastFetchedDate.Before(today) ||
			needsYahooHistoricalData(s)

		if needsHistorical {
			if sector, err := fetchYahooFinanceSector(s.Symbol); err == nil {
				s.Sector = sector
				h.DB.Model(s).Update("sector", sector)
			}
			if s.MarketCap == "" {
				if marketCap, err := fetchYahooFinanceMarketCap(s.Symbol); err == nil {
					label := classifyMarketCap(marketCap)
					s.MarketCap = label
					h.DB.Model(s).Update("market_cap", label)
				}
			}

			fetchedHigh := false
			fetchedLow := false
			if sixthHighest, err := fetchSixthHighestPrice(s.Symbol); err == nil {
				s.SixthHighestPrice = sixthHighest
				h.DB.Model(s).Update("sixth_highest_price", sixthHighest)
				fetchedHigh = true
			} else {
				log.Printf("RefreshStockPrices [%s]: sixth-high FAIL via %s: %v", s.Symbol, resolveYahooSymbol(s.Symbol), err)
			}
			if sixthLowest, err := fetchSixthLowestPrice(s.Symbol); err == nil {
				s.SixthLowestPrice = sixthLowest
				h.DB.Model(s).Update("sixth_lowest_price", sixthLowest)
				fetchedLow = true
			} else {
				log.Printf("RefreshStockPrices [%s]: sixth-low FAIL via %s: %v", s.Symbol, resolveYahooSymbol(s.Symbol), err)
			}

			// Only stamp LastFetchedDate when historical data was retrieved,
			// so failed symbols (e.g. unmapped tickers) are retried later.
			if fetchedHigh || fetchedLow {
				s.LastFetchedDate = &now
				h.DB.Model(s).Update("last_fetched_date", now)
			}

			if needsYahooHistoricalData(s) && strings.TrimSpace(s.ISIN) != "" {
				log.Printf("RefreshStockPrices [%s]: historical still missing — ISIN auto-map retry", s.Symbol)
				h.applyYahooDataWithAutoMapping(s, models.SourceFormatManual)
				h.persistYahooStockFields(s)
			}
		} else {
			log.Printf("RefreshStockPrices [%s]: historical skipped (fresh)", s.Symbol)
		}

		if needsTrendData(s, today) {
			if err := h.fetchAndPersistStockTrend(s, sensexMA7, sensexMA20, marketDelta, now); err != nil {
				log.Printf("RefreshStockPrices [%s]: trend FAIL: %v", s.Symbol, err)
			} else {
				log.Printf("RefreshStockPrices [%s]: trend OK %s ma7=%.2f ma20=%.2f adj=%.2f",
					s.Symbol, s.Trend, s.MA7, s.MA20, s.AdjustedDelta)
			}
		} else {
			log.Printf("RefreshStockPrices [%s]: trend skipped (already fetched today)", s.Symbol)
		}

		status := "OK"
		if needsYahooAnyData(s) {
			status = "INCOMPLETE"
		}
		log.Printf("RefreshStockPrices [%s]: DONE status=%s yahoo=%s price=%.2f high6=%.2f low6=%.2f sector=%q mcap=%q priceErr=%q",
			s.Symbol, status, resolveYahooSymbol(s.Symbol), s.CurrentPrice, s.SixthHighestPrice, s.SixthLowestPrice,
			s.Sector, s.MarketCap, priceErr)
	}
	log.Printf("RefreshStockPrices: finished %d stocks", len(stocks))
	userID := middleware.CurrentUserID(c)
	userStocks, err := h.stocksForUser(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.stocksWithHoldings(userStocks, userID))
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
	c.JSON(http.StatusOK, mfs)
}

func (h *Handler) CreateMutualFund(c *gin.Context) {
	var mf models.MutualFund
	if err := c.ShouldBindJSON(&mf); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	mf.UserID = middleware.CurrentUserID(c)
	if err := h.DB.Create(&mf).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, mf)
}

func (h *Handler) GetMutualFund(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var mf models.MutualFund
	if err := h.DB.Where("id = ? AND user_id = ?", uint(id), userID).First(&mf).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Mutual Fund not found"})
		return
	}
	c.JSON(http.StatusOK, mf)
}

func (h *Handler) UpdateMutualFund(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var mf models.MutualFund
	if err := h.DB.Where("id = ? AND user_id = ?", uint(id), userID).First(&mf).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Mutual Fund not found"})
		return
	}
	if err := c.ShouldBindJSON(&mf); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	mf.ID = uint(id)
	mf.UserID = userID
	if err := h.DB.Save(&mf).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, mf)
}

func (h *Handler) DeleteMutualFund(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	res := h.DB.Where("id = ? AND user_id = ?", uint(id), userID).Delete(&models.MutualFund{})
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
		return
	}
	if res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Mutual Fund not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Mutual Fund deleted"})
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

	c.JSON(http.StatusOK, gin.H{
		"stocks":       h.stocksWithHoldings(stocks, userID),
		"mutual_funds": mfs,
	})
}

func (h *Handler) GetPortfolioSummary(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	stocks, err := h.stocksForUser(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	var mfs []models.MutualFund
	h.DB.Where("user_id = ?", userID).Find(&mfs)

	totalInvested := 0.0
	currentValue := 0.0
	stockCount := 0

	type sourceTotals struct {
		invested float64
		current  float64
	}
	bySourceMap := map[string]sourceTotals{}

	for _, stock := range stocks {
		var positions []models.UserStock
		h.DB.Where("stock_id = ? AND user_id = ? AND quantity > 0", stock.ID, userID).Find(&positions)
		if len(positions) > 0 {
			stockCount++
		}

		stockQuantity := 0.0
		stockInvested := 0.0

		for _, pos := range positions {
			stockQuantity += pos.Quantity
			stockInvested += pos.AvgBuyPrice * pos.Quantity

			src := pos.Source
			if src == "" {
				src = models.SourceManualAdd
			}
			t := bySourceMap[src]
			t.invested += pos.AvgBuyPrice * pos.Quantity
			t.current += stock.CurrentPrice * pos.Quantity
			bySourceMap[src] = t
		}

		totalInvested += stockInvested
		currentValue += stock.CurrentPrice * stockQuantity
	}

	for _, mf := range mfs {
		totalInvested += mf.NAV * mf.Quantity
		currentValue += mf.CurrentNAV * mf.Quantity
	}

	profitLoss := currentValue - totalInvested

	profitLossPct := 0.0
	if totalInvested > 0 {
		profitLossPct = (profitLoss / totalInvested) * 100
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
		bySource = append(bySource, gin.H{
			"source":                 name,
			"total_invested":         t.invested,
			"current_value":          t.current,
			"profit_loss":            pl,
			"profit_loss_percentage": plPct,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"total_invested":         totalInvested,
		"current_value":          currentValue,
		"profit_loss":            profitLoss,
		"profit_loss_percentage": profitLossPct,
		"stock_count":            stockCount,
		"by_source":              bySource,
	})
}
