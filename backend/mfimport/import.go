package mfimport

import (
	"bytes"
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"financetracker/models"

	"github.com/xuri/excelize/v2"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"gorm.io/gorm/logger"
)

// Result is the summary of a Global_MutualFunds upsert.
type Result struct {
	Kind    string `json:"kind"` // "catalog" | "nav"
	Created int    `json:"created"`
	Updated int    `json:"updated"`
	Skipped int    `json:"skipped"`
	Errors  int    `json:"errors"`
}

func parseFloat(raw string) float64 {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return 0
	}
	raw = strings.ReplaceAll(raw, ",", "")
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

func hasSchemeName(header []string) bool {
	return colIndex(header, "Scheme Name") >= 0
}

func hasNAV(header []string) bool {
	return colIndex(header, "NAV") >= 0
}

// ImportBytes auto-detects catalog vs NAV format from headers and upserts by ISIN.
func ImportBytes(db *gorm.DB, data []byte, filename string) (Result, error) {
	ext := strings.ToLower(filepath.Ext(filename))
	if ext == ".xlsx" || ext == ".xlsm" {
		rows, err := readXLSXRows(data)
		if err != nil {
			return Result{}, err
		}
		if len(rows) == 0 {
			return Result{}, fmt.Errorf("empty spreadsheet")
		}
		header := rows[0]
		if hasSchemeName(header) {
			return importCatalogRows(db, rows)
		}
		if hasNAV(header) {
			return importNAVRows(db, rows)
		}
		return Result{}, fmt.Errorf("unrecognized xlsx columns: %v", header)
	}

	reader := csv.NewReader(bytes.NewReader(data))
	reader.TrimLeadingSpace = true
	reader.FieldsPerRecord = -1
	header, err := reader.Read()
	if err != nil {
		return Result{}, fmt.Errorf("read header: %w", err)
	}
	rows := [][]string{header}
	for {
		rec, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return Result{}, fmt.Errorf("read csv row: %w", err)
		}
		rows = append(rows, rec)
	}
	if hasSchemeName(header) {
		return importCatalogRows(db, rows)
	}
	if hasNAV(header) {
		return importNAVRows(db, rows)
	}
	return Result{}, fmt.Errorf("unrecognized csv columns: %v", header)
}

func readXLSXRows(data []byte) ([][]string, error) {
	f, err := excelize.OpenReader(bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("open xlsx: %w", err)
	}
	defer f.Close()

	sheets := f.GetSheetList()
	if len(sheets) == 0 {
		return nil, fmt.Errorf("xlsx has no sheets")
	}
	raw, err := f.GetRows(sheets[0])
	if err != nil {
		return nil, fmt.Errorf("read xlsx rows: %w", err)
	}
	return raw, nil
}

func silentDB(db *gorm.DB) *gorm.DB {
	return db.Session(&gorm.Session{Logger: logger.Default.LogMode(logger.Silent)})
}

