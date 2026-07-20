package handlers

import (
	"encoding/json"
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

// StockWithDetails embeds Stock with holdings computed from transactions.
type StockWithDetails struct {
	models.Stock
	Quantity        float64 `json:"quantity"`
	AverageBuyPrice float64 `json:"average_buy_price"`
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

func (h *Handler) stocksWithHoldings(stocks []models.Stock) []StockWithDetails {
	var stocksWithDetails []StockWithDetails
	for _, stock := range stocks {
		var transactions []models.Transaction
		h.DB.Where("stock_id = ?", stock.ID).Find(&transactions)

		totalQuantity := 0.0
		totalInvested := 0.0
		for _, tx := range transactions {
			if tx.Type == models.TransactionTypeBuy {
				totalQuantity += tx.RemainingQuantity
				totalInvested += tx.Price * tx.RemainingQuantity
			}
		}

		avgBuyPrice := 0.0
		if totalQuantity > 0 {
			avgBuyPrice = totalInvested / totalQuantity
		}

		stocksWithDetails = append(stocksWithDetails, StockWithDetails{
			Stock:           stock,
			Quantity:        totalQuantity,
			AverageBuyPrice: avgBuyPrice,
		})
	}
	return stocksWithDetails
}

// Stock handlers
func (h *Handler) GetStocks(c *gin.Context) {
	var stocks []models.Stock
	if err := h.DB.Find(&stocks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.stocksWithHoldings(stocks))
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

	source := req.Source
	if source == "" {
		source = models.SourceManualAdd
	}

	stock, err := h.findOrCreateStock(req.Symbol, req.Name, "")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Create buy transaction
	transaction := models.Transaction{
		StockID:           stock.ID,
		Type:              models.TransactionTypeBuy,
		Quantity:          req.Quantity,
		Price:             req.Price,
		RemainingQuantity: req.Quantity,
		TransactionDate:   req.TransactionDate,
		Source:            source,
	}

	if err := h.DB.Create(&transaction).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, transaction)
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

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}

	if err := tx.Where("source = ? AND type = ?", source, models.TransactionTypeBuy).
		Delete(&models.Transaction{}).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	created := make([]models.Transaction, 0, len(req.Items))
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

		transaction := models.Transaction{
			StockID:           stock.ID,
			Type:              models.TransactionTypeBuy,
			Quantity:          item.Quantity,
			Price:             item.Price,
			RemainingQuantity: item.Quantity,
			TransactionDate:   item.TransactionDate,
			Source:            source,
		}
		if err := tx.Create(&transaction).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		created = append(created, transaction)
	}

	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	_ = ReloadSymbolCache(h.DB)

	c.JSON(http.StatusCreated, gin.H{
		"count":        len(created),
		"transactions": created,
	})
}

