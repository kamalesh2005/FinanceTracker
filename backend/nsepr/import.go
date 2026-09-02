package nsepr

import (
	"archive/zip"
	"bytes"
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"net/http"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"financetracker/dailyclose"
	"financetracker/models"

	"gorm.io/gorm"
)

const (
	// NSE archives use PR{DDMMYY}.zip (not YYMMDD). Example: 20 Aug 2026 → PR200826.zip
	nsePRZipURLFmt  = "https://nsearchives.nseindia.com/archives/equities/bhavcopy/pr/PR%s.zip"
	nseUserAgent    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
	maxLookbackDays = 5
)

// Modern PR zip members use prDDMMYYYY.csv; older archives use prDDMMYY.csv.
var (
	prCSVName8 = regexp.MustCompile(`(?i)^pr(\d{2})(\d{2})(\d{4})\.csv$`)
	prCSVName6 = regexp.MustCompile(`(?i)^pr(\d{2})(\d{2})(\d{2})\.csv$`)
)

// Result summarizes a PR CSV import into existing Global_Stocks + daily closes.
type Result struct {
	Updated   int       `json:"updated"`
	Skipped   int       `json:"skipped"`
	Unmatched int       `json:"unmatched"`
	Errors    int       `json:"errors"`
	TradeDate time.Time `json:"trade_date"`
	Filename  string    `json:"filename"`
}

func isZipPayload(data []byte) bool {
	return len(data) >= 4 && data[0] == 'P' && data[1] == 'K' && (data[2] == 3 || data[2] == 5 || data[2] == 7)
}

// DownloadLatestPRZip tries today (IST) then walks back up to maxLookbackDays for a PR zip.
func DownloadLatestPRZip(now time.Time) (zipBytes []byte, usedDate time.Time, err error) {
	ist, locErr := time.LoadLocation("Asia/Kolkata")
	if locErr != nil {
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}
	day := now.In(ist)

	client := &http.Client{Timeout: 90 * time.Second}
	var lastErr error
	for i := 0; i <= maxLookbackDays; i++ {
		d := day.AddDate(0, 0, -i)
		ddMmYy := fmt.Sprintf("%02d%02d%02d", d.Day(), int(d.Month()), d.Year()%100)
		url := fmt.Sprintf(nsePRZipURLFmt, ddMmYy)

		data, status, getErr := httpGet(client, url)
		if getErr != nil {
			lastErr = getErr
			log.Printf("nsepr: download %s: %v", url, getErr)
			continue
		}
		if status == http.StatusNotFound {
			lastErr = fmt.Errorf("PR zip not found for %s (HTTP 404)", ddMmYy)
			log.Printf("nsepr: %v", lastErr)
			continue
		}
		if status != http.StatusOK {
			lastErr = fmt.Errorf("PR zip %s: HTTP %d", ddMmYy, status)
			log.Printf("nsepr: %v", lastErr)
			continue
		}
		if len(data) == 0 {
			lastErr = fmt.Errorf("PR zip %s: empty body", ddMmYy)
			continue
		}
		// NSE sometimes returns an HTML 404 page with HTTP 200.
		if !isZipPayload(data) {
			lastErr = fmt.Errorf("PR zip %s: not a zip (got %d bytes, likely missing for that date)", ddMmYy, len(data))
			log.Printf("nsepr: %v", lastErr)
			continue
		}
		log.Printf("nsepr: downloaded PR%s.zip (%d bytes) for %s", ddMmYy, len(data), d.Format("2006-01-02"))
		return data, d, nil
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("no PR zip found in last %d days", maxLookbackDays+1)
	}
	return nil, time.Time{}, lastErr
}

