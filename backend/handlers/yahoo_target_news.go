package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"

	"financetracker/models"

	"gorm.io/gorm"
)

// yahooTargetNewsPolicy controls how often consensus target and news are refetched.
// Zero min ages mean always fetch (intraday and held-stock daily crons).
type yahooTargetNewsPolicy struct {
	minConsensusAge time.Duration
	minNewsAge      time.Duration
}

func needsAgeRefresh(last *time.Time, now time.Time, minAge time.Duration) bool {
	if minAge <= 0 {
		return true
	}
	if last == nil {
		return true
	}
	return now.Sub(last.UTC()) >= minAge
}

type yahooTargetEstimate struct {
	TargetMeanPrice   float64
	RecommendationKey string
}

type yahooRawNumber struct {
	Raw float64
}

func (n *yahooRawNumber) UnmarshalJSON(b []byte) error {
	b = bytes.TrimSpace(b)
	if len(b) == 0 || string(b) == "null" {
		return nil
	}
	if b[0] == '{' {
		var wrap struct {
			Raw float64 `json:"raw"`
		}
		if err := json.Unmarshal(b, &wrap); err != nil {
			return err
		}
		n.Raw = wrap.Raw
		return nil
	}
	return json.Unmarshal(b, &n.Raw)
}

func fetchYahooFinanceTargetEstimate(symbol string) (yahooTargetEstimate, error) {
	suffixes := []string{".NS", ".BO", ""}
	resolved := resolveYahooSymbol(symbol)
	var lastErr error

	for _, suffix := range suffixes {
		reqURL := fmt.Sprintf(
			"https://query1.finance.yahoo.com/v10/finance/quoteSummary/%s%s?modules=financialData",
			url.PathEscape(resolved),
			suffix,
		)
		req, err := http.NewRequest("GET", reqURL, nil)
		if err != nil {
			lastErr = err
			continue
		}

		resp, err := yahooDo(req)
		if err != nil {
			lastErr = err
			continue
		}
		if resp.StatusCode != http.StatusOK {
			lastErr = fmt.Errorf("yahoo target HTTP %d", resp.StatusCode)
			resp.Body.Close()
			continue
		}

		var result struct {
			QuoteSummary struct {
				Result []struct {
					FinancialData struct {
						TargetMeanPrice   yahooRawNumber `json:"targetMeanPrice"`
						RecommendationKey string         `json:"recommendationKey"`
					} `json:"financialData"`
				} `json:"result"`
				Error interface{} `json:"error"`
			} `json:"quoteSummary"`
		}
		decodeErr := json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		if decodeErr != nil {
			lastErr = decodeErr
			continue
		}
		if result.QuoteSummary.Error != nil {
			lastErr = fmt.Errorf("yahoo target error: %v", result.QuoteSummary.Error)
			continue
		}
		if len(result.QuoteSummary.Result) == 0 {
			lastErr = fmt.Errorf("yahoo target empty result")
			continue
		}
		fd := result.QuoteSummary.Result[0].FinancialData
		if fd.TargetMeanPrice.Raw > 0 || strings.TrimSpace(fd.RecommendationKey) != "" {
			return yahooTargetEstimate{
				TargetMeanPrice:   fd.TargetMeanPrice.Raw,
				RecommendationKey: strings.TrimSpace(fd.RecommendationKey),
			}, nil
		}
		lastErr = fmt.Errorf("yahoo target missing for %s%s", resolved, suffix)
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("target not found for %s", symbol)
	}
	return yahooTargetEstimate{}, lastErr
}

// persistYahooTargetAndNews stores Yahoo 1Y target and the latest Google Finance headline.
// Failures are logged and skipped so a missing target/news does not block price saves.
func persistYahooTargetAndNews(db *gorm.DB, s *models.Stock, price float64, now time.Time, policy yahooTargetNewsPolicy) {
	if db == nil || s == nil {
		return
	}
	updates := map[string]interface{}{}

	if needsAgeRefresh(s.LastConsensusFetchedDate, now, policy.minConsensusAge) {
		if est, err := fetchYahooFinanceTargetEstimate(s.Symbol); err != nil {
			log.Printf("Yahoo target [%s]: %v", s.Symbol, err)
		} else if est.TargetMeanPrice > 0 || est.RecommendationKey != "" {
			upside := 0.0
			if price > 0 && est.TargetMeanPrice > 0 {
				upside = (est.TargetMeanPrice - price) / price * 100
			}
			updates["consensus_target"] = est.TargetMeanPrice
			updates["consensus_ltp"] = price
			updates["consensus_upside"] = upside
			updates["consensus_type"] = est.RecommendationKey
			updates["consensus_date"] = now
			updates["last_consensus_fetched_date"] = now
			s.ConsensusTarget = est.TargetMeanPrice
			s.ConsensusLTP = price
			s.ConsensusUpside = upside
			s.ConsensusType = est.RecommendationKey
			s.ConsensusDate = &now
			s.LastConsensusFetchedDate = &now
		}
	}

	if needsAgeRefresh(s.LastNewsFetchedDate, now, policy.minNewsAge) {
		if title, link, err := fetchGoogleFinanceLatestNews(s.Symbol); err != nil {
			log.Printf("Google Finance news [%s]: %v", s.Symbol, err)
		} else {
			updates["news_headline"] = title
			updates["news_url"] = link
			updates["last_news_fetched_date"] = now
			s.NewsHeadline = title
			s.NewsURL = link
			s.LastNewsFetchedDate = &now
		}
	}

	if len(updates) == 0 {
		return
	}
	if s.ID == 0 {
		return
	}
	if err := db.Model(s).Updates(updates).Error; err != nil {
		log.Printf("Yahoo target/news [%s]: DB update FAIL: %v", s.Symbol, err)
	}
}
