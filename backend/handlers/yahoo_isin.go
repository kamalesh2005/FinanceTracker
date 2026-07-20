package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"sync"
)

var (
	isinResolveMu    sync.RWMutex
	isinResolveCache = map[string]string{} // ISIN → NSE base symbol (validated)
)

type yahooSearchQuote struct {
	Symbol    string
	Exchange  string
	QuoteType string
	ShortName string
}

// resolveNSESymbolFromISIN resolves an ISIN to an NSE ticker (no .NS suffix) via NSE CSV then Yahoo search.
func resolveNSESymbolFromISIN(isin string) (nseSymbol string, via string, err error) {
	isin = normalizeISIN(isin)
	if isin == "" {
		return "", "", fmt.Errorf("invalid ISIN")
	}

	isinResolveMu.RLock()
	if cached, ok := isinResolveCache[isin]; ok && cached != "" {
		isinResolveMu.RUnlock()
		return cached, "cache", nil
	}
	isinResolveMu.RUnlock()

	if sym, ok := lookupNSESymbolByISIN(isin); ok && sym != "" {
		if price, err := fetchYahooFinancePriceForTicker(sym); err == nil && price > 0 {
			cacheISINResolve(isin, sym)
			return sym, "NSE CSV", nil
		}
	}

	sym, err := yahooSearchNSESymbolByISIN(isin)
	if err != nil {
		return "", "", err
	}
	if price, err := fetchYahooFinancePriceForTicker(sym); err != nil || price <= 0 {
		return "", "", fmt.Errorf("yahoo validation failed for %s", sym)
	}
	cacheISINResolve(isin, sym)
	return sym, "Yahoo search", nil
}

func cacheISINResolve(isin, nseSymbol string) {
	isinResolveMu.Lock()
	isinResolveCache[isin] = nseSymbol
	isinResolveMu.Unlock()
}

func yahooFinanceSearchQuotes(query string) ([]yahooSearchQuote, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return nil, fmt.Errorf("empty search query")
	}

	u, err := url.Parse("https://query1.finance.yahoo.com/v1/finance/search")
	if err != nil {
		return nil, err
	}
	q := u.Query()
	q.Set("q", query)
	q.Set("quotesCount", "10")
	q.Set("newsCount", "0")
	q.Set("listsCount", "0")
	u.RawQuery = q.Encode()

	req, err := http.NewRequest("GET", u.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", yahooUserAgent)

	resp, err := yahooHTTPClient().Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("yahoo search HTTP %d", resp.StatusCode)
	}

	var payload struct {
		Quotes []struct {
			Symbol    string `json:"symbol"`
			Exchange  string `json:"exchange"`
			QuoteType string `json:"quoteType"`
			ShortName string `json:"shortname"`
		} `json:"quotes"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, err
	}

	out := make([]yahooSearchQuote, 0, len(payload.Quotes))
	for _, q := range payload.Quotes {
		sym := strings.TrimSpace(q.Symbol)
		if sym == "" {
			continue
		}
		out = append(out, yahooSearchQuote{
			Symbol:    sym,
			Exchange:  q.Exchange,
			QuoteType: q.QuoteType,
			ShortName: q.ShortName,
		})
	}
	return out, nil
}

func yahooSearchNSESymbolByISIN(isin string) (string, error) {
	quotes, err := yahooFinanceSearchQuotes(isin)
	if err != nil {
		return "", err
	}

	bestScore := -1
	bestSymbol := ""
	for _, q := range quotes {
		score := scoreYahooQuoteForIndia(q.Symbol, q.Exchange, q.QuoteType)
		if score > bestScore {
			bestScore = score
			bestSymbol = q.Symbol
		}
	}
	if bestSymbol == "" || bestScore < 0 {
		return "", fmt.Errorf("no yahoo quote for ISIN %s", isin)
	}

	return stripYahooExchangeSuffix(bestSymbol), nil
}

// yahooSearchUniqueNSESymbolByName searches Yahoo by company name and accepts only
// when exactly one India-relevant quote remains after filtering.
func yahooSearchUniqueNSESymbolByName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", fmt.Errorf("empty name")
	}

	quotes, err := yahooFinanceSearchQuotes(name)
	if err != nil {
		return "", err
	}

	var indiaQuotes []yahooSearchQuote
	for _, q := range quotes {
		if scoreYahooQuoteForIndia(q.Symbol, q.Exchange, q.QuoteType) > 0 {
			indiaQuotes = append(indiaQuotes, q)
		}
	}
	if len(indiaQuotes) == 0 {
		return "", fmt.Errorf("no India yahoo quote for name %q", name)
	}
	if len(indiaQuotes) != 1 {
		return "", fmt.Errorf("ambiguous yahoo name search for %q: %d India quotes", name, len(indiaQuotes))
	}

	sym := stripYahooExchangeSuffix(indiaQuotes[0].Symbol)
	if price, err := fetchYahooFinancePriceForTicker(sym); err != nil || price <= 0 {
		return "", fmt.Errorf("yahoo validation failed for %s", sym)
	}
	return sym, nil
}

func scoreYahooQuoteForIndia(symbol, exchange, quoteType string) int {
	symbol = strings.ToUpper(symbol)
	exchange = strings.ToUpper(exchange)
	quoteType = strings.ToUpper(quoteType)

	score := 0
	if strings.HasSuffix(symbol, ".NS") {
		score += 100
	} else if strings.HasSuffix(symbol, ".BO") {
		score += 40
	}
	if strings.Contains(exchange, "NSE") || exchange == "NSI" {
		score += 50
	}
	switch quoteType {
	case "EQUITY":
		score += 30
	case "ETF":
		score += 20
	case "MUTUALFUND":
		score -= 50
	}
	return score
}

func stripYahooExchangeSuffix(symbol string) string {
	symbol = strings.TrimSpace(symbol)
	if i := strings.LastIndex(symbol, "."); i > 0 {
		suffix := strings.ToUpper(symbol[i+1:])
		if suffix == "NS" || suffix == "BO" {
			return symbol[:i]
		}
	}
	return symbol
}
