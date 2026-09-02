package nseimport

import (
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"strconv"
	"strings"
	"time"

	"financetracker/models"

	"gorm.io/gorm"
)

// Result is the summary of an NSE catalog upsert.
type Result struct {
	Created int `json:"created"`
	Updated int `json:"updated"`
	Skipped int `json:"skipped"`
	Errors  int `json:"errors"`
}

type catalogRow struct {
	stock   models.Stock
	updates map[string]interface{}
}

func parseNSEDate(raw string) *time.Time {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	for _, layout := range []string{"02-Jan-06", "2-Jan-06", "02-Jan-2006", "2006-01-02"} {
		if t, err := time.Parse(layout, raw); err == nil {
			return &t
		}
	}
	return nil
}

func parseFloat(raw string) (float64, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return 0, false
	}
	raw = strings.ReplaceAll(raw, ",", "")
	v, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		return 0, false
	}
	return v, true
}

func colIndex(header []string, names ...string) int {
	normalized := make([]string, len(header))
	for i, h := range header {
		normalized[i] = strings.ToLower(strings.TrimSpace(h))
	}
	for _, name := range names {
		want := strings.ToLower(strings.TrimSpace(name))
		for i, h := range normalized {
			if h == want {
				return i
			}
		}
	}
	return -1
}

func cell(row []string, idx int) string {
	if idx < 0 || idx >= len(row) {
		return ""
	}
	return strings.TrimSpace(row[idx])
}

func setString(updates map[string]interface{}, column, value string, assign func(string)) {
	if value == "" {
		return
	}
	assign(value)
	updates[column] = value
}

func setFloat(updates map[string]interface{}, column, raw string, assign func(float64)) {
	v, ok := parseFloat(raw)
	if !ok {
		return
	}
	assign(v)
	updates[column] = v
}

func setDate(updates map[string]interface{}, column, raw string, assign func(*time.Time)) {
	t := parseNSEDate(raw)
	if t == nil {
		return
	}
	assign(t)
	updates[column] = *t
}

// ImportCSV upserts Global_Stocks from an NSE_All or Nifty constituent CSV.
// Required headers: Symbol, and a name column (Security Name or Company Name).
// Close price and Industry are optional. Only columns present with a value are written,
// so a Nifty upload does not zero prices or wipe listing fields.
// Does not overwrite pull_data=Y with N. Skips footer aggregate rows.
func ImportCSV(db *gorm.DB, r io.Reader) (Result, error) {
	var out Result
	reader := csv.NewReader(r)
	reader.TrimLeadingSpace = true
	reader.FieldsPerRecord = -1

	header, err := reader.Read()
	if err != nil {
		return out, fmt.Errorf("read header: %w", err)
	}

	iSymbol := colIndex(header, "Symbol")
	iName := colIndex(header, "Security Name", "Company Name")
	iClose := colIndex(header, "Close Price/Paid up value(Rs.)")
	iIndustry := colIndex(header, "Industry")
	iTradeDate := colIndex(header, "Trade Date")
	iSeries := colIndex(header, "Series")
	iCategory := colIndex(header, "Category")
	iLastTrade := colIndex(header, "Last Trade Date")
	iFace := colIndex(header, "Face Value(Rs.)")
	iIssue := colIndex(header, "Issue Size")
	iMcap := colIndex(header, "Market Cap(Rs.)")

	if iSymbol < 0 || iName < 0 {
		return out, fmt.Errorf("csv missing required columns (Symbol, Security Name or Company Name); got %v", header)
	}

	now := time.Now()
	const batchSize = 200
	batch := make([]catalogRow, 0, batchSize)

	flush := func() {
		if len(batch) == 0 {
			return
		}
		for _, row := range batch {
			var existing models.Stock
			err := db.Where("UPPER(symbol) = ?", row.stock.Symbol).First(&existing).Error
			if err == gorm.ErrRecordNotFound {
				row.stock.PullData = models.PullDataNo
				if err := db.Create(&row.stock).Error; err != nil {
					out.Errors++
					log.Printf("nseimport create %s: %v", row.stock.Symbol, err)
					continue
				}
				out.Created++
				continue
			}
			if err != nil {
				out.Errors++
				log.Printf("nseimport lookup %s: %v", row.stock.Symbol, err)
				continue
			}
			if len(row.updates) == 0 {
				out.Skipped++
				continue
			}
			if err := db.Model(&existing).Updates(row.updates).Error; err != nil {
				out.Errors++
				log.Printf("nseimport update %s: %v", row.stock.Symbol, err)
				continue
			}
			out.Updated++
		}
		batch = batch[:0]
	}

	for {
		rec, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			out.Errors++
			log.Printf("nseimport read row: %v", err)
			continue
		}
		symbol := strings.ToUpper(cell(rec, iSymbol))
		if symbol == "" {
			out.Skipped++
			continue
		}
		if symbol == "LISTED" || symbol == "PERMITTED" || symbol == "TOTAL" {
			out.Skipped++
			continue
		}
		series := cell(rec, iSeries)
		name := cell(rec, iName)
		if series == "" && name == "" {
			out.Skipped++
			continue
		}

		stock := models.Stock{Symbol: symbol, PullData: models.PullDataNo}
		updates := make(map[string]interface{})

		setString(updates, "name", name, func(v string) { stock.Name = v })
		if iSeries >= 0 {
			setString(updates, "series", series, func(v string) { stock.Series = v })
		}
		if iIndustry >= 0 {
			setString(updates, "industry", cell(rec, iIndustry), func(v string) { stock.Industry = v })
		}
		if iCategory >= 0 {
			setString(updates, "listing_category", cell(rec, iCategory), func(v string) { stock.ListingCategory = v })
		}
		if iClose >= 0 {
			if v, ok := parseFloat(cell(rec, iClose)); ok {
				stock.CurrentPrice = v
				stock.LastPriceFetchedDate = &now
				updates["current_price"] = v
				updates["last_price_fetched_date"] = now
			}
		}
		if iTradeDate >= 0 {
			setDate(updates, "trade_date", cell(rec, iTradeDate), func(t *time.Time) { stock.TradeDate = t })
		}
		if iLastTrade >= 0 {
			setDate(updates, "last_trade_date", cell(rec, iLastTrade), func(t *time.Time) { stock.LastTradeDate = t })
		}
		if iFace >= 0 {
			setFloat(updates, "face_value", cell(rec, iFace), func(v float64) { stock.FaceValue = v })
		}
		if iIssue >= 0 {
			setFloat(updates, "issue_size", cell(rec, iIssue), func(v float64) { stock.IssueSize = v })
		}
		if iMcap >= 0 {
			setFloat(updates, "market_cap_rs", cell(rec, iMcap), func(v float64) { stock.MarketCapRs = v })
		}

		batch = append(batch, catalogRow{stock: stock, updates: updates})
		if len(batch) >= batchSize {
			flush()
		}
	}
	flush()

	if res := db.Where("UPPER(symbol) IN ?", []string{"LISTED", "PERMITTED", "TOTAL"}).Delete(&models.Stock{}); res.Error != nil {
		log.Printf("nseimport cleanup footer rows: %v", res.Error)
	}

	return out, nil
}
