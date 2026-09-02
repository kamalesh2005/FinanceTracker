package handlers

import (
	"log"
	"strings"
	"time"

	"financetracker/models"

	"gorm.io/gorm"
)

const (
	catalogDailyLimit         = 250
	catalogWeeklyInterval     = 7 * 24 * time.Hour
	catalogConsensusNewsMinAge = 7 * 24 * time.Hour
	catalogBatchSize          = 25
	catalogPaceBetweenStocks  = 200 * time.Millisecond
	catalogPaceBetweenBatches = 2 * time.Second
)

var catalogTargetNewsPolicy = yahooTargetNewsPolicy{
	minConsensusAge: catalogConsensusNewsMinAge,
	minNewsAge:      catalogConsensusNewsMinAge,
}

// BuildNonHeldEQCatalogQueue returns up to the remaining daily quota of non-held EQ
// stocks due for a weekly catalog Yahoo refresh.
func BuildNonHeldEQCatalogQueue(db *gorm.DB, now time.Time) ([]models.Stock, error) {
	if db == nil {
		return nil, nil
	}
	loc := now.Location()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	weeklyCutoff := now.Add(-catalogWeeklyInterval)

	var dailyCount int64
	if err := db.Model(&models.Stock{}).
		Where("pull_data <> ? AND series = ? AND last_catalog_yahoo_refresh_at >= ?",
			models.PullDataYes, "EQ", todayStart).
		Count(&dailyCount).Error; err != nil {
		return nil, err
	}
	if dailyCount >= catalogDailyLimit {
		return nil, nil
	}
	remaining := int(catalogDailyLimit - dailyCount)

	var stocks []models.Stock
	err := db.Where("pull_data <> ? AND series = ?", models.PullDataYes, "EQ").
		Where("last_catalog_yahoo_refresh_at IS NULL OR last_catalog_yahoo_refresh_at < ?", weeklyCutoff).
		Where("last_catalog_yahoo_refresh_at IS NULL OR last_catalog_yahoo_refresh_at < ?", todayStart).
		Order("last_catalog_yahoo_refresh_at IS NULL DESC, last_catalog_yahoo_refresh_at ASC, symbol ASC").
		Limit(remaining).
		Find(&stocks).Error
	if err != nil {
		return nil, err
	}
	return stocks, nil
}

// CountNonHeldEQCatalogRefreshedToday counts catalog refreshes completed today (IST calendar day of now).
func CountNonHeldEQCatalogRefreshedToday(db *gorm.DB, now time.Time) (int64, error) {
	if db == nil {
		return 0, nil
	}
	loc := now.Location()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	var count int64
	err := db.Model(&models.Stock{}).
		Where("pull_data <> ? AND series = ? AND last_catalog_yahoo_refresh_at >= ?",
			models.PullDataYes, "EQ", todayStart).
		Count(&count).Error
	return count, err
}

