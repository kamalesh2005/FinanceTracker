package mfapi

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const baseURL = "https://api.mfapi.in"

// Client talks to api.mfapi.in. Symbol is the AMFI scheme code.
type Client struct {
	HTTP *http.Client
}

func NewClient() *Client {
	return &Client{
		HTTP: &http.Client{Timeout: 45 * time.Second},
	}
}

type navPoint struct {
	Date string `json:"date"`
	NAV  string `json:"nav"`
}

type schemeResponse struct {
	Data   []navPoint `json:"data"`
	Status string     `json:"status"`
}

// LatestNAV returns the most recent NAV for schemeCode.
func (c *Client) LatestNAV(schemeCode string) (nav float64, asOf time.Time, err error) {
	schemeCode = strings.TrimSpace(schemeCode)
	if schemeCode == "" {
		return 0, time.Time{}, fmt.Errorf("empty scheme code")
	}
	body, err := c.get(fmt.Sprintf("%s/mf/%s/latest", baseURL, schemeCode))
	if err != nil {
		return 0, time.Time{}, err
	}
	var resp schemeResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		return 0, time.Time{}, err
	}
	if len(resp.Data) == 0 {
		return 0, time.Time{}, fmt.Errorf("no latest NAV for scheme %s", schemeCode)
	}
	return parsePoint(resp.Data[0])
}

// FiscalYearEndNAVs returns Indian FY-end NAVs for FY labels (inclusive).
// FY Y runs 1 Apr Y through 31 Mar (Y+1); for each label, uses the last NAV
// on or before 31 Mar of calendar year (Y+1). Missing FYs are omitted.
func (c *Client) FiscalYearEndNAVs(schemeCode string, fyLabels []int) (map[int]float64, error) {
	schemeCode = strings.TrimSpace(schemeCode)
	if schemeCode == "" {
		return nil, fmt.Errorf("empty scheme code")
	}
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
	// FY min ends Mar (minFY+1); fetch from Jan of first end year through Mar of last end year.
	startYear := minFY + 1
	endYear := maxFY + 1
	url := fmt.Sprintf("%s/mf/%s?startDate=%04d-01-01&endDate=%04d-03-31",
		baseURL, schemeCode, startYear, endYear)
	body, err := c.get(url)
	if err != nil {
		return nil, err
	}
	var resp schemeResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, err
	}
	return pickFiscalYearEnds(resp.Data, fyLabels), nil
}

// YearEndNAVs is kept as an alias for FiscalYearEndNAVs for call-site clarity during transition.
func (c *Client) YearEndNAVs(schemeCode string, years []int) (map[int]float64, error) {
	return c.FiscalYearEndNAVs(schemeCode, years)
}

func (c *Client) get(url string) ([]byte, error) {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	res, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, fmt.Errorf("mfapi %s: HTTP %d", url, res.StatusCode)
	}
	return body, nil
}

func parsePoint(p navPoint) (float64, time.Time, error) {
	nav, err := strconv.ParseFloat(strings.TrimSpace(p.NAV), 64)
	if err != nil {
		return 0, time.Time{}, fmt.Errorf("parse nav %q: %w", p.NAV, err)
	}
	t, err := time.Parse("02-01-2006", strings.TrimSpace(p.Date))
	if err != nil {
		return 0, time.Time{}, fmt.Errorf("parse date %q: %w", p.Date, err)
	}
	return nav, t, nil
}

// pickFiscalYearEnds maps FY label Y → last NAV on or before 31 Mar (Y+1).
func pickFiscalYearEnds(points []navPoint, fyLabels []int) map[int]float64 {
	// endCalendarYear (Y+1) → FY label Y
	fyByEndYear := map[int]int{}
	for _, y := range fyLabels {
		fyByEndYear[y+1] = y
	}
	type best struct {
		nav  float64
		date time.Time
		ok   bool
	}
	byFY := map[int]*best{}
	for _, y := range fyLabels {
		byFY[y] = &best{}
	}

	for _, p := range points {
		nav, t, err := parsePoint(p)
		if err != nil || nav <= 0 {
			continue
		}
		// Assign to the FY whose end is the next 31 Mar on or after t.
		// Equivalently: if month <= March, end year = t.Year(); else end year = t.Year()+1.
		endYear := t.Year()
		if t.Month() > time.March {
			endYear = t.Year() + 1
		}
		fy, ok := fyByEndYear[endYear]
		if !ok {
			continue
		}
		fyEnd := time.Date(endYear, time.March, 31, 23, 59, 59, 0, time.UTC)
		if t.After(fyEnd) {
			continue
		}
		b := byFY[fy]
		if !b.ok || t.After(b.date) {
			b.nav = nav
			b.date = t
			b.ok = true
		}
	}

	out := make(map[int]float64, len(fyLabels))
	for y, b := range byFY {
		if b.ok {
			out[y] = b.nav
		}
	}
	return out
}
