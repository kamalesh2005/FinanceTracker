package handlers

import (
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

const nseEquityListURL = "https://nsearchives.nseindia.com/content/equities/EQUITY_L.csv"

var (
	nseISINMu        sync.RWMutex
	nseISINToSymbol  = map[string]string{}
	nseISINLoadedAt  time.Time
	nseISINLoadError error
)

// LoadNSEEquityISINIndex downloads NSE EQUITY_L.csv and builds ISIN → NSE symbol (EQ series preferred).
func LoadNSEEquityISINIndex() error {
	req, err := http.NewRequest("GET", nseEquityListURL, nil)
	if err != nil {
		nseISINLoadError = err
		return err
	}
	req.Header.Set("User-Agent", yahooUserAgent)
	req.Header.Set("Accept", "text/csv,*/*")
	req.Header.Set("Referer", "https://www.nseindia.com/")

	client := &http.Client{Timeout: 45 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		nseISINLoadError = err
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		nseISINLoadError = fmt.Errorf("NSE EQUITY_L.csv: HTTP %d", resp.StatusCode)
		return nseISINLoadError
	}

	next, err := parseNSEEquityCSV(resp.Body)
	if err != nil {
		nseISINLoadError = err
		return err
	}

	nseISINMu.Lock()
	nseISINToSymbol = next
	nseISINLoadedAt = time.Now()
	nseISINLoadError = nil
	nseISINMu.Unlock()

	log.Printf("NSE ISIN index loaded: %d entries", len(next))
	return nil
}

// LoadNSEEquityISINIndexFromFile loads ISIN index from a local EQUITY_L.csv (fallback when download fails).
func LoadNSEEquityISINIndexFromFile(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	next, err := parseNSEEquityCSV(f)
	if err != nil {
		return err
	}

	nseISINMu.Lock()
	nseISINToSymbol = next
	nseISINLoadedAt = time.Now()
	nseISINLoadError = nil
	nseISINMu.Unlock()

	log.Printf("NSE ISIN index loaded from file %s: %d entries", path, len(next))
	return nil
}

func parseNSEEquityCSV(r io.Reader) (map[string]string, error) {
	reader := csv.NewReader(r)
	reader.FieldsPerRecord = -1
	reader.LazyQuotes = true
	reader.TrimLeadingSpace = true

	rows, err := reader.ReadAll()
	if err != nil {
		return nil, err
	}
	if len(rows) < 2 {
		return nil, fmt.Errorf("NSE EQUITY_L.csv: empty file")
	}

	header := rows[0]
	symbolCol, isinCol, seriesCol := -1, -1, -1
	for i, h := range header {
		key := strings.ToUpper(strings.TrimSpace(h))
		switch key {
		case "SYMBOL":
			symbolCol = i
		case "ISIN NUMBER", "ISIN":
			isinCol = i
		case "SERIES":
			seriesCol = i
		}
	}
	if symbolCol < 0 || isinCol < 0 {
		return nil, fmt.Errorf("NSE EQUITY_L.csv: missing SYMBOL or ISIN column")
	}

	// ISIN may map to multiple series; prefer EQ, then keep first seen.
	type pick struct {
		symbol string
		series string
	}
	byISIN := make(map[string]pick)

	for _, row := range rows[1:] {
		if symbolCol >= len(row) || isinCol >= len(row) {
			continue
		}
		symbol := strings.ToUpper(strings.TrimSpace(row[symbolCol]))
		isin := normalizeISIN(row[isinCol])
		if symbol == "" || isin == "" {
			continue
		}
		series := "EQ"
		if seriesCol >= 0 && seriesCol < len(row) {
			series = strings.ToUpper(strings.TrimSpace(row[seriesCol]))
		}

		cur, ok := byISIN[isin]
		if !ok {
			byISIN[isin] = pick{symbol: symbol, series: series}
			continue
		}
		if cur.series != "EQ" && series == "EQ" {
			byISIN[isin] = pick{symbol: symbol, series: series}
		}
	}

	out := make(map[string]string, len(byISIN))
	for isin, p := range byISIN {
		out[isin] = p.symbol
	}
	return out, nil
}

func lookupNSESymbolByISIN(isin string) (string, bool) {
	isin = normalizeISIN(isin)
	if isin == "" {
		return "", false
	}
	nseISINMu.RLock()
	defer nseISINMu.RUnlock()
	sym, ok := nseISINToSymbol[isin]
	return sym, ok
}
