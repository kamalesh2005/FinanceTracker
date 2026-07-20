package handlers

import (
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"sync"
	"time"
)

const yahooUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

var (
	yahooAuthMu   sync.Mutex
	yahooCrumb    string
	yahooCrumbAt  time.Time
	yahooHTTPCli  *http.Client
	yahooCrumbTTL = 30 * time.Minute
)

func yahooHTTPClient() *http.Client {
	if yahooHTTPCli != nil {
		return yahooHTTPCli
	}
	jar, err := cookiejar.New(nil)
	if err != nil {
		yahooHTTPCli = &http.Client{Timeout: 15 * time.Second}
		return yahooHTTPCli
	}
	yahooHTTPCli = &http.Client{
		Timeout: 15 * time.Second,
		Jar:     jar,
	}
	return yahooHTTPCli
}

// getYahooCrumb returns a cached Yahoo Finance crumb, refreshing cookies when needed.
// quoteSummary / v7 quote endpoints require this crumb + session cookies.
func getYahooCrumb(forceRefresh bool) (string, *http.Client, error) {
	yahooAuthMu.Lock()
	defer yahooAuthMu.Unlock()

	client := yahooHTTPClient()
	if !forceRefresh && yahooCrumb != "" && time.Since(yahooCrumbAt) < yahooCrumbTTL {
		return yahooCrumb, client, nil
	}

	// fc.yahoo.com sets A1/A3 consent cookies required by crumb + quote APIs
	// (often returns 404; that is expected).
	for _, warmURL := range []string{"https://fc.yahoo.com", "https://finance.yahoo.com/"} {
		homeReq, err := http.NewRequest("GET", warmURL, nil)
		if err != nil {
			return "", nil, err
		}
		homeReq.Header.Set("User-Agent", yahooUserAgent)
		homeResp, err := client.Do(homeReq)
		if err != nil {
			continue
		}
		io.Copy(io.Discard, homeResp.Body)
		homeResp.Body.Close()
	}

	crumbReq, err := http.NewRequest("GET", "https://query1.finance.yahoo.com/v1/test/getcrumb", nil)
	if err != nil {
		return "", nil, err
	}
	crumbReq.Header.Set("User-Agent", yahooUserAgent)
	crumbResp, err := client.Do(crumbReq)
	if err != nil {
		return "", nil, fmt.Errorf("yahoo crumb request: %w", err)
	}
	defer crumbResp.Body.Close()
	body, err := io.ReadAll(crumbResp.Body)
	if err != nil {
		return "", nil, err
	}
	if crumbResp.StatusCode != http.StatusOK {
		return "", nil, fmt.Errorf("yahoo crumb status %d: %s", crumbResp.StatusCode, string(body))
	}
	crumb := string(body)
	if crumb == "" || crumb == "\"\"" {
		return "", nil, fmt.Errorf("yahoo crumb empty")
	}

	yahooCrumb = crumb
	yahooCrumbAt = time.Now()
	return yahooCrumb, client, nil
}

func yahooDo(req *http.Request) (*http.Response, error) {
	req.Header.Set("User-Agent", yahooUserAgent)

	crumb, client, err := getYahooCrumb(false)
	if err != nil {
		return nil, err
	}

	q := req.URL.Query()
	q.Set("crumb", crumb)
	req.URL.RawQuery = q.Encode()

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusUnauthorized && resp.StatusCode != http.StatusForbidden {
		return resp, nil
	}
	resp.Body.Close()

	// Crumb/session expired — refresh and retry once.
	crumb, client, err = getYahooCrumb(true)
	if err != nil {
		return nil, err
	}
	q = req.URL.Query()
	q.Set("crumb", crumb)
	req.URL.RawQuery = q.Encode()
	return client.Do(req)
}
