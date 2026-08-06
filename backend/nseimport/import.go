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

func parseFloat(raw string) float64 {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return 0
	}
	v, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		return 0
	}
	return v
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

// ImportCSV upserts Global_Stocks from an NSE_All-style CSV reader.
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
	iName := colIndex(header, "Security Name")
	iClose := colIndex(header, "Close Price/Paid up value(Rs.)")
	iTradeDate := colIndex(header, "Trade Date")
	iSeries := colIndex(header, "Series")
	iCategory := colIndex(header, "Category")
	iLastTrade := colIndex(header, "Last Trade Date")
	iFace := colIndex(header, "Face Value(Rs.)")
	iIssue := colIndex(header, "Issue Size")
	iMcap := colIndex(header, "Market Cap(Rs.)")

	if iSymbol < 0 || iName < 0 || iClose < 0 {
		return out, fmt.Errorf("csv missing required columns (Symbol, Security Name, Close Price); got %v", header)
	}

	now := time.Now()
	const batchSize = 200
	batch := make([]models.Stock, 0, batchSize)

	flush := func() {
		if len(batch) == 0 {
			return
		}
		for _, row := range batch {
			var existing models.Stock
			err := db.Where("symbol = ?", row.Symbol).First(&existing).Error
			if err == gorm.ErrRecordNotFound {
				row.PullData = models.PullDataNo
				if err := db.Create(&row).Error; err != nil {
					out.Errors++
					log.Printf("nseimport create %s: %v", row.Symbol, err)
					continue
				}
				out.Created++
				continue
			}
			if err != nil {
				out.Errors++
				log.Printf("nseimport lookup %s: %v", row.Symbol, err)
				continue
			}
			updates := map[string]interface{}{
				"name":                    row.Name,
				"current_price":           row.CurrentPrice,
				"last_price_fetched_date": row.LastPriceFetchedDate,
				"trade_date":              row.TradeDate,
				"series":                  row.Series,
				"listing_category":        row.ListingCategory,
				"last_trade_date":         row.LastTradeDate,
				"face_value":              row.FaceValue,
				"issue_size":              row.IssueSize,
				"market_cap_rs":           row.MarketCapRs,
			}
			if err := db.Model(&existing).Updates(updates).Error; err != nil {
				out.Errors++
				log.Printf("nseimport update %s: %v", row.Symbol, err)
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
		stock := models.Stock{
			Symbol:               symbol,
			Name:                 name,
			CurrentPrice:         parseFloat(cell(rec, iClose)),
			LastPriceFetchedDate: &now,
			TradeDate:            parseNSEDate(cell(rec, iTradeDate)),
			Series:               series,
			ListingCategory:      cell(rec, iCategory),
			LastTradeDate:        parseNSEDate(cell(rec, iLastTrade)),
			FaceValue:            parseFloat(cell(rec, iFace)),
			IssueSize:            parseFloat(cell(rec, iIssue)),
			MarketCapRs:          parseFloat(cell(rec, iMcap)),
			PullData:             models.PullDataNo,
		}
		batch = append(batch, stock)
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
