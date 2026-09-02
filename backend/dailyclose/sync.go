package dailyclose

import (
	"fmt"
	"strings"
	"time"

	"financetracker/models"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const (
	SensexSymbol      = "SENSEX"
	SensexYahooTicker = "^BSESN"
	CloseWindowDays   = 100
	MaxTradingDays    = 60
)

// SyncResult is the outcome of a once-a-day Yahoo history sync.
type SyncResult struct {
	Skipped     bool
	MA7         float64
	MA20        float64
	MA50        float64
	STDelta     float64
	MTDelta     float64
	SixthHigh   float64
	SixthLow    float64
	LatestClose float64
	LatestDate  time.Time
}

func sameCalendarDay(t *time.Time, today time.Time) bool {
	if t == nil {
		return false
	}
	loc := today.Location()
	local := t.In(loc)
	d := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, loc)
	return d.Equal(today)
}

func calcSMA(closes []float64, period int) float64 {
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

// LoadLatestMAs reads MA fields from the is_latest daily-close row.
func LoadLatestMAs(db *gorm.DB, symbol string) (ma7, ma20, ma50, close float64, date time.Time, ok bool) {
	var row models.StockDailyClose
	err := db.Where("symbol = ? AND is_latest = ?", strings.ToUpper(strings.TrimSpace(symbol)), true).
		First(&row).Error
	if err != nil {
		return 0, 0, 0, 0, time.Time{}, false
	}
	return row.MA7, row.MA20, row.MA50, row.ClosingPrice, row.TradeDate, true
}

// SyncYahooHistory fetches one 1y Yahoo chart (unless already synced today),
// upserts ~60 trading days of closes, computes MAs and sixth high/low.
func SyncYahooHistory(db *gorm.DB, symbol, yahooTicker string, suffixes []string, now time.Time) (SyncResult, error) {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if symbol == "" {
		return SyncResult{}, fmt.Errorf("symbol required")
	}
	if yahooTicker == "" {
		yahooTicker = symbol
	}
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	var sync models.StockDailyCloseSync
	_ = db.First(&sync, "symbol = ?", symbol).Error
	if sameCalendarDay(sync.LastYahooFetchedDate, today) {
		ma7, ma20, ma50, closePx, dt, ok := LoadLatestMAs(db, symbol)
		out := SyncResult{Skipped: true, MA7: ma7, MA20: ma20, MA50: ma50, LatestClose: closePx, LatestDate: dt}
		if ok {
			out.STDelta = calcDelta(ma7, ma20)
			out.MTDelta = calcDelta(ma20, ma50)
		}
		return out, nil
	}

	if symbol == SensexSymbol {
		suffixes = []string{""}
		if yahooTicker == SensexSymbol {
			yahooTicker = SensexYahooTicker
		}
	}

	bars, err := FetchYearBars(yahooTicker, suffixes)
	if err != nil {
		return SyncResult{}, err
	}

	windowStart := today.AddDate(0, 0, -CloseWindowDays)
	windowBars := make([]DayBar, 0, MaxTradingDays)
	for _, b := range bars {
		if b.Date.Before(windowStart) {
			continue
		}
		windowBars = append(windowBars, b)
	}
	if len(windowBars) > MaxTradingDays {
		windowBars = windowBars[len(windowBars)-MaxTradingDays:]
	}

	for _, b := range windowBars {
		row := models.StockDailyClose{
			TradeDate:    b.Date,
			Symbol:       symbol,
			ClosingPrice: b.Close,
		}
		err := db.Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "symbol"}, {Name: "trade_date"}},
			DoUpdates: clause.AssignmentColumns([]string{"closing_price", "updated_at"}),
		}).Create(&row).Error
		if err != nil {
			return SyncResult{}, fmt.Errorf("upsert close %s %s: %w", symbol, b.Date.Format("2006-01-02"), err)
		}
	}

	ma7, ma20, ma50, latestClose, latestDate, err := recalcMAs(db, symbol)
	if err != nil {
		return SyncResult{}, err
	}

	var highs, lows []float64
	for _, b := range bars {
		if b.High > 0 {
			highs = append(highs, b.High)
		}
		if b.Low > 0 {
			lows = append(lows, b.Low)
		}
	}

	out := SyncResult{
		Skipped:     false,
		MA7:         ma7,
		MA20:        ma20,
		MA50:        ma50,
		STDelta:     calcDelta(ma7, ma20),
		MTDelta:     calcDelta(ma20, ma50),
		SixthHigh:   sixthHighest(highs),
		SixthLow:    sixthLowest(lows),
		LatestClose: latestClose,
		LatestDate:  latestDate,
	}

	sync = models.StockDailyCloseSync{
		Symbol:               symbol,
		LastYahooFetchedDate: &today,
		UpdatedAt:            now,
	}
	if err := db.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "symbol"}},
		DoUpdates: clause.AssignmentColumns([]string{"last_yahoo_fetched_date", "updated_at"}),
	}).Create(&sync).Error; err != nil {
		return out, fmt.Errorf("stamp sync %s: %w", symbol, err)
	}
	return out, nil
}

