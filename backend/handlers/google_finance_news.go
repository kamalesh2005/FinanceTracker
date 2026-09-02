package handlers

import (
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

const (
	googleFinanceQuoteBase = "https://www.google.com/finance/quote/"
	googleFinanceMaxBody   = 3 << 20
)

var (
	googleFinanceHTTPClient = &http.Client{Timeout: 20 * time.Second}
	googleNewsHeadlineRe    = regexp.MustCompile(`(?i)<a\s+href="(https?://[^"]+)"[^>]*>\s*<div class="[^"]*TQWIEd[^"]*">([^<]+)</div>`)
)

func googleFinanceTicker(symbol string) string {
	s := strings.ToUpper(strings.TrimSpace(resolveYahooSymbol(symbol)))
	for _, suf := range []string{".NS", ".BO", ".NSE", ".BSE", ".BOM"} {
		s = strings.TrimSuffix(s, suf)
	}
	return strings.TrimSpace(s)
}

func googleFinanceQuoteURL(symbol, exchange string) string {
	ticker := googleFinanceTicker(symbol)
	return googleFinanceQuoteBase + url.PathEscape(ticker) + ":" + exchange
}

func fetchGoogleFinanceLatestNews(symbol string) (title, link string, err error) {
	ticker := googleFinanceTicker(symbol)
	if ticker == "" {
		return "", "", fmt.Errorf("empty google finance ticker")
	}

	var lastErr error
	for _, exchange := range []string{"NSE", "BOM"} {
		t, l, e := fetchGoogleFinanceNewsFromURL(googleFinanceQuoteURL(ticker, exchange))
		if e != nil {
			lastErr = e
			continue
		}
		if t != "" {
			return t, l, nil
		}
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("no Google Finance news for %s", ticker)
	}
	return "", "", lastErr
}

func fetchGoogleFinanceNewsFromURL(pageURL string) (title, link string, err error) {
	req, err := http.NewRequest(http.MethodGet, pageURL, nil)
	if err != nil {
		return "", "", err
	}
	req.Header.Set("User-Agent", yahooUserAgent)
	req.Header.Set("Accept", "text/html,application/xhtml+xml")
	req.Header.Set("Accept-Language", "en-IN,en;q=0.9")

	resp, err := googleFinanceHTTPClient.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", "", fmt.Errorf("google finance HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, googleFinanceMaxBody+1))
	if err != nil {
		return "", "", err
	}
	if len(body) > googleFinanceMaxBody {
		return "", "", fmt.Errorf("google finance response too large")
	}
	return parseGoogleFinanceLatestNews(string(body))
}

func parseGoogleFinanceLatestNews(pageHTML string) (title, link string, err error) {
	for _, m := range googleNewsHeadlineRe.FindAllStringSubmatch(pageHTML, 8) {
		if len(m) < 3 {
			continue
		}
		link = strings.TrimSpace(html.UnescapeString(m[1]))
		title = strings.TrimSpace(html.UnescapeString(m[2]))
		if title == "" {
			continue
		}
		if u, perr := url.Parse(link); perr != nil || (u.Scheme != "http" && u.Scheme != "https") {
			continue
		}
		host := strings.ToLower(hostOf(link))
		if strings.Contains(host, "google.com") {
			continue
		}
		return title, link, nil
	}
	return "", "", fmt.Errorf("no Google Finance news items")
}

func hostOf(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	return u.Host
}
