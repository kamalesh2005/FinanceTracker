package dailyclose

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"time"
)

// DayBar is one trading day's OHL (we use high/low/close).
type DayBar struct {
	Date  time.Time
	Close float64
	High  float64
	Low   float64
}

func chartURL(ticker, suffix, query string) string {
	return fmt.Sprintf(
		"https://query1.finance.yahoo.com/v8/finance/chart/%s%s?%s",
		url.PathEscape(ticker),
		suffix,
		query,
	)
}

// FetchYearBars downloads ~1y of daily bars for ticker (tries NSE/BSE suffixes).
func FetchYearBars(ticker string, suffixes []string) ([]DayBar, error) {
	if len(suffixes) == 0 {
		suffixes = []string{".NS", ".BO", ""}
	}
	client := &http.Client{Timeout: 15 * time.Second}

	for _, suffix := range suffixes {
		reqURL := chartURL(ticker, suffix, "interval=1d&range=1y")
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
	return nil, fmt.Errorf("yahoo chart data not found for %s", ticker)
}

func asFloat(vals []interface{}, i int) float64 {
	if i < 0 || i >= len(vals) || vals[i] == nil {
		return 0
	}
	f, ok := vals[i].(float64)
	if !ok || f <= 0 {
		return 0
	}
	return f
}

func sixthHighest(highs []float64) float64 {
	if len(highs) < 6 {
		return 0
	}
	cp := append([]float64(nil), highs...)
	sort.Sort(sort.Reverse(sort.Float64Slice(cp)))
	return cp[5]
}

func sixthLowest(lows []float64) float64 {
	if len(lows) < 6 {
		return 0
	}
	cp := append([]float64(nil), lows...)
	sort.Float64s(cp)
	return cp[5]
}