func httpGet(client *http.Client, url string) ([]byte, int, error) {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("User-Agent", nseUserAgent)
	req.Header.Set("Accept", "*/*")
	req.Header.Set("Referer", "https://www.nseindia.com/")

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

// ExtractPRCSV finds prDDMMYYYY.csv (or legacy prDDMMYY.csv) inside a PR zip.
func ExtractPRCSV(zipBytes []byte) (csvBytes []byte, filename string, err error) {
	if !isZipPayload(zipBytes) {
		return nil, "", fmt.Errorf("open zip: payload is not a zip archive")
	}
	zr, err := zip.NewReader(bytes.NewReader(zipBytes), int64(len(zipBytes)))
	if err != nil {
		return nil, "", fmt.Errorf("open zip: %w", err)
	}

	var legacyName string
	var legacyFile *zip.File
	for _, f := range zr.File {
		base := filepath.Base(f.Name)
		if prCSVName8.MatchString(base) {
			rc, openErr := f.Open()
			if openErr != nil {
				return nil, "", fmt.Errorf("open %s: %w", base, openErr)
			}
			data, readErr := io.ReadAll(rc)
			_ = rc.Close()
			if readErr != nil {
				return nil, "", fmt.Errorf("read %s: %w", base, readErr)
			}
			return data, base, nil
		}
		if legacyFile == nil && prCSVName6.MatchString(base) {
			legacyName = base
			legacyFile = f
		}
	}
	if legacyFile != nil {
		rc, openErr := legacyFile.Open()
		if openErr != nil {
			return nil, "", fmt.Errorf("open %s: %w", legacyName, openErr)
		}
		data, readErr := io.ReadAll(rc)
		_ = rc.Close()
		if readErr != nil {
			return nil, "", fmt.Errorf("read %s: %w", legacyName, readErr)
		}
		return data, legacyName, nil
	}
	return nil, "", fmt.Errorf("zip has no prDDMMYYYY.csv / prDDMMYY.csv member")
}

// ParseTradeDateFromFilename extracts the trade date from prDDMMYYYY.csv or prDDMMYY.csv.
func ParseTradeDateFromFilename(filename string) (time.Time, error) {
	base := filepath.Base(filename)
	if m := prCSVName8.FindStringSubmatch(base); m != nil {
		dd, _ := strconv.Atoi(m[1])
		mm, _ := strconv.Atoi(m[2])
		yyyy, _ := strconv.Atoi(m[3])
		t := time.Date(yyyy, time.Month(mm), dd, 0, 0, 0, 0, time.UTC)
		if t.Day() != dd || int(t.Month()) != mm || t.Year() != yyyy {
			return time.Time{}, fmt.Errorf("invalid date in filename %q", base)
		}
		return t, nil
	}
	if m := prCSVName6.FindStringSubmatch(base); m != nil {
		dd, _ := strconv.Atoi(m[1])
		mm, _ := strconv.Atoi(m[2])
		yy, _ := strconv.Atoi(m[3])
		yyyy := 2000 + yy
		if yy >= 70 {
			yyyy = 1900 + yy
		}
		t := time.Date(yyyy, time.Month(mm), dd, 0, 0, 0, 0, time.UTC)
		if t.Day() != dd || int(t.Month()) != mm || t.Year() != yyyy {
			return time.Time{}, fmt.Errorf("invalid date in filename %q", base)
		}
		return t, nil
	}
	return time.Time{}, fmt.Errorf("filename must be prDDMMYYYY.csv or prDDMMYY.csv (got %q)", base)
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

func normalizeName(s string) string {
	s = strings.ToUpper(strings.TrimSpace(s))
	s = strings.ReplaceAll(s, "&", " AND ")
	replacer := strings.NewReplacer(
		".", " ",
		",", " ",
		"'", " ",
		"-", " ",
		"(", " ",
		")", " ",
	)
	s = replacer.Replace(s)
	for _, w := range []string{" LIMITED", " LTD", " LI"} {
		for strings.Contains(s, w) {
			s = strings.ReplaceAll(s, w, " ")
		}
	}
	fields := strings.Fields(s)
	return strings.Join(fields, " ")
}

// ImportPRCSV updates existing Global_Stocks (close + 52w high/low) and upserts daily closes.
// It never creates new catalog rows.
func ImportPRCSV(db *gorm.DB, r io.Reader, filename string) (Result, error) {
	var out Result
	out.Filename = filepath.Base(filename)

	tradeDate, err := ParseTradeDateFromFilename(filename)
	if err != nil {
		return out, err
	}
	out.TradeDate = tradeDate

	reader := csv.NewReader(r)
	reader.TrimLeadingSpace = true
	reader.FieldsPerRecord = -1
	reader.LazyQuotes = true

	header, err := reader.Read()
	if err != nil {
		return out, fmt.Errorf("read header: %w", err)
	}

	iSymbol := colIndex(header, "SYMBOL", "Symbol")
	iName := colIndex(header, "SECURITY", "Security", "SECURITY NAME", "Security Name", "COMPANY NAME", "Company Name")
	iSeries := colIndex(header, "SERIES", "Series")
	iMkt := colIndex(header, "MKT", "Mkt")
	iClose := colIndex(header,
		"CLOSE_PRICE", "CLOSE PRICE", "Close Price", "CLOSE", "Close",
		"CLS_PR", "CLOSE_PR",
	)
	i52High := colIndex(header,
		"HI_52_WK", "52 WEEK HIGH", "52 Week High", "HIGH_52", "52W HIGH",
	)
	i52Low := colIndex(header,
		"LO_52_WK", "52 WEEK LOW", "52 Week Low", "LOW_52", "52W LOW",
	)

	if iClose < 0 || (iSymbol < 0 && iName < 0) {
		return out, fmt.Errorf(
			"pr csv missing required columns (need CLOSE and SYMBOL or SECURITY); got %v",
			header,
		)
	}

	var stocks []models.Stock
	if err := db.Select("id", "symbol", "name").Find(&stocks).Error; err != nil {
		return out, err
	}
	bySymbol := make(map[string]uint, len(stocks))
	byExactName := make(map[string]uint, len(stocks))
	byNormName := make(map[string]uint, len(stocks))
	for _, s := range stocks {
		sym := strings.ToUpper(strings.TrimSpace(s.Symbol))
		if sym != "" {
			bySymbol[sym] = s.ID
		}
		name := strings.TrimSpace(s.Name)
		if name == "" {
			continue
		}
		byExactName[strings.ToUpper(name)] = s.ID
		n := normalizeName(name)
		if n != "" {
			byNormName[n] = s.ID
		}
	}

	now := time.Now().UTC()

	// Prefer EQ series when duplicate symbols appear.
	type pending struct {
		stockID uint
		symbol  string
		close   float64
		high52  float64
		low52   float64
		series  string
	}
	best := map[uint]pending{}

	for {
		rec, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			out.Errors++
			log.Printf("nsepr read row: %v", err)
			continue
		}

		symbol := strings.ToUpper(cell(rec, iSymbol))
		if symbol == "SYMBOL" || symbol == "TOTAL" || symbol == "LISTED" || symbol == "PERMITTED" {
			out.Skipped++
			continue
		}
		// MKT=Y rows are index quotes in pr*.csv; skip them.
		if iMkt >= 0 && strings.EqualFold(cell(rec, iMkt), "Y") {
			out.Skipped++
			continue
		}
		name := cell(rec, iName)
		series := strings.ToUpper(cell(rec, iSeries))

		closePrice, ok := parseFloat(cell(rec, iClose))
		if !ok {
			out.Skipped++
			continue
		}
		high52, _ := parseFloat(cell(rec, i52High))
		low52, _ := parseFloat(cell(rec, i52Low))

		var stockID uint
		matched := false
		if symbol != "" {
			if id, ok := bySymbol[symbol]; ok {
				stockID = id
				matched = true
			}
		}
		if !matched && name != "" {
			if id, ok := byExactName[strings.ToUpper(name)]; ok {
				stockID = id
				matched = true
			} else if id, ok := byNormName[normalizeName(name)]; ok {
				stockID = id
				matched = true
			}
		}
		if !matched {
			out.Unmatched++
			continue
		}

		symOut := symbol
		if symOut == "" {
			// Resolve symbol from catalog id.
			for s, id := range bySymbol {
				if id == stockID {
					symOut = s
					break
				}
			}
		}
		if symOut == "" {
			out.Skipped++
			continue
		}

		cand := pending{
			stockID: stockID,
			symbol:  symOut,
			close:   closePrice,
			high52:  high52,
			low52:   low52,
			series:  series,
		}
		if prev, exists := best[stockID]; exists {
			// Prefer EQ over other series.
			if prev.series == "EQ" && series != "EQ" {
				continue
			}
			if prev.series != "EQ" && series == "EQ" {
				best[stockID] = cand
				continue
			}
			// Otherwise keep first.
			continue
		}
		best[stockID] = cand
	}

	for _, row := range best {
		updates := map[string]interface{}{
			"current_price":           row.close,
			"last_price_fetched_date": now,
		}
		if row.high52 > 0 {
			updates["sixth_highest_price"] = row.high52
		}
		if row.low52 > 0 {
			updates["sixth_lowest_price"] = row.low52
		}
		if err := db.Model(&models.Stock{}).Where("id = ?", row.stockID).Updates(updates).Error; err != nil {
			out.Errors++
			log.Printf("nsepr update stock %s: %v", row.symbol, err)
			continue
		}
		if _, err := dailyclose.UpsertClose(db, row.symbol, tradeDate, row.close); err != nil {
			out.Errors++
			log.Printf("nsepr upsert close %s: %v", row.symbol, err)
			continue
		}
		out.Updated++
	}

	return out, nil
}

// PullAndImport downloads the latest PR zip, extracts pr*.csv, and imports it.
func PullAndImport(db *gorm.DB, now time.Time) (Result, error) {
	zipBytes, _, err := DownloadLatestPRZip(now)
	if err != nil {
		return Result{}, err
	}
	csvBytes, filename, err := ExtractPRCSV(zipBytes)
	if err != nil {
		return Result{}, err
	}
	return ImportPRCSV(db, bytes.NewReader(csvBytes), filename)
}
