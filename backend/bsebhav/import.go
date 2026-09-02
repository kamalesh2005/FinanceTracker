package bsebhav

import (
	"bytes"
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"financetracker/models"

	"gorm.io/gorm"
)

const (
	bseBhavURLFmt = "https://www.bseindia.com/download/BhavCopy/Equity/BhavCopy_BSE_CM_0_0_0_%s_F_0000.CSV"
	bseUserAgent  = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
	priceMaxAge   = 12 * time.Hour
)

// Result summarizes a BSE bhav import into Global_Stocks.
type Result struct {
	Created   int       `json:"created"`
	Updated   int       `json:"updated"`
	Skipped   int       `json:"skipped"`
	Errors    int       `json:"errors"`
	TradeDate time.Time `json:"trade_date"`
	Filename  string    `json:"filename"`
}

// DownloadTodayBhavCSV fetches today's IST bhavcopy only (no lookback).
func DownloadTodayBhavCSV(now time.Time) (csvBytes []byte, filename string, tradeDate time.Time, err error) {
	ist, locErr := time.LoadLocation("Asia/Kolkata")
	if locErr != nil {
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}
	day := now.In(ist)
	yyyyMmDd := fmt.Sprintf("%04d%02d%02d", day.Year(), int(day.Month()), day.Day())
	name := fmt.Sprintf("BhavCopy_BSE_CM_0_0_0_%s_F_0000.CSV", yyyyMmDd)
	url := fmt.Sprintf(bseBhavURLFmt, yyyyMmDd)
	tradeDate = time.Date(day.Year(), day.Month(), day.Day(), 0, 0, 0, 0, time.UTC)

	client := &http.Client{Timeout: 90 * time.Second}
	data, status, getErr := httpGet(client, url)
	if getErr != nil {
		return nil, "", time.Time{}, fmt.Errorf("download %s: %w", name, getErr)
	}
	if status == http.StatusNotFound {
		return nil, "", time.Time{}, fmt.Errorf("%s not found (HTTP 404)", name)
	}
	if status != http.StatusOK {
		return nil, "", time.Time{}, fmt.Errorf("%s: HTTP %d", name, status)
	}
	if len(data) == 0 {
		return nil, "", time.Time{}, fmt.Errorf("%s: empty body", name)
	}
	if !looksLikeBhavCSV(data) {
		return nil, "", time.Time{}, fmt.Errorf("%s: not a BSE bhav CSV (got %d bytes)", name, len(data))
	}
	log.Printf("bsebhav: downloaded %s (%d bytes) for %s", name, len(data), day.Format("2006-01-02"))
	return data, name, tradeDate, nil
}

func httpGet(client *http.Client, url string) ([]byte, int, error) {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("User-Agent", bseUserAgent)
	req.Header.Set("Accept", "text/csv,*/*")
	req.Header.Set("Referer", "https://www.bseindia.com/")

	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, err
	}
	return data, resp.StatusCode, nil
}

func looksLikeBhavCSV(data []byte) bool {
	if len(data) == 0 {
		return false
	}
	trim := bytes.TrimSpace(data)
	if len(trim) >= 9 && (bytes.HasPrefix(trim, []byte("<!DOCTYPE")) ||
		bytes.HasPrefix(trim, []byte("<html")) ||
		bytes.HasPrefix(trim, []byte("<HTML"))) {
		return false
	}
	head := string(trim)
	if len(head) > 300 {
		head = head[:300]
	}
	upper := strings.ToUpper(head)
	return strings.Contains(upper, "ISIN") &&
		strings.Contains(upper, "TCKRSYMB") &&
		strings.Contains(upper, "CLSPRIC")
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
	if err != nil || v <= 0 {
		return 0, false
	}
	return v, true
}

func priceFresh(t *time.Time, now time.Time) bool {
	if t == nil {
		return false
	}
	return now.Sub(t.UTC()) < priceMaxAge
}

