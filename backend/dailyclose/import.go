package dailyclose

import (
	"bytes"
	"fmt"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"financetracker/models"

	"github.com/xuri/excelize/v2"
	"gorm.io/gorm"
)

// ImportResult summarizes an Excel closing-price upload.
type ImportResult struct {
	Created   int `json:"created"`
	Updated   int `json:"updated"`
	Skipped   int `json:"skipped"`
	Unmatched int `json:"unmatched"`
	Errors    int `json:"errors"`
}

var glFilenameDate = regexp.MustCompile(`(?i)gl(\d{2})(\d{2})(\d{4})`)

// ParseTradeDateFromFilename extracts DDMMYYYY from names like gl31072026.xlsx.
func ParseTradeDateFromFilename(filename string) (time.Time, error) {
	base := filepath.Base(filename)
	m := glFilenameDate.FindStringSubmatch(base)
	if m == nil {
		return time.Time{}, fmt.Errorf("filename must contain glDDMMYYYY (got %q)", base)
	}
	dd, _ := strconv.Atoi(m[1])
	mm, _ := strconv.Atoi(m[2])
	yyyy, _ := strconv.Atoi(m[3])
	t := time.Date(yyyy, time.Month(mm), dd, 0, 0, 0, 0, time.UTC)
	if t.Day() != dd || int(t.Month()) != mm || t.Year() != yyyy {
		return time.Time{}, fmt.Errorf("invalid date in filename %q", base)
	}
	return t, nil
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

func parsePrice(raw string) (float64, bool) {
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

func cellAt(row []string, i int) string {
	if i < 0 || i >= len(row) {
		return ""
	}
	return strings.TrimSpace(row[i])
}

// ImportClosingPricesXLSX upserts one day's closes from a BSE gain/loss workbook.
// Does not recalculate MAs or sixth-high/low. Updates Global_Stocks.current_price only.
func ImportClosingPricesXLSX(db *gorm.DB, data []byte, filename string) (ImportResult, error) {
	tradeDate, err := ParseTradeDateFromFilename(filename)
	if err != nil {
		return ImportResult{}, err
	}

	f, err := excelize.OpenReader(bytes.NewReader(data))
	if err != nil {
		return ImportResult{}, fmt.Errorf("open xlsx: %w", err)
	}
	defer f.Close()

	sheets := f.GetSheetList()
	if len(sheets) == 0 {
		return ImportResult{}, fmt.Errorf("xlsx has no sheets")
	}
	rows, err := f.GetRows(sheets[0])
	if err != nil {
		return ImportResult{}, fmt.Errorf("read xlsx: %w", err)
	}

	var stocks []models.Stock
	if err := db.Select("id", "symbol", "name").Find(&stocks).Error; err != nil {
		return ImportResult{}, err
	}
	exact := make(map[string]string, len(stocks))
	norm := make(map[string]string, len(stocks))
	for _, s := range stocks {
		name := strings.TrimSpace(s.Name)
		if name == "" {
			continue
		}
		exact[strings.ToUpper(name)] = s.Symbol
		n := normalizeName(name)
		if n != "" {
			if _, exists := norm[n]; !exists {
				norm[n] = s.Symbol
			}
		}
	}

	resolve := func(security string) (string, bool) {
		security = strings.TrimSpace(security)
		if security == "" {
			return "", false
		}
		if sym, ok := exact[strings.ToUpper(security)]; ok {
			return sym, true
		}
		if sym, ok := norm[normalizeName(security)]; ok {
			return sym, true
		}
		return "", false
	}

	out := ImportResult{}
	limit := 3000
	if len(rows) < limit {
		limit = len(rows)
	}
	touched := make(map[string]float64)

	for i := 0; i < limit; i++ {
		row := rows[i]
		gainLoss := cellAt(row, 0)
		if gainLoss == "" {
			out.Skipped++
			continue
		}
		// Skip header
		if strings.EqualFold(gainLoss, "GAIN_LOSS") {
			out.Skipped++
			continue
		}
		security := cellAt(row, 1)
		priceRaw := cellAt(row, 2)
		price, ok := parsePrice(priceRaw)
		if !ok {
			out.Skipped++
			continue
		}
		sym, ok := resolve(security)
		if !ok {
			out.Unmatched++
			continue
		}
		created, err := UpsertClose(db, sym, tradeDate, price)
		if err != nil {
			out.Errors++
			continue
		}
		if created {
			out.Created++
		} else {
			out.Updated++
		}
		touched[strings.ToUpper(sym)] = price
	}

	for sym, price := range touched {
		_ = db.Model(&models.Stock{}).Where("UPPER(symbol) = ?", sym).
			Update("current_price", price).Error
	}
	return out, nil
}
