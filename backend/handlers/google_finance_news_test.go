package handlers

import "testing"

func TestGoogleFinanceTicker(t *testing.T) {
	cases := map[string]string{
		"TCS":         "TCS",
		"tcs.NS":      "TCS",
		"M&M":         "M&M",
		"RELIANCE.BO": "RELIANCE",
		"  infy.nse ": "INFY",
	}
	for in, want := range cases {
		if got := googleFinanceTicker(in); got != want {
			t.Fatalf("%q: got %q want %q", in, got, want)
		}
	}
}

func TestGoogleFinanceQuoteURL(t *testing.T) {
	got := googleFinanceQuoteURL("TCS", "NSE")
	want := "https://www.google.com/finance/quote/TCS:NSE"
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}
	got = googleFinanceQuoteURL("M&M", "NSE")
	if got != "https://www.google.com/finance/quote/M&M:NSE" && got != "https://www.google.com/finance/quote/M%26M:NSE" {
		t.Fatalf("unexpected M&M url %q", got)
	}
}

func TestParseGoogleFinanceLatestNews(t *testing.T) {
	html := `
<a href="https://www.google.com/finance/quote/INFY:NSE" target="_blank"><div class="TQWIEd">Skip related quote</div></a>
<a href="https://www.bignewsnetwork.com/news/279239972/tcs-vodafone-business" target="_blank"><div class="TQWIEd">TCS, Vodafone Business join hands to drive AI-led digital transformation in UK</div></a>
<a href="https://www.reuters.com/world/india/indias-tcs" target="_blank"><div class="TQWIEd">India&#39;s TCS flags alleged exposure of some employee data</div></a>
`
	title, link, err := parseGoogleFinanceLatestNews(html)
	if err != nil {
		t.Fatal(err)
	}
	if title != "TCS, Vodafone Business join hands to drive AI-led digital transformation in UK" {
		t.Fatalf("title=%q", title)
	}
	if link != "https://www.bignewsnetwork.com/news/279239972/tcs-vodafone-business" {
		t.Fatalf("link=%q", link)
	}

	title, _, err = parseGoogleFinanceLatestNews(`<div class="TQWIEd">India&#39;s TCS</div>`)
	if err == nil {
		t.Fatalf("expected error, got title %q", title)
	}
}
