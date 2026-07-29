package trendlyne

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/html"
)

const (
	userAgent        = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
	requestTimeout   = 45 * time.Second
	maxResponseBytes = 4 << 20 // 4 MiB
	crawlDelay       = 1100 * time.Millisecond
	equitySitemapURL = "https://trendlyne.com/equity-sitemap.xml"
	consensusLabel   = "Consensus Share Price Target"

	identityMismatchMarker = "page is for"
)

var (
	httpClient = &http.Client{Timeout: requestTimeout}

	reportURLRe = regexp.MustCompile(`(?i)^https?://(?:www\.)?trendlyne\.com/research-reports/stock/(\d+)/([A-Za-z0-9._-]+)/([^/?#]+)/?$`)
	numRe       = regexp.MustCompile(`-?\d+(?:\.\d+)?`)
	// Trendlyne keys pages by numeric id; the slug is cosmetic and a stale id
	// silently serves a different company, so identity comes from the page body.
	canonicalRe  = regexp.MustCompile(`(?i)<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']`)
	equityLinkRe = regexp.MustCompile(`(?i)/equity/[a-z0-9-]+/\d+/([A-Za-z0-9&._-]{1,20})/`)
	nseSymbolRe  = regexp.MustCompile(`(?i)\bNSE\s*:\s*([A-Za-z0-9&._-]{1,20})\b`)
	dateLayouts = []string{
		"2 Jan 2006",
		"02 Jan 2006",
		"2 January 2006",
		"02 January 2006",
	}

	rateMu      sync.Mutex
	lastRequest time.Time
	sitemapCache map[string]string
	sitemapOnce  sync.Once
	sitemapErr   error
)

// ConsensusResult is the first "Consensus Share Price Target" row.
type ConsensusResult struct {
	URL     string
	Symbol  string
	Date    time.Time
	LTP     float64
	Target  float64
	Upside  float64
	Type    string
	HasDate bool
}

