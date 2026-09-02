package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const (
	nifty50Symbol      = "NIFTY50"
	nifty50YahooTicker = "^NSEI"
	nifty50Name        = "Nifty 50"
)

// SeedNifty50Index upserts the NIFTY50 row with FY-end levels, always overwriting
// fy_* so a calendar→FY migration picks up the new Mar-end closes.
func SeedNifty50Index(db *gorm.DB) error {
	// FY N ends last trading day on/before 31 Mar (N+1).
	fy := map[string]float64{
		"fy_2020": 14867, // ~31 Mar 2021
		"fy_2021": 17465, // ~31 Mar 2022
		"fy_2022": 17360, // ~31 Mar 2023
		"fy_2023": 22327, // ~28 Mar 2024
		"fy_2024": 23519, // ~28 Mar 2025
		"fy_2025": 22331, // ~31 Mar 2026
	}
	var row models.GlobalIndex
	err := db.Where("symbol = ?", nifty50Symbol).First(&row).Error
	if err == gorm.ErrRecordNotFound {
		row = models.GlobalIndex{
			Symbol:      nifty50Symbol,
			Name:        nifty50Name,
			YahooSymbol: nifty50YahooTicker,
			FY2020:      fy["fy_2020"],
			FY2021:      fy["fy_2021"],
			FY2022:      fy["fy_2022"],
			FY2023:      fy["fy_2023"],
			FY2024:      fy["fy_2024"],
			FY2025:      fy["fy_2025"],
		}
		if err := db.Create(&row).Error; err != nil {
			return err
		}
		log.Printf("SeedNifty50Index: created NIFTY50 FY-end levels")
		return nil
	}
	if err != nil {
		return err
	}
	updates := map[string]interface{}{
		"fy_2020": fy["fy_2020"],
		"fy_2021": fy["fy_2021"],
		"fy_2022": fy["fy_2022"],
		"fy_2023": fy["fy_2023"],
		"fy_2024": fy["fy_2024"],
		"fy_2025": fy["fy_2025"],
	}
	if strings.TrimSpace(row.Name) == "" {
		updates["name"] = nifty50Name
	}
	if strings.TrimSpace(row.YahooSymbol) == "" {
		updates["yahoo_symbol"] = nifty50YahooTicker
	}
	if err := db.Model(&row).Updates(updates).Error; err != nil {
		return err
	}
	log.Printf("SeedNifty50Index: upserted NIFTY50 FY-end levels")
	return nil
}

func applyIndexReturns(idx *models.GlobalIndex) {
	idx.Return2021 = pctReturn(idx.FY2020, idx.FY2021)
	idx.Return2022 = pctReturn(idx.FY2021, idx.FY2022)
	idx.Return2023 = pctReturn(idx.FY2022, idx.FY2023)
	idx.Return2024 = pctReturn(idx.FY2023, idx.FY2024)
	idx.Return2025 = pctReturn(idx.FY2024, idx.FY2025)
	idx.ReturnYTD = pctReturn(idx.FY2025, idx.CurrentValue)
}

func fetchYahooIndexPrice(ticker string) (float64, error) {
	ticker = strings.TrimSpace(ticker)
	if ticker == "" {
		return 0, fmt.Errorf("empty yahoo ticker")
	}
	reqURL := yahooChartURLDirect(ticker, "", "interval=1d&range=1d")
	req, err := http.NewRequest(http.MethodGet, reqURL, nil)
	if err != nil {
		return 0, err
	}
	resp, err := yahooDo(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("yahoo chart HTTP %d for %s", resp.StatusCode, ticker)
	}
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
		return 0, err
	}
	if result.Chart.Error != nil || len(result.Chart.Result) == 0 {
		return 0, fmt.Errorf("yahoo chart empty for %s", ticker)
	}
	price := result.Chart.Result[0].Meta.RegularMarketPrice
	if price <= 0 {
		return 0, fmt.Errorf("yahoo chart price 0 for %s", ticker)
	}
	return price, nil
}

// RefreshNifty50CurrentValue pulls ^NSEI once per IST calendar day into Global_Indices.
func (h *Handler) RefreshNifty50CurrentValue() error {
	if err := SeedNifty50Index(h.DB); err != nil {
		return err
	}
	var row models.GlobalIndex
	if err := h.DB.Where("symbol = ?", nifty50Symbol).First(&row).Error; err != nil {
		return err
	}
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}
	now := time.Now().In(ist)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, ist)
	if isSameCalendarDay(row.LastValueDate, today) {
		log.Printf("Nifty50: current skipped (already fetched today) value=%.2f", row.CurrentValue)
		return nil
	}
	ticker := strings.TrimSpace(row.YahooSymbol)
	if ticker == "" {
		ticker = nifty50YahooTicker
	}
	price, err := fetchYahooIndexPrice(ticker)
	if err != nil {
		log.Printf("Nifty50: yahoo FAIL ticker=%s: %v", ticker, err)
		return err
	}
	if err := h.DB.Model(&models.GlobalIndex{}).Where("id = ?", row.ID).Updates(map[string]interface{}{
		"current_value":   price,
		"last_value_date": now,
		"updated_at":      now,
	}).Error; err != nil {
		return err
	}
	log.Printf("Nifty50: current OK %.2f (via %s)", price, ticker)
	return nil
}

func (h *Handler) GetIndices(c *gin.Context) {
	var rows []models.GlobalIndex
	if err := h.DB.Order("symbol").Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if rows == nil {
		rows = []models.GlobalIndex{}
	}
	for i := range rows {
		applyIndexReturns(&rows[i])
	}
	c.JSON(http.StatusOK, rows)
}
