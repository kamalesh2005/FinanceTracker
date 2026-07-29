package trendlyne

import (
	"os"
	"testing"
)

// Skipped unless TRENDLYNE_LIVE=1 so normal runs never hit the network.
// The ADANIENT case deliberately passes a stale stock id to exercise recovery.
func TestLiveConsensus(t *testing.T) {
	if os.Getenv("TRENDLYNE_LIVE") != "1" {
		t.Skip("set TRENDLYNE_LIVE=1 to run live scrape check")
	}
	cases := []struct {
		symbol string
		url    string
	}{
		{"ABB", "https://trendlyne.com/research-reports/stock/17/ABB/abb-india-ltd/"},
		{"ADANIENT", "https://trendlyne.com/research-reports/stock/1723/ADANIENT/adani-enterprises-ltd/"},
	}
	for _, tc := range cases {
		res, err := FetchConsensus(tc.symbol, tc.url)
		if err != nil {
			t.Logf("%s: ERR %v", tc.symbol, err)
			continue
		}
		t.Logf("%s: target=%.2f upside=%.2f type=%s date=%v url=%s",
			tc.symbol, res.Target, res.Upside, res.Type, res.Date.Format("2006-01-02"), res.URL)
	}
}