// FetchConsensus scrapes consensus data for symbol. If pageURL is empty, discovers it.
func FetchConsensus(symbol, pageURL string) (*ConsensusResult, error) {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if symbol == "" {
		return nil, fmt.Errorf("empty symbol")
	}

	resolved := strings.TrimSpace(pageURL)
	if resolved == "" {
		u, err := DiscoverReportURL(symbol)
		if err != nil {
			return nil, err
		}
		resolved = u
	}

	result, err := fetchAndParse(symbol, resolved)
	// A cached URL can drift to another company when Trendlyne reassigns ids;
	// rediscover once before giving up.
	if err != nil && isIdentityMismatch(err) && strings.TrimSpace(pageURL) != "" {
		rediscovered, discErr := DiscoverReportURL(symbol)
		if discErr == nil && rediscovered != resolved {
			resolved = rediscovered
			result, err = fetchAndParse(symbol, resolved)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("%w (url=%s)", err, resolved)
	}
	result.URL = resolved
	return result, nil
}

func fetchAndParse(symbol, pageURL string) (*ConsensusResult, error) {
	body, err := getBytes(pageURL)
	if err != nil {
		return nil, fmt.Errorf("FETCH_FAIL: %w", err)
	}
	return ParseConsensusHTML(symbol, body)
}

func isIdentityMismatch(err error) bool {
	return err != nil && strings.Contains(err.Error(), identityMismatchMarker)
}

// DiscoverReportURL finds the research-reports URL for a symbol via equity sitemap,
// falling back to a public web search when the sitemap is unavailable.
func DiscoverReportURL(symbol string) (string, error) {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	index, err := loadSitemapIndex()
	if err == nil {
		if u, ok := index[symbol]; ok {
			return u, nil
		}
	}
	if u, searchErr := discoverViaWebSearch(symbol); searchErr == nil && u != "" {
		return u, nil
	}
	if err != nil {
		return "", fmt.Errorf("URL_NOT_FOUND: %w", err)
	}
	return "", fmt.Errorf("URL_NOT_FOUND: no Trendlyne research-reports URL for %s", symbol)
}

func discoverViaWebSearch(symbol string) (string, error) {
	q := url.QueryEscape(fmt.Sprintf(`site:trendlyne.com/research-reports/stock/ "%s"`, symbol))
	searchURL := "https://html.duckduckgo.com/html/?q=" + q
	body, err := getBytes(searchURL)
	if err != nil {
		return "", err
	}
	re := regexp.MustCompile(`(?i)https?://(?:www\.)?trendlyne\.com/research-reports/stock/\d+/` + regexp.QuoteMeta(symbol) + `/[A-Za-z0-9._%-]+/?`)
	m := re.FindString(string(body))
	if m == "" {
		// DuckDuckGo often wraps redirects: uddg=<encoded>
		uddgRe := regexp.MustCompile(`uddg=([^&"]+)`)
		for _, sm := range uddgRe.FindAllStringSubmatch(string(body), -1) {
			decoded, decErr := url.QueryUnescape(sm[1])
			if decErr != nil {
				continue
			}
			if reportURLRe.MatchString(decoded) && strings.Contains(strings.ToUpper(decoded), "/"+symbol+"/") {
				return strings.TrimRight(decoded, "/") + "/", nil
			}
		}
		return "", fmt.Errorf("no search hit")
	}
	return strings.TrimRight(m, "/") + "/", nil
}

func loadSitemapIndex() (map[string]string, error) {
	sitemapOnce.Do(func() {
		sitemapCache = map[string]string{}
		body, err := getBytes(equitySitemapURL)
		if err != nil {
			sitemapErr = err
			return
		}
		locs := extractXMLLocs(string(body))
		var reportLocs []string
		var childSitemaps []string
		for _, loc := range locs {
			if reportURLRe.MatchString(loc) {
				reportLocs = append(reportLocs, loc)
			} else if strings.Contains(loc, "sitemap") && strings.HasSuffix(strings.ToLower(loc), ".xml") {
				childSitemaps = append(childSitemaps, loc)
			}
		}
		for _, child := range childSitemaps {
			childBody, err := getBytes(child)
			if err != nil {
				continue
			}
			for _, loc := range extractXMLLocs(string(childBody)) {
				if reportURLRe.MatchString(loc) {
					reportLocs = append(reportLocs, loc)
				}
			}
		}
		for _, loc := range reportLocs {
			m := reportURLRe.FindStringSubmatch(loc)
			if len(m) < 3 {
				continue
			}
			sym := strings.ToUpper(m[2])
			if _, exists := sitemapCache[sym]; !exists {
				sitemapCache[sym] = strings.TrimRight(loc, "/") + "/"
			}
		}
		if len(sitemapCache) == 0 {
			sitemapErr = fmt.Errorf("equity sitemap contained no research-reports URLs")
		}
	})
	return sitemapCache, sitemapErr
}

func extractXMLLocs(xmlBody string) []string {
	re := regexp.MustCompile(`(?i)<loc>\s*([^<\s]+)\s*</loc>`)
	matches := re.FindAllStringSubmatch(xmlBody, -1)
	out := make([]string, 0, len(matches))
	for _, m := range matches {
		if len(m) > 1 {
			out = append(out, strings.TrimSpace(m[1]))
		}
	}
	return out
}

func getBytes(rawURL string) ([]byte, error) {
	waitCrawlDelay()
	req, err := http.NewRequest(http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
	req.Header.Set("Accept-Language", "en-IN,en;q=0.9")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("http %d for %s", resp.StatusCode, rawURL)
	}
	limited := io.LimitReader(resp.Body, maxResponseBytes+1)
	body, err := io.ReadAll(limited)
	if err != nil {
		return nil, err
	}
	if len(body) > maxResponseBytes {
		return nil, fmt.Errorf("response too large for %s", rawURL)
	}
	return body, nil
}

func waitCrawlDelay() {
	rateMu.Lock()
	defer rateMu.Unlock()
	if !lastRequest.IsZero() {
		elapsed := time.Since(lastRequest)
		if elapsed < crawlDelay {
			time.Sleep(crawlDelay - elapsed)
		}
	}
	lastRequest = time.Now()
}

// ParseConsensusHTML extracts the consensus row from Trendlyne HTML.
// Prefers the "Consensus Share Price Target" row; if absent, uses the first
// data row of the research-reports table.
func ParseConsensusHTML(symbol string, body []byte) (*ConsensusResult, error) {
	doc, err := html.Parse(strings.NewReader(string(body)))
	if err != nil {
		return nil, fmt.Errorf("PARSE_FAIL: html parse: %w", err)
	}

	pageSymbol := extractPageSymbol(body)
	if pageSymbol != "" && !strings.EqualFold(pageSymbol, symbol) {
		return nil, fmt.Errorf("PARSE_FAIL: %s %s, want %s", identityMismatchMarker, pageSymbol, symbol)
	}

	table := findReportsTable(doc)
	if table == nil {
		return nil, fmt.Errorf("PARSE_FAIL: research reports table not found")
	}

	identityVerified := pageSymbol != ""
	var firstData []string
	rows := tableRows(table)
	for _, row := range rows {
		cells := rowCells(row)
		if len(cells) == 0 || isHeaderRow(cells) {
			continue
		}
		joined := strings.Join(cells, " | ")
		if strings.Contains(strings.ToLower(joined), strings.ToLower(consensusLabel)) {
			return parseReportRowCells(symbol, cells, identityVerified)
		}
		if firstData == nil && isDataRow(cells) {
			firstData = cells
		}
	}
	if firstData != nil {
		return parseReportRowCells(symbol, firstData, identityVerified)
	}
	return nil, fmt.Errorf("PARSE_FAIL: no consensus or report data row found")
}

func isHeaderRow(cells []string) bool {
	joined := strings.ToLower(strings.Join(cells, " "))
	hasAuthor := strings.Contains(joined, "author")
	hasTarget := strings.Contains(joined, "target")
	hasUpside := strings.Contains(joined, "upside")
	if !(hasAuthor && hasTarget && hasUpside) {
		return false
	}
	// Header rows have no report date and few/no price numbers.
	for _, cell := range cells {
		if looksLikeDate(cell) {
			return false
		}
	}
	numCount := 0
	for _, cell := range cells {
		if _, ok := parseFloatLoose(cell); ok {
			numCount++
		}
	}
	return numCount < 2
}

func isDataRow(cells []string) bool {
	hasDate := false
	numCount := 0
	for _, cell := range cells {
		if looksLikeDate(cell) {
			hasDate = true
		}
		if _, ok := parseFloatLoose(cell); ok {
			numCount++
		}
	}
	return hasDate || numCount >= 2
}

// extractPageSymbol returns the NSE ticker the page actually describes. The
// canonical link is authoritative; the others are fallbacks for markup drift.
func extractPageSymbol(body []byte) string {
	text := string(body)
	if m := canonicalRe.FindStringSubmatch(text); len(m) > 1 {
		if u := reportURLRe.FindStringSubmatch(strings.TrimSpace(m[1])); len(u) > 2 {
			return strings.ToUpper(u[2])
		}
	}
	if m := equityLinkRe.FindStringSubmatch(text); len(m) > 1 {
		return strings.ToUpper(m[1])
	}
	if m := nseSymbolRe.FindStringSubmatch(text); len(m) > 1 {
		return strings.ToUpper(m[1])
	}
	return ""
}

func findReportsTable(n *html.Node) *html.Node {
	var found *html.Node
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		if found != nil || node == nil {
			return
		}
		if node.Type == html.ElementNode && node.Data == "table" {
			headerText := strings.ToLower(nodeText(node))
			if strings.Contains(headerText, "author") &&
				strings.Contains(headerText, "target") &&
				strings.Contains(headerText, "upside") {
				found = node
				return
			}
		}
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return found
}

func tableRows(table *html.Node) []*html.Node {
	var rows []*html.Node
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		if n.Type == html.ElementNode && n.Data == "tr" {
			rows = append(rows, n)
			return
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(table)
	return rows
}

func rowCells(tr *html.Node) []string {
	var cells []string
	for c := tr.FirstChild; c != nil; c = c.NextSibling {
		if c.Type == html.ElementNode && (c.Data == "td" || c.Data == "th") {
			text := collapseSpace(nodeText(c))
			cells = append(cells, text)
		}
	}
	return cells
}

func parseReportRowCells(symbol string, cells []string, identityVerified bool) (*ConsensusResult, error) {
	dateIdx, stockIdx, ltpIdx, targetIdx, upsideIdx, typeIdx := -1, -1, -1, -1, -1, -1

	for i, cell := range cells {
		if dateIdx < 0 && looksLikeDate(cell) {
			dateIdx = i
		}
		if stockIdx < 0 && strings.EqualFold(strings.TrimSpace(cell), symbol) {
			stockIdx = i
		}
	}

	// Numbers after the date (or from the start when no date): LTP, Target,
	// optional price-at-reco, Upside. Works for both consensus and brokerage rows.
	start := 0
	if dateIdx >= 0 {
		start = dateIdx + 1
	}
	nums := make([]int, 0, 4)
	for i := start; i < len(cells); i++ {
		if _, ok := parseFloatLoose(cells[i]); ok {
			nums = append(nums, i)
		}
		lower := strings.ToLower(strings.TrimSpace(cells[i]))
		if typeIdx < 0 && (lower == "buy" || lower == "sell" || lower == "hold" || lower == "accumulate") {
			typeIdx = i
		}
	}
	if len(nums) >= 2 {
		ltpIdx = nums[0]
		targetIdx = nums[1]
	}
	if len(nums) >= 3 {
		if typeIdx > nums[len(nums)-1] || typeIdx < 0 {
			upsideIdx = nums[len(nums)-1]
			if len(nums) >= 4 {
				upsideIdx = nums[3]
			} else if len(nums) == 3 {
				upsideIdx = nums[2]
			}
		} else {
			for i := len(nums) - 1; i >= 0; i-- {
				if nums[i] < typeIdx {
					upsideIdx = nums[i]
					break
				}
			}
		}
	}

	// The row's stock cell carries a display name ("Adani Enterpris"), not the
	// ticker, so only fall back to matching it when the page gave no identity.
	if !identityVerified && stockIdx < 0 {
		joined := strings.ToUpper(strings.Join(cells, " "))
		if !strings.Contains(joined, strings.ToUpper(symbol)) {
			return nil, fmt.Errorf("PARSE_FAIL: symbol %s not found in report row", symbol)
		}
	}

	if ltpIdx < 0 || targetIdx < 0 {
		return nil, fmt.Errorf("PARSE_FAIL: missing LTP/target in report row: %v", cells)
	}

	ltp, ok := parseFloatLoose(cells[ltpIdx])
	if !ok {
		return nil, fmt.Errorf("PARSE_FAIL: bad LTP %q", cells[ltpIdx])
	}
	target, ok := parseFloatLoose(cells[targetIdx])
	if !ok {
		return nil, fmt.Errorf("PARSE_FAIL: bad target %q", cells[targetIdx])
	}

	var upside float64
	if upsideIdx >= 0 {
		upside, _ = parseFloatLoose(cells[upsideIdx])
	}

	recType := ""
	if typeIdx >= 0 {
		recType = normalizeType(cells[typeIdx])
	} else {
		for _, cell := range cells {
			if t := normalizeType(cell); t != "" {
				recType = t
				break
			}
		}
	}

	result := &ConsensusResult{
		Symbol: strings.ToUpper(symbol),
		LTP:    ltp,
		Target: target,
		Upside: upside,
		Type:   recType,
	}
	if dateIdx >= 0 {
		if d, ok := parseDate(cells[dateIdx]); ok {
			result.Date = d
			result.HasDate = true
		}
	}
	return result, nil
}

func looksLikeDate(s string) bool {
	_, ok := parseDate(s)
	return ok
}

func parseDate(s string) (time.Time, bool) {
	s = collapseSpace(s)
	for _, layout := range dateLayouts {
		if t, err := time.Parse(layout, s); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

func parseFloatLoose(s string) (float64, bool) {
	s = strings.TrimSpace(s)
	if s == "" || s == "-" {
		return 0, false
	}
	m := numRe.FindString(strings.ReplaceAll(s, ",", ""))
	if m == "" {
		return 0, false
	}
	v, err := strconv.ParseFloat(m, 64)
	if err != nil {
		return 0, false
	}
	return v, true
}

func normalizeType(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	switch s {
	case "buy", "sell", "hold", "accumulate":
		return s
	default:
		return ""
	}
}

func nodeText(n *html.Node) string {
	if n == nil {
		return ""
	}
	if n.Type == html.TextNode {
		return n.Data
	}
	var b strings.Builder
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		b.WriteString(nodeText(c))
		b.WriteByte(' ')
	}
	return b.String()
}

func collapseSpace(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

// ResetSitemapCacheForTests clears cached sitemap state (tests only).
func ResetSitemapCacheForTests() {
	sitemapOnce = sync.Once{}
	sitemapCache = nil
	sitemapErr = nil
}

// ValidateReportURL checks URL shape for a symbol.
func ValidateReportURL(symbol, raw string) bool {
	m := reportURLRe.FindStringSubmatch(strings.TrimSpace(raw))
	if len(m) < 3 {
		return false
	}
	return strings.EqualFold(m[2], symbol)
}

// AbsoluteURL ensures absolute Trendlyne URL.
func AbsoluteURL(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if strings.HasPrefix(raw, "http://") || strings.HasPrefix(raw, "https://") {
		return strings.TrimRight(raw, "/") + "/"
	}
	u, err := url.Parse("https://trendlyne.com")
	if err != nil {
		return raw
	}
	ref, err := url.Parse(raw)
	if err != nil {
		return raw
	}
	return strings.TrimRight(u.ResolveReference(ref).String(), "/") + "/"
}