func (h *Handler) CreateSellTransaction(c *gin.Context) {
	var req struct {
		Symbol          string    `json:"symbol" binding:"required"`
		Quantity        float64   `json:"quantity" binding:"required"`
		Price           float64   `json:"price" binding:"required"`
		TransactionDate time.Time `json:"transaction_date" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Find stock
	var stock models.Stock
	if err := h.DB.Where("symbol = ?", req.Symbol).First(&stock).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Get all buy transactions for this stock ordered by date (FIFO)
	var buyTransactions []models.Transaction
	if err := h.DB.Where("stock_id = ? AND type = ? AND remaining_quantity > 0", stock.ID, models.TransactionTypeBuy).
		Order("transaction_date ASC").
		Find(&buyTransactions).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Calculate total available quantity
	totalAvailable := 0.0
	for _, t := range buyTransactions {
		totalAvailable += t.RemainingQuantity
	}

	if totalAvailable < req.Quantity {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Insufficient quantity. Available: %.2f, Requested: %.2f", totalAvailable, req.Quantity)})
		return
	}

	// Create sell transaction
	sellTransaction := models.Transaction{
		StockID:           stock.ID,
		Type:              models.TransactionTypeSell,
		Quantity:          req.Quantity,
		Price:             req.Price,
		RemainingQuantity: 0, // Sell transactions don't have remaining quantity
		TransactionDate:   req.TransactionDate,
	}

	if err := h.DB.Create(&sellTransaction).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Reduce remaining quantity from buy transactions (FIFO)
	remainingToSell := req.Quantity
	for i := range buyTransactions {
		if remainingToSell <= 0 {
			break
		}

		if buyTransactions[i].RemainingQuantity >= remainingToSell {
			// This transaction can cover the entire remaining sell
			buyTransactions[i].RemainingQuantity -= remainingToSell
			remainingToSell = 0
		} else {
			// Use up this entire transaction and move to next
			remainingToSell -= buyTransactions[i].RemainingQuantity
			buyTransactions[i].RemainingQuantity = 0
		}

		if err := h.DB.Save(&buyTransactions[i]).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	c.JSON(http.StatusCreated, sellTransaction)
}

func (h *Handler) GetTransactions(c *gin.Context) {
	symbol := c.Query("symbol")
	var transactions []models.Transaction

	query := h.DB.Preload("Stock")
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

	c.JSON(http.StatusOK, transactions)
}

func (h *Handler) GetStockTransactions(c *gin.Context) {
	symbol := c.Param("symbol")

	var stock models.Stock
	if err := h.DB.Where("symbol = ?", symbol).First(&stock).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
		return
	}

	var transactions []models.Transaction
	if err := h.DB.Where("stock_id = ?", stock.ID).
		Order("transaction_date DESC").
		Find(&transactions).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
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
	var history []HistoricalDataPoint

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
	var stocks []models.Stock
	if err := h.DB.Find(&stocks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var trends []StockTrend

	// Fetch Sensex market delta first
	_, _, _, marketDelta, _ := fetchMovingAverages("^BSESN")

	for _, stock := range stocks {
		currentPrice, ma7, ma20, stockDelta, err := fetchMovingAverages(stock.Symbol)
		if err != nil {
			trends = append(trends, StockTrend{
				StockID:      stock.ID,
				Symbol:       stock.Symbol,
				CurrentPrice: stock.CurrentPrice,
				Trend:        "unknown",
			})
			continue
		}

		adjustedDelta := stockDelta - marketDelta

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

		trends = append(trends, StockTrend{
			StockID:       stock.ID,
			Symbol:        stock.Symbol,
			CurrentPrice:  currentPrice,
			MA7:           ma7,
			MA20:          ma20,
			StockDelta:    stockDelta,
			MarketDelta:   marketDelta,
			AdjustedDelta: adjustedDelta,
			Trend:         trend,
		})
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

		// Fill blank market cap even when historical data was already fetched today
		if s.MarketCap == "" {
			if marketCap, err := fetchYahooFinanceMarketCap(s.Symbol); err == nil {
				label := classifyMarketCap(marketCap)
				s.MarketCap = label
				h.DB.Model(s).Update("market_cap", label)
			}
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

		status := "OK"
		if needsYahooAnyData(s) {
			status = "INCOMPLETE"
		}
		log.Printf("RefreshStockPrices [%s]: DONE status=%s yahoo=%s price=%.2f high6=%.2f low6=%.2f sector=%q mcap=%q priceErr=%q",
			s.Symbol, status, resolveYahooSymbol(s.Symbol), s.CurrentPrice, s.SixthHighestPrice, s.SixthLowestPrice,
			s.Sector, s.MarketCap, priceErr)
	}
	log.Printf("RefreshStockPrices: finished %d stocks", len(stocks))
	c.JSON(http.StatusOK, h.stocksWithHoldings(stocks))
}

// Mutual Fund handlers
func (h *Handler) GetMutualFunds(c *gin.Context) {
	var mfs []models.MutualFund
	if err := h.DB.Find(&mfs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, mfs)
}

func (h *Handler) CreateMutualFund(c *gin.Context) {
	var mf models.MutualFund
	if err := c.ShouldBindJSON(&mf); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.DB.Create(&mf).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, mf)
}

func (h *Handler) GetMutualFund(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var mf models.MutualFund
	if err := h.DB.First(&mf, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Mutual Fund not found"})
		return
	}
	c.JSON(http.StatusOK, mf)
}

func (h *Handler) UpdateMutualFund(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var mf models.MutualFund
	if err := h.DB.First(&mf, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Mutual Fund not found"})
		return
	}
	if err := c.ShouldBindJSON(&mf); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.DB.Save(&mf).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, mf)
}

func (h *Handler) DeleteMutualFund(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	if err := h.DB.Delete(&models.MutualFund{}, uint(id)).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Mutual Fund deleted"})
}

// Portfolio handlers
func (h *Handler) GetPortfolio(c *gin.Context) {
	var stocks []models.Stock
	var mfs []models.MutualFund

	h.DB.Find(&stocks)
	h.DB.Find(&mfs)

	c.JSON(http.StatusOK, gin.H{
		"stocks":       stocks,
		"mutual_funds": mfs,
	})
}

func (h *Handler) GetPortfolioSummary(c *gin.Context) {
	var stocks []models.Stock
	var mfs []models.MutualFund

	h.DB.Find(&stocks)
	h.DB.Find(&mfs)

	totalInvested := 0.0
	currentValue := 0.0

	type sourceTotals struct {
		invested float64
		current  float64
	}
	bySourceMap := map[string]sourceTotals{}

	for _, stock := range stocks {
		// Calculate from transactions
		var transactions []models.Transaction
		h.DB.Where("stock_id = ?", stock.ID).Find(&transactions)

		stockQuantity := 0.0
		stockInvested := 0.0

		for _, tx := range transactions {
			if tx.Type == models.TransactionTypeBuy {
				stockQuantity += tx.RemainingQuantity
				stockInvested += tx.Price * tx.RemainingQuantity

				if tx.RemainingQuantity > 0 {
					src := tx.Source
					if src == "" {
						src = models.SourceManualAdd
					}
					t := bySourceMap[src]
					t.invested += tx.Price * tx.RemainingQuantity
					t.current += stock.CurrentPrice * tx.RemainingQuantity
					bySourceMap[src] = t
				}
			}
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
		"by_source":              bySource,
	})
}
