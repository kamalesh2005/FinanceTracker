package handlers

import (
	"encoding/json"
	"financetracker/models"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type Handler struct {
	DB *gorm.DB
}

func NewHandler(db *gorm.DB) *Handler {
	return &Handler{DB: db}
}

// Stock handlers
func (h *Handler) GetStocks(c *gin.Context) {
	var stocks []models.Stock
	if err := h.DB.Find(&stocks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Calculate quantity and average buy price from transactions for each stock
	type StockWithDetails struct {
		models.Stock
		Quantity        float64 `json:"quantity"`
		AverageBuyPrice float64 `json:"average_buy_price"`
	}

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

	c.JSON(http.StatusOK, stocksWithDetails)
}

func (h *Handler) CreateStock(c *gin.Context) {
	var stock models.Stock
	if err := c.ShouldBindJSON(&stock); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	// Fetch sector from Yahoo Finance if not fetched today
	if stock.LastFetchedDate == nil || stock.LastFetchedDate.Before(today) {
		if sector, err := fetchYahooFinanceSector(stock.Symbol); err == nil {
			stock.Sector = sector
		}

		// Fetch 6th highest price from Yahoo Finance
		if sixthHighest, err := fetchSixthHighestPrice(stock.Symbol); err == nil {
			stock.SixthHighestPrice = sixthHighest
		}

		// Fetch 6th lowest price from Yahoo Finance
		if sixthLowest, err := fetchSixthLowestPrice(stock.Symbol); err == nil {
			stock.SixthLowestPrice = sixthLowest
		}

		stock.LastFetchedDate = &now
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
		// Fetch sector from Yahoo Finance if not fetched today
		if stocks[i].LastFetchedDate == nil || stocks[i].LastFetchedDate.Before(today) {
			if sector, err := fetchYahooFinanceSector(stocks[i].Symbol); err == nil {
				stocks[i].Sector = sector
			}

			// Fetch 6th highest price from Yahoo Finance
			if sixthHighest, err := fetchSixthHighestPrice(stocks[i].Symbol); err == nil {
				stocks[i].SixthHighestPrice = sixthHighest
			}

			// Fetch 6th lowest price from Yahoo Finance
			if sixthLowest, err := fetchSixthLowestPrice(stocks[i].Symbol); err == nil {
				stocks[i].SixthLowestPrice = sixthLowest
			}

			stocks[i].LastFetchedDate = &now
		}
	}

	if err := h.DB.Create(&stocks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, stocks)
}

// Transaction handlers
func (h *Handler) CreateBuyTransaction(c *gin.Context) {
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

	// Find or create stock
	var stock models.Stock
	if err := h.DB.Where("symbol = ?", req.Symbol).First(&stock).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			// Create new stock
			stock = models.Stock{
				Symbol: req.Symbol,
			}

			// Fetch sector and other data
			now := time.Now()

			if sector, err := fetchYahooFinanceSector(req.Symbol); err == nil {
				stock.Sector = sector
			}
			if sixthHighest, err := fetchSixthHighestPrice(req.Symbol); err == nil {
				stock.SixthHighestPrice = sixthHighest
			}
			if sixthLowest, err := fetchSixthLowestPrice(req.Symbol); err == nil {
				stock.SixthLowestPrice = sixthLowest
			}
			if currentPrice, err := fetchYahooFinancePrice(req.Symbol); err == nil {
				stock.CurrentPrice = currentPrice
			}
			stock.LastFetchedDate = &now

			if err := h.DB.Create(&stock).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	// Create buy transaction
	transaction := models.Transaction{
		StockID:           stock.ID,
		Type:              models.TransactionTypeBuy,
		Quantity:          req.Quantity,
		Price:             req.Price,
		RemainingQuantity: req.Quantity,
		TransactionDate:   req.TransactionDate,
	}

	if err := h.DB.Create(&transaction).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, transaction)
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
	suffixes := []string{"", ".NS", ".BO"}
	client := &http.Client{Timeout: 8 * time.Second}

	for _, suffix := range suffixes {
		url := fmt.Sprintf("https://query1.finance.yahoo.com/v8/finance/chart/%s%s?interval=1d&range=1d", symbol, suffix)
		req, err := http.NewRequest("GET", url, nil)
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
	return 0, fmt.Errorf("price not found for %s", symbol)
}

func fetchYahooFinanceSector(symbol string) (string, error) {
	suffixes := []string{"", ".NS", ".BO"}
	client := &http.Client{Timeout: 8 * time.Second}

	// Try using the quoteSummary endpoint with proper headers
	for _, suffix := range suffixes {
		url := fmt.Sprintf("https://query1.finance.yahoo.com/v10/finance/quoteSummary/%s%s?modules=assetProfile", symbol, suffix)
		req, err := http.NewRequest("GET", url, nil)
		if err != nil {
			continue
		}
		req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")

		resp, err := client.Do(req)
		if err != nil || resp.StatusCode != http.StatusOK {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}
		defer resp.Body.Close()

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

		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
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
		"M&M":        "Automobile",
		"MARUTI":     "Automobile",
		"LT":         "Infrastructure",
		"SUNPHARMA":  "Healthcare",
		"DRREDDY":    "Healthcare",
		"CIPLA":      "Healthcare",
	}

	if sector, exists := sectorMap[symbol]; exists {
		return sector, nil
	}

	return "", fmt.Errorf("sector not found for %s", symbol)
}

func fetchSixthHighestPrice(symbol string) (float64, error) {
	suffixes := []string{"", ".NS", ".BO"}
	client := &http.Client{Timeout: 10 * time.Second}

	for _, suffix := range suffixes {
		url := fmt.Sprintf("https://query1.finance.yahoo.com/v8/finance/chart/%s%s?interval=1d&range=1y", symbol, suffix)
		req, err := http.NewRequest("GET", url, nil)
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
	suffixes := []string{"", ".NS", ".BO"}
	client := &http.Client{Timeout: 10 * time.Second}

	for _, suffix := range suffixes {
		url := fmt.Sprintf("https://query1.finance.yahoo.com/v8/finance/chart/%s%s?interval=1d&range=1y", symbol, suffix)
		req, err := http.NewRequest("GET", url, nil)
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
	MA20          float64 `json:"ma20"`
	MA50          float64 `json:"ma50"`
	StockDelta    float64 `json:"stock_delta"`
	MarketDelta   float64 `json:"market_delta"`
	AdjustedDelta float64 `json:"adjusted_delta"`
	Trend         string  `json:"trend"`
}

func fetchMovingAverages(symbol string) (currentPrice, ma20, ma50, delta float64, err error) {
	suffixes := []string{"", ".NS", ".BO"}
	client := &http.Client{Timeout: 10 * time.Second}

	for _, suffix := range suffixes {
		url := fmt.Sprintf("https://query1.finance.yahoo.com/v8/finance/chart/%s%s?interval=1d&range=3mo", symbol, suffix)
		req, e := http.NewRequest("GET", url, nil)
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
		if n < 20 {
			return 0, 0, 0, 0, fmt.Errorf("insufficient data for %s", symbol)
		}

		sum20 := 0.0
		for _, c := range closes[n-20:] {
			sum20 += c
		}
		ma20 = sum20 / 20

		if n >= 50 {
			sum50 := 0.0
			for _, c := range closes[n-50:] {
				sum50 += c
			}
			ma50 = sum50 / 50
		}

		if ma50 > 0 {
			delta = ((ma20 - ma50) / ma50) * 100
		}

		return currentPrice, ma20, ma50, delta, nil
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

	suffixes := []string{"", ".NS", ".BO"}
	client := &http.Client{Timeout: 10 * time.Second}
	var history []HistoricalDataPoint

	for _, suffix := range suffixes {
		url := fmt.Sprintf("https://query1.finance.yahoo.com/v8/finance/chart/%s%s?interval=1d&range=3mo", symbol, suffix)
		req, e := http.NewRequest("GET", url, nil)
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
		currentPrice, ma20, ma50, stockDelta, err := fetchMovingAverages(stock.Symbol)
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
		if ma20 > 0 && ma50 > 0 {
			if currentPrice > ma20 && ma20 > ma50 {
				if adjustedDelta > 0 {
					trend = "bullish"
				} else {
					trend = "moderately bullish"
				}
			} else if currentPrice < ma20 && ma20 < ma50 {
				if adjustedDelta < 0 {
					trend = "bearish"
				} else {
					trend = "moderately bearish"
				}
			} else if ma20 > ma50 {
				if adjustedDelta > 0 {
					trend = "moderately bullish"
				} else {
					trend = "neutral"
				}
			} else {
				if adjustedDelta < 0 {
					trend = "moderately bearish"
				} else {
					trend = "neutral"
				}
			}
		} else if ma20 > 0 {
			if currentPrice >= ma20 {
				if adjustedDelta > 0 {
					trend = "bullish"
				} else {
					trend = "neutral"
				}
			} else {
				if adjustedDelta < 0 {
					trend = "bearish"
				} else {
					trend = "neutral"
				}
			}
		}

		trends = append(trends, StockTrend{
			StockID:       stock.ID,
			Symbol:        stock.Symbol,
			CurrentPrice:  currentPrice,
			MA20:          ma20,
			MA50:          ma50,
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

	for i := range stocks {
		// Always fetch current price
		if price, err := fetchYahooFinancePrice(stocks[i].Symbol); err == nil {
			stocks[i].CurrentPrice = price
			h.DB.Model(&stocks[i]).Update("current_price", price)
		}

		// Only fetch historical data if not fetched today
		if stocks[i].LastFetchedDate == nil || stocks[i].LastFetchedDate.Before(today) {
			if sector, err := fetchYahooFinanceSector(stocks[i].Symbol); err == nil {
				stocks[i].Sector = sector
				h.DB.Model(&stocks[i]).Update("sector", sector)
			}
			if sixthHighest, err := fetchSixthHighestPrice(stocks[i].Symbol); err == nil {
				stocks[i].SixthHighestPrice = sixthHighest
				h.DB.Model(&stocks[i]).Update("sixth_highest_price", sixthHighest)
			}
			if sixthLowest, err := fetchSixthLowestPrice(stocks[i].Symbol); err == nil {
				stocks[i].SixthLowestPrice = sixthLowest
				h.DB.Model(&stocks[i]).Update("sixth_lowest_price", sixthLowest)
			}
			stocks[i].LastFetchedDate = &now
			h.DB.Model(&stocks[i]).Update("last_fetched_date", now)
		}
	}
	c.JSON(http.StatusOK, stocks)
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

	c.JSON(http.StatusOK, gin.H{
		"total_invested":         totalInvested,
		"current_value":          currentValue,
		"profit_loss":            profitLoss,
		"profit_loss_percentage": (profitLoss / totalInvested) * 100,
	})
}