// refreshStockPricesAndTrendsBatch runs the shared Yahoo price/history/trend loop.
func (h *Handler) refreshStockPricesAndTrendsBatch(
	stocks []models.Stock,
	logPrefix string,
	policy yahooTargetNewsPolicy,
	stampCatalogRefresh bool,
	paceBetweenStocks time.Duration,
) (ok, fail int) {
	if len(stocks) == 0 {
		return 0, 0
	}

	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	log.Printf("%s: starting for %d stocks", logPrefix, len(stocks))

	needsAnyTrend := false
	needsAnyHistorical := false
	for i := range stocks {
		if needsTrendData(&stocks[i], today) {
			needsAnyTrend = true
		}
		if stocks[i].LastFetchedDate == nil || stocks[i].LastFetchedDate.Before(today) || needsYahooHistoricalData(&stocks[i]) {
			needsAnyHistorical = true
		}
	}
	var sensexMA7, sensexMA20, sensexMA50, marketSTDelta, marketMTDelta float64
	if needsAnyTrend || needsAnyHistorical {
		if sx, err := h.syncSensexHistory(now); err == nil {
			sensexMA7, sensexMA20, sensexMA50 = sx.MA7, sx.MA20, sx.MA50
			marketSTDelta, marketMTDelta = sx.STDelta, sx.MTDelta
			log.Printf("%s: Sensex MA7=%.2f MA20=%.2f MA50=%.2f marketSTDelta=%.2f marketMTDelta=%.2f skipped=%v",
				logPrefix, sensexMA7, sensexMA20, sensexMA50, marketSTDelta, marketMTDelta, sx.Skipped)
		} else {
			log.Printf("%s: Sensex sync FAIL: %v", logPrefix, err)
		}
	}

	trendRS := h.loadTrendRuleset()
	for i := range stocks {
		if paceBetweenStocks > 0 && i > 0 {
			time.Sleep(paceBetweenStocks)
		}
		s := &stocks[i]
		yahoo := resolveYahooSymbol(s.Symbol)
		normISIN := normalizeISIN(s.ISIN)
		log.Printf("%s [%s]: yahoo=%s isin_raw=%q isin_norm=%q price=%.2f high6=%.2f low6=%.2f",
			logPrefix, s.Symbol, yahoo, s.ISIN, normISIN, s.CurrentPrice, s.SixthHighestPrice, s.SixthLowestPrice)

		priceFetchedToday := isSameCalendarDay(s.LastPriceFetchedDate, today)
		priceErr := ""
		priceFailed := false
		if !priceFetchedToday {
			if price, err := fetchYahooFinancePrice(s.Symbol); err == nil {
				s.CurrentPrice = price
				s.LastPriceFetchedDate = &now
				h.DB.Model(s).Updates(map[string]interface{}{
					"current_price":           price,
					"last_price_fetched_date": now,
				})
				persistYahooTargetAndNews(h.DB, s, price, now, policy)
				log.Printf("%s [%s]: price OK %.2f (via %s)", logPrefix, s.Symbol, price, yahoo)
			} else {
				priceErr = err.Error()
				priceFailed = true
				fail++
				log.Printf("%s [%s]: price FAIL via %s: %v", logPrefix, s.Symbol, yahoo, err)
			}
		} else {
			log.Printf("%s [%s]: price skipped (already fetched today)", logPrefix, s.Symbol)
			if s.CurrentPrice > 0 && (s.ConsensusTarget == 0 || strings.TrimSpace(s.NewsHeadline) == "") {
				persistYahooTargetAndNews(h.DB, s, s.CurrentPrice, now, policy)
			}
		}

		if s.CurrentPrice == 0 && strings.TrimSpace(s.ISIN) != "" {
			log.Printf("%s [%s]: attempting ISIN auto-map (price still 0, isin present)", logPrefix, s.Symbol)
			h.applyYahooDataWithAutoMapping(s, models.SourceFormatManual)
			h.persistYahooStockFields(s)
			yahoo = resolveYahooSymbol(s.Symbol)
			log.Printf("%s [%s]: after ISIN auto-map yahoo=%s price=%.2f", logPrefix, s.Symbol, yahoo, s.CurrentPrice)
		} else if s.CurrentPrice == 0 && strings.TrimSpace(s.ISIN) == "" {
			log.Printf("%s [%s]: price=0 and no ISIN — cannot auto-map", logPrefix, s.Symbol)
		}

		needsHistorical := s.LastFetchedDate == nil ||
			s.LastFetchedDate.Before(today) ||
			needsYahooHistoricalData(s)
		needsTrend := needsTrendData(s, today)

		if needsHistorical {
			if sector, industry, err := fetchYahooFinanceAssetProfile(s.Symbol); err == nil {
				if sector != "" {
					s.Sector = sector
					h.DB.Model(s).Update("sector", sector)
				}
				if industry != "" {
					s.Industry = industry
					h.DB.Model(s).Update("industry", industry)
				}
			}
			if s.MarketCap == "" {
				if marketCap, err := fetchYahooFinanceMarketCap(s.Symbol); err == nil {
					label := classifyMarketCap(marketCap)
					s.MarketCap = label
					h.DB.Model(s).Update("market_cap", label)
				}
			}
		}

		if needsHistorical || needsTrend {
			if err := h.fetchAndPersistStockTrend(s, trendRS, sensexMA7, sensexMA20, sensexMA50, marketSTDelta, marketMTDelta, now); err != nil {
				log.Printf("%s [%s]: history/trend FAIL: %v", logPrefix, s.Symbol, err)
				if needsYahooHistoricalData(s) && strings.TrimSpace(s.ISIN) != "" {
					log.Printf("%s [%s]: historical still missing — ISIN auto-map retry", logPrefix, s.Symbol)
					h.applyYahooDataWithAutoMapping(s, models.SourceFormatManual)
					h.persistYahooStockFields(s)
				}
			} else {
				log.Printf("%s [%s]: history/trend OK %s ma7=%.2f ma20=%.2f ma50=%.2f high6=%.2f low6=%.2f adjST=%.2f adjMT=%.2f",
					logPrefix, s.Symbol, s.Trend, s.MA7, s.MA20, s.MA50, s.SixthHighestPrice, s.SixthLowestPrice, s.AdjustedSTDelta, s.AdjustedMTDelta)
			}
		} else {
			log.Printf("%s [%s]: history/trend skipped (already fetched today)", logPrefix, s.Symbol)
		}

		if stampCatalogRefresh && s.ID != 0 && !priceFailed {
			s.LastCatalogYahooRefreshAt = &now
			if err := h.DB.Model(s).Update("last_catalog_yahoo_refresh_at", now).Error; err != nil {
				log.Printf("%s [%s]: catalog stamp FAIL: %v", logPrefix, s.Symbol, err)
			}
		}

		status := "OK"
		if needsYahooAnyData(s) {
			status = "INCOMPLETE"
		}
		if priceErr == "" {
			ok++
		}
		log.Printf("%s [%s]: DONE status=%s yahoo=%s price=%.2f high6=%.2f low6=%.2f sector=%q industry=%q mcap=%q priceErr=%q",
			logPrefix, s.Symbol, status, resolveYahooSymbol(s.Symbol), s.CurrentPrice, s.SixthHighestPrice, s.SixthLowestPrice,
			s.Sector, s.Industry, s.MarketCap, priceErr)
	}
	log.Printf("%s: finished %d stocks ok=%d fail=%d", logPrefix, len(stocks), ok, fail)
	return ok, fail
}

