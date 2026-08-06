package etfimport

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

// Result is the summary of an ETF CSV import.
type Result struct {
	Created int `json:"created"`
	Updated int `json:"updated"`
	Skipped int `json:"skipped"`
	Errors  int `json:"errors"`
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

// ImportCSV imports ETF rows from a CSV.
//
// Required headers (case-insensitive):
//   - SYMBOL
//   - SECURITY
//   - CLOSE PRICE
//   - 52 WEEK HIGH
//   - 52 WEEK LOW
//
// Updates models.Stock fields:
//   - name, sector/industry, current_price, sixth_highest_price, sixth_lowest_price,
//     last_price_fetched_date
//
// It never overwrites pull_data=Y with pull_data=N.
func ImportCSV(db *gorm.DB, r io.Reader) (Result, error) {
	var out Result

	reader := csv.NewReader(r)
	reader.TrimLeadingSpace = true
	reader.FieldsPerRecord = -1

	header, err := reader.Read()
	if err != nil {
		return out, fmt.Errorf("read header: %w", err)
	}

	iSymbol := colIndex(header, "SYMBOL", "Symbol")
	iName := colIndex(header, "SECURITY", "Security")
	iClose := colIndex(header, "CLOSE PRICE", "Close Price")
	i52High := colIndex(header, "52 WEEK HIGH", "52 Week High")
	i52Low := colIndex(header, "52 WEEK LOW", "52 Week Low")

	if iSymbol < 0 || iName < 0 || iClose < 0 || i52High < 0 || i52Low < 0 {
		return out, fmt.Errorf(
			"csv missing required columns (SYMBOL, SECURITY, CLOSE PRICE, 52 WEEK HIGH, 52 WEEK LOW); got %v",
			header,
		)
	}

	now := time.Now()

	// Keep memory bounded (still does a per-row lookup like other imports in this repo).
	const batchSize = 200
	batch := make([]struct {
		symbol string
		name   string
		close  float64
		high   float64
		low    float64
	}, 0, batchSize)

	flush := func() error {
		for _, row := range batch {
			var existing models.Stock
			err := db.Where("UPPER(symbol) = ?", row.symbol).First(&existing).Error
			if err == gorm.ErrRecordNotFound {
				stock := models.Stock{
					Symbol:               row.symbol,
					Name:                 row.name,
					Sector:               "ETF",
					Industry:             "ETF",
					CurrentPrice:         row.close,
					SixthHighestPrice:    row.high,
					SixthLowestPrice:     row.low,
					LastPriceFetchedDate: &now,
					PullData:             models.PullDataNo,
				}
				if err := db.Create(&stock).Error; err != nil {
					out.Errors++
					log.Printf("etfimport create %s: %v", row.symbol, err)
					continue
				}
				out.Created++
				continue
			}
			if err != nil {
				out.Errors++
				log.Printf("etfimport lookup %s: %v", row.symbol, err)
				continue
			}

			updates := map[string]interface{}{
				"name":                    row.name,
				"sector":                  "ETF",
				"industry":                "ETF",
				"current_price":           row.close,
				"sixth_highest_price":     row.high,
				"sixth_lowest_price":      row.low,
				"last_price_fetched_date": now,
			}
			if err := db.Model(&existing).Updates(updates).Error; err != nil {
				out.Errors++
				log.Printf("etfimport update %s: %v", row.symbol, err)
				continue
			}
			out.Updated++
		}
		batch = batch[:0]
		return nil
	}

	for {
		rec, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			out.Errors++
			log.Printf("etfimport read row: %v", err)
			continue
		}

		symbol := strings.ToUpper(cell(rec, iSymbol))
		if symbol == "" || strings.EqualFold(symbol, "SYMBOL") || strings.EqualFold(symbol, "TOTAL") {
			out.Skipped++
			continue
		}

		name := cell(rec, iName)
		closePrice, ok := parseFloat(cell(rec, iClose))
		if !ok {
			out.Skipped++
			continue
		}
		high52, ok := parseFloat(cell(rec, i52High))
		if !ok {
			out.Skipped++
			continue
		}
		low52, ok := parseFloat(cell(rec, i52Low))
		if !ok {
			out.Skipped++
			continue
		}

		batch = append(batch, struct {
			symbol string
			name   string
			close  float64
			high   float64
			low    float64
		}{
			symbol: symbol,
			name:   name,
			close:  closePrice,
			high:   high52,
			low:    low52,
		})

		if len(batch) >= batchSize {
			if err := flush(); err != nil {
				return out, err
			}
		}
	}

	if err := flush(); err != nil {
		return out, err
	}

	return out, nil
}