func recalcMAs(db *gorm.DB, symbol string) (ma7, ma20, ma50, latestClose float64, latestDate time.Time, err error) {
	var rows []models.StockDailyClose
	if err = db.Where("symbol = ?", symbol).Order("trade_date asc").Find(&rows).Error; err != nil {
		return
	}
	if len(rows) == 0 {
		err = fmt.Errorf("no daily closes for %s", symbol)
		return
	}

	closes := make([]float64, len(rows))
	for i, r := range rows {
		closes[i] = r.ClosingPrice
	}
	ma7 = calcSMA(closes, 7)
	ma20 = calcSMA(closes, 20)
	ma50 = calcSMA(closes, 50)
	latest := rows[len(rows)-1]
	latestClose = latest.ClosingPrice
	latestDate = latest.TradeDate

	if err = db.Model(&models.StockDailyClose{}).Where("symbol = ?", symbol).Update("is_latest", false).Error; err != nil {
		return
	}
	if err = db.Model(&models.StockDailyClose{}).Where("id = ?", latest.ID).Updates(map[string]interface{}{
		"is_latest": true,
		"ma7":       ma7,
		"ma20":      ma20,
		"ma50":      ma50,
	}).Error; err != nil {
		return
	}
	return
}

// UpsertClose inserts/updates a single day's close and fixes is_latest (no MA recalc).
func UpsertClose(db *gorm.DB, symbol string, tradeDate time.Time, price float64) (created bool, err error) {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	tradeDate = time.Date(tradeDate.Year(), tradeDate.Month(), tradeDate.Day(), 0, 0, 0, 0, time.UTC)

	var existing models.StockDailyClose
	findErr := db.Where("symbol = ? AND trade_date = ?", symbol, tradeDate).First(&existing).Error
	if findErr == gorm.ErrRecordNotFound {
		row := models.StockDailyClose{
			TradeDate:    tradeDate,
			Symbol:       symbol,
			ClosingPrice: price,
		}
		if err = db.Create(&row).Error; err != nil {
			return false, err
		}
		created = true
	} else if findErr != nil {
		return false, findErr
	} else {
		if err = db.Model(&existing).Update("closing_price", price).Error; err != nil {
			return false, err
		}
	}

	var latest models.StockDailyClose
	if err = db.Where("symbol = ?", symbol).Order("trade_date DESC").First(&latest).Error; err != nil {
		return created, err
	}
	_ = db.Model(&models.StockDailyClose{}).Where("symbol = ?", symbol).Update("is_latest", false).Error
	_ = db.Model(&models.StockDailyClose{}).
		Where("symbol = ? AND trade_date = ?", symbol, latest.TradeDate).
		Update("is_latest", true).Error
	return created, nil
}