// RefreshNonHeldEQCatalogDaily refreshes up to 250 non-held EQ catalog stocks per IST day,
// at most once per week per stock, with batched pacing.
func (h *Handler) RefreshNonHeldEQCatalogDaily() error {
	now := time.Now()
	dailyCount, err := CountNonHeldEQCatalogRefreshedToday(h.DB, now)
	if err != nil {
		return err
	}
	log.Printf("CatalogYahooCron: daily refreshed so far=%d limit=%d", dailyCount, catalogDailyLimit)
	if dailyCount >= catalogDailyLimit {
		log.Printf("CatalogYahooCron: daily quota reached; skipping")
		return nil
	}

	queue, err := BuildNonHeldEQCatalogQueue(h.DB, now)
	if err != nil {
		return err
	}
	if len(queue) == 0 {
		log.Printf("CatalogYahooCron: nothing to do")
		return nil
	}
	log.Printf("CatalogYahooCron: queued %d stocks", len(queue))

	totalOK, totalFail := 0, 0
	totalBatches := (len(queue) + catalogBatchSize - 1) / catalogBatchSize
	for i := 0; i < len(queue); i += catalogBatchSize {
		end := i + catalogBatchSize
		if end > len(queue) {
			end = len(queue)
		}
		batchNum := (i / catalogBatchSize) + 1
		batch := queue[i:end]
		log.Printf("CatalogYahooCron: batch %d/%d size=%d", batchNum, totalBatches, len(batch))

		ok, fail := h.refreshStockPricesAndTrendsBatch(
			batch, "CatalogYahooCron", catalogTargetNewsPolicy, true, catalogPaceBetweenStocks,
		)
		totalOK += ok
		totalFail += fail

		if end < len(queue) {
			time.Sleep(catalogPaceBetweenBatches)
		}
	}
	log.Printf("CatalogYahooCron: completed ok=%d fail=%d total=%d", totalOK, totalFail, len(queue))
	return nil
}
