package dailyclose

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// StockFYLabels are Indian FY labels whose ends we persist (FY20…FY25).
var StockFYLabels = []int{2020, 2021, 2022, 2023, 2024, 2025}

// FetchFiscalYearEndCloses returns last close on/before 31 Mar (Y+1) for each FY label Y.
// Missing FYs are omitted. Uses Yahoo chart period1/period2 covering the FY window.
func FetchFiscalYearEndCloses(ticker string, suffixes []string, fyLabels []int) (map[int]float64, error) {
	if len(fyLabels) == 0 {
		return map[int]float64{}, nil
	}
	minFY, maxFY := fyLabels[0], fyLabels[0]
	for _, y := range fyLabels {
		if y < minFY {
			minFY = y
		}
		if y > maxFY {
			maxFY = y
		}
	}
	// FY min ends Mar (minFY+1); fetch from Jan of first end year through end of last FY.
	start := time.Date(minFY+1, time.January, 1, 0, 0, 0, 0, time.UTC)
	end := time.Date(maxFY+1, time.March, 31, 23, 59, 59, 0, time.UTC)
	bars, err := FetchBarsPeriod(ticker, suffixes, start, end)
	if err != nil {
		return nil, err
	}
	return pickFiscalYearEndsFromBars(bars, fyLabels), nil
}

// FetchBarsPeriod downloads daily bars between start and end (inclusive) via Yahoo.
func FetchBarsPeriod(ticker string, suffixes []string, start, end time.Time) ([]DayBar, error) {
	if len(suffixes) == 0 {
		suffixes = []string{".NS", ".BO", ""}
	}
	client := &http.Client{Timeout: 45 * time.Second}
	query := fmt.Sprintf("interval=1d&period1=%d&period2=%d", start.Unix(), end.Unix())

	for _, suffix := range suffixes {
		reqURL := chartURL(ticker, suffix, query)
		req, err := http.NewRequest("GET", reqURL, nil)
		if err != nil {
			continue
		}
		req.Header.Set("User-Agent", "Mozilla/5.0")

		resp, err := client.Do(req)
		if err != nil || resp.StatusCode != http.StatusOK {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}

		var result struct {
			Chart struct {
				Result []struct {
					Timestamp  []int64 `json:"timestamp"`
					Indicators struct {
						Quote []struct {
							Close []interface{} `json:"close"`
							High  []interface{} `json:"high"`
							Low   []interface{} `json:"low"`
						} `json:"quote"`
					} `json:"indicators"`
				} `json:"result"`
				Error interface{} `json:"error"`
			} `json:"chart"`
		}
		err = json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		if err != nil {
			continue
		}
		if result.Chart.Error != nil || len(result.Chart.Result) == 0 {
			continue
		}
		cr := result.Chart.Result[0]
		if len(cr.Indicators.Quote) == 0 {
			continue
		}
		q := cr.Indicators.Quote[0]
		bars := make([]DayBar, 0, len(cr.Timestamp))
		for i := 0; i < len(cr.Timestamp); i++ {
			c := asFloat(q.Close, i)
			h := asFloat(q.High, i)
			l := asFloat(q.Low, i)
			if c <= 0 {
				continue
			}
			t := time.Unix(cr.Timestamp[i], 0).UTC()
			day := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
			bars = append(bars, DayBar{Date: day, Close: c, High: h, Low: l})
		}
		if len(bars) > 0 {
			return bars, nil
		}
	}
	return nil, fmt.Errorf("yahoo chart period data not found for %s", ticker)
}

// pickFiscalYearEndsFromBars maps FY label Y → last close on or before 31 Mar (Y+1).
func pickFiscalYearEndsFromBars(bars []DayBar, fyLabels []int) map[int]float64 {
	fyByEndYear := map[int]int{}
	for _, y := range fyLabels {
		fyByEndYear[y+1] = y
	}
	type best struct {
		close float64
		date  time.Time
		ok    bool
	}
	byFY := map[int]*best{}
	for _, y := range fyLabels {
		byFY[y] = &best{}
	}

	for _, b := range bars {
		if b.Close <= 0 {
			continue
		}
		endYear := b.Date.Year()
		if b.Date.Month() > time.March {
			endYear = b.Date.Year() + 1
		}
		fy, ok := fyByEndYear[endYear]
		if !ok {
			continue
		}
		fyEnd := time.Date(endYear, time.March, 31, 23, 59, 59, 0, time.UTC)
		if b.Date.After(fyEnd) {
			continue
		}
		cur := byFY[fy]
		if !cur.ok || b.Date.After(cur.date) {
			cur.close = b.Close
			cur.date = b.Date
			cur.ok = true
		}
	}

	out := make(map[int]float64, len(fyLabels))
	for y, cur := range byFY {
		if cur.ok {
			out[y] = cur.close
		}
	}
	return out
}