func importCatalogRows(db *gorm.DB, rows [][]string) (Result, error) {
	out := Result{Kind: "catalog"}
	if len(rows) == 0 {
		return out, fmt.Errorf("empty catalog")
	}
	header := rows[0]
	iISIN := colIndex(header, "ISIN")
	iSymbol := colIndex(header, "Symbol")
	iName := colIndex(header, "Scheme Name")
	iQty := colIndex(header, "Acceptable Quantity")
	iHaircut := colIndex(header, "Applicable Haircut")

	if iISIN < 0 || iName < 0 {
		return out, fmt.Errorf("catalog missing required columns (ISIN, Scheme Name); got %v", header)
	}

	existingISINs := map[string]struct{}{}
	{
		var isins []string
		if err := silentDB(db).Model(&models.GlobalMutualFund{}).Pluck("isin", &isins).Error; err != nil {
			return out, fmt.Errorf("load existing isins: %w", err)
		}
		for _, isin := range isins {
			existingISINs[strings.ToUpper(strings.TrimSpace(isin))] = struct{}{}
		}
	}

	const batchSize = 500
	batch := make([]models.GlobalMutualFund, 0, batchSize)
	flush := func() {
		if len(batch) == 0 {
			return
		}
		created, updated := 0, 0
		for _, row := range batch {
			if _, ok := existingISINs[row.ISIN]; ok {
				updated++
			} else {
				created++
			}
		}
		err := silentDB(db).Clauses(clause.OnConflict{
			Columns: []clause.Column{{Name: "isin"}},
			DoUpdates: clause.AssignmentColumns([]string{
				"symbol", "scheme_name", "acceptable_quantity", "applicable_haircut", "updated_at",
			}),
		}).CreateInBatches(batch, batchSize).Error
		if err != nil {
			out.Errors += len(batch)
			log.Printf("mfimport catalog batch upsert: %v", err)
		} else {
			out.Created += created
			out.Updated += updated
			for _, row := range batch {
				existingISINs[row.ISIN] = struct{}{}
			}
		}
		batch = batch[:0]
	}

	seen := map[string]struct{}{}
	for _, rec := range rows[1:] {
		isin := strings.ToUpper(cell(rec, iISIN))
		if isin == "" {
			out.Skipped++
			continue
		}
		name := cell(rec, iName)
		if name == "" {
			out.Skipped++
			continue
		}
		if _, dup := seen[isin]; dup {
			out.Skipped++
			continue
		}
		seen[isin] = struct{}{}

		batch = append(batch, models.GlobalMutualFund{
			ISIN:               isin,
			Symbol:             cell(rec, iSymbol),
			SchemeName:         name,
			AcceptableQuantity: parseFloat(cell(rec, iQty)),
			ApplicableHaircut:  cell(rec, iHaircut),
		})
		if len(batch) >= batchSize {
			flush()
		}
	}
	flush()
	return out, nil
}

func importNAVRows(db *gorm.DB, rows [][]string) (Result, error) {
	out := Result{Kind: "nav"}
	if len(rows) == 0 {
		return out, fmt.Errorf("empty nav file")
	}
	header := rows[0]
	iISIN := colIndex(header, "ISIN")
	iSymbol := colIndex(header, "SYMBOL", "Symbol")
	iSeries := colIndex(header, "SERIES", "Series")
	iType := colIndex(header, "TYPE", "Type")
	iHaircut := colIndex(header, "HAIRCUT", "Haircut")
	iNAV := colIndex(header, "NAV")

	if iISIN < 0 || iNAV < 0 {
		return out, fmt.Errorf("nav file missing required columns (ISIN, NAV); got %v", header)
	}

	now := time.Now()
	sdb := silentDB(db)
	for _, rec := range rows[1:] {
		isin := strings.ToUpper(cell(rec, iISIN))
		if isin == "" {
			out.Skipped++
			continue
		}
		nav := parseFloat(cell(rec, iNAV))
		if nav <= 0 {
			out.Skipped++
			continue
		}

		updates := map[string]interface{}{
			"current_nav":   nav,
			"last_nav_date": now,
		}
		if sym := cell(rec, iSymbol); sym != "" {
			updates["symbol"] = sym
		}
		if series := cell(rec, iSeries); series != "" {
			updates["series"] = series
		}
		if typ := cell(rec, iType); typ != "" {
			updates["type"] = typ
		}
		if iHaircut >= 0 {
			if h := cell(rec, iHaircut); h != "" {
				updates["haircut"] = parseFloat(h)
			}
		}

		res := sdb.Model(&models.GlobalMutualFund{}).Where("UPPER(isin) = ?", isin).Updates(updates)
		if res.Error != nil {
			out.Errors++
			log.Printf("mfimport nav update %s: %v", isin, res.Error)
			continue
		}
		if res.RowsAffected == 0 {
			out.Skipped++
			continue
		}
		out.Updated++
	}
	return out, nil
}
