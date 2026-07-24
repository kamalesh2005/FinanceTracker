package handlers

import (
	"log"
	"time"

	"financetracker/models"
)

// UpdateAllCurrentPrices fetches Yahoo regular-market prices for every Global_Stocks
// row and always overwrites current_price (no once-per-day skip). Used by the
// intraday market-hours cron.
func (h *Handler) UpdateAllCurrentPrices() {
	var stocks []models.Stock
	if err := h.DB.Find(&stocks).Error; err != nil {
		log.Printf("IntradayPriceCron: failed to load stocks: %v", err)
		return
	}

	now := time.Now()
	ok, fail := 0, 0
	log.Printf("IntradayPriceCron: starting for %d stocks", len(stocks))

	for i := range stocks {
		s := &stocks[i]
		price, err := fetchYahooFinancePrice(s.Symbol)
		if err != nil {
			fail++
			log.Printf("IntradayPriceCron [%s]: FAIL via %s: %v",
				s.Symbol, resolveYahooSymbol(s.Symbol), err)
			continue
		}
		s.CurrentPrice = price
		s.LastPriceFetchedDate = &now
		if err := h.DB.Model(s).Updates(map[string]interface{}{
			"current_price":           price,
			"last_price_fetched_date": now,
		}).Error; err != nil {
			fail++
			log.Printf("IntradayPriceCron [%s]: DB update FAIL: %v", s.Symbol, err)
			continue
		}
		ok++
		log.Printf("IntradayPriceCron [%s]: OK %.2f (via %s)",
			s.Symbol, price, resolveYahooSymbol(s.Symbol))
	}

	log.Printf("IntradayPriceCron: finished ok=%d fail=%d total=%d", ok, fail, len(stocks))
}