// ImportCSV upserts Global_Stocks by ISIN using BSE bhav columns.
func ImportCSV(db *gorm.DB, r io.Reader, filename string) (Result, error) {
	var out Result
	out.Filename = filepath.Base(filename)

	reader := csv.NewReader(r)
	reader.TrimLeadingSpace = true
	reader.FieldsPerRecord = -1
	reader.LazyQuotes = true

	header, err := reader.Read()
	if err != nil {
		return out, fmt.Errorf("read header: %w", err)
	}

	iISIN := colIndex(header, "ISIN")
	iSymbol := colIndex(header, "TckrSymb", "TCKRSYMB")
	iName := colIndex(header, "FinInstrmNm", "FININSTRMNM")
	iClose := colIndex(header, "ClsPric", "CLSPRIC")

	if iISIN < 0 || iSymbol < 0 || iName < 0 || iClose < 0 {
		return out, fmt.Errorf(
			"bse bhav missing required columns (ISIN, TckrSymb, FinInstrmNm, ClsPric); got %v",
			header,
		)
	}

	now := time.Now().UTC()

	for {
		rec, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			out.Errors++
			log.Printf("bsebhav read row: %v", err)
			continue
		}

		isin := strings.ToUpper(cell(rec, iISIN))
		if isin == "" || isin == "ISIN" {
			out.Skipped++
			continue
		}
		symbol := strings.ToUpper(cell(rec, iSymbol))
		name := cell(rec, iName)
		closePrice, ok := parseFloat(cell(rec, iClose))
		if !ok || symbol == "" {
			out.Skipped++
			continue
		}

		var byISIN models.Stock
		isinErr := db.Where("UPPER(isin) = ?", isin).First(&byISIN).Error
		if isinErr == nil {
			if priceFresh(byISIN.LastPriceFetchedDate, now) {
				out.Skipped++
				continue
			}
			if err := db.Model(&byISIN).Updates(map[string]interface{}{
				"current_price":           closePrice,
				"last_price_fetched_date": now,
			}).Error; err != nil {
				out.Errors++
				log.Printf("bsebhav update isin %s: %v", isin, err)
				continue
			}
			out.Updated++
			continue
		}
		if isinErr != gorm.ErrRecordNotFound {
			out.Errors++
			log.Printf("bsebhav lookup isin %s: %v", isin, isinErr)
			continue
		}

		// ISIN not found — check symbol collision before create.
		var bySym models.Stock
		symErr := db.Where("UPPER(symbol) = ?", symbol).First(&bySym).Error
		if symErr == nil {
			existingISIN := strings.ToUpper(strings.TrimSpace(bySym.ISIN))
			if existingISIN != "" && existingISIN != isin {
				out.Skipped++
				continue
			}
			updates := map[string]interface{}{}
			if existingISIN == "" {
				updates["isin"] = isin
			}
			if !priceFresh(bySym.LastPriceFetchedDate, now) {
				updates["current_price"] = closePrice
				updates["last_price_fetched_date"] = now
			}
			if len(updates) == 0 {
				out.Skipped++
				continue
			}
			if err := db.Model(&bySym).Updates(updates).Error; err != nil {
				out.Errors++
				log.Printf("bsebhav attach isin to %s: %v", symbol, err)
				continue
			}
			if _, ok := updates["current_price"]; ok {
				out.Updated++
			} else {
				out.Skipped++
			}
			continue
		}
		if symErr != gorm.ErrRecordNotFound {
			out.Errors++
			log.Printf("bsebhav lookup symbol %s: %v", symbol, symErr)
			continue
		}

		stock := models.Stock{
			ISIN:                 isin,
			Symbol:               symbol,
			Name:                 name,
			CurrentPrice:         closePrice,
			LastPriceFetchedDate: &now,
			PullData:             models.PullDataNo,
		}
		if err := db.Create(&stock).Error; err != nil {
			out.Errors++
			log.Printf("bsebhav create %s (%s): %v", symbol, isin, err)
			continue
		}
		out.Created++
	}

	return out, nil
}

// PullAndImport downloads today's BSE bhav and imports it.
func PullAndImport(db *gorm.DB, now time.Time) (Result, error) {
	data, filename, tradeDate, err := DownloadTodayBhavCSV(now)
	if err != nil {
		return Result{}, err
	}
	result, err := ImportCSV(db, bytes.NewReader(data), filename)
	if err != nil {
		return result, err
	}
	result.TradeDate = tradeDate
	return result, nil
}
