package nsemf

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"financetracker/mfimport"

	"gorm.io/gorm"
)

const (
	// NSE Haircut for Mutual Funds (csv): MF_VAR_{DDMMYYYY}.csv
	nseMFVarURLFmt  = "https://nsearchives.nseindia.com/archives/equities/mf_haircut/MF_VAR_%s.csv"
	nseUserAgent    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
	maxLookbackDays = 5
)

// DownloadLatestMFVarCSV tries today (IST) then walks back up to maxLookbackDays.
func DownloadLatestMFVarCSV(now time.Time) (csvBytes []byte, filename string, usedDate time.Time, err error) {
	ist, locErr := time.LoadLocation("Asia/Kolkata")
	if locErr != nil {
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}
	day := now.In(ist)

	client := &http.Client{Timeout: 90 * time.Second}
	var lastErr error
	for i := 0; i <= maxLookbackDays; i++ {
		d := day.AddDate(0, 0, -i)
		ddMmYyyy := fmt.Sprintf("%02d%02d%04d", d.Day(), int(d.Month()), d.Year())
		name := fmt.Sprintf("MF_VAR_%s.csv", ddMmYyyy)
		url := fmt.Sprintf(nseMFVarURLFmt, ddMmYyyy)

		data, status, getErr := httpGet(client, url)
		if getErr != nil {
			lastErr = getErr
			log.Printf("nsemf: download %s: %v", url, getErr)
			continue
		}
		if status == http.StatusNotFound {
			lastErr = fmt.Errorf("%s not found (HTTP 404)", name)
			log.Printf("nsemf: %v", lastErr)
			continue
		}
		if status != http.StatusOK {
			lastErr = fmt.Errorf("%s: HTTP %d", name, status)
			log.Printf("nsemf: %v", lastErr)
			continue
		}
		if len(data) == 0 {
			lastErr = fmt.Errorf("%s: empty body", name)
			continue
		}
		if !looksLikeMFVarCSV(data) {
			lastErr = fmt.Errorf("%s: not a MF_VAR CSV (got %d bytes)", name, len(data))
			log.Printf("nsemf: %v", lastErr)
			continue
		}
		log.Printf("nsemf: downloaded %s (%d bytes) for %s", name, len(data), d.Format("2006-01-02"))
		return data, name, d, nil
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("no MF_VAR CSV found in last %d days", maxLookbackDays+1)
	}
	return nil, "", time.Time{}, lastErr
}

func httpGet(client *http.Client, url string) ([]byte, int, error) {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("User-Agent", nseUserAgent)
	req.Header.Set("Accept", "text/csv,*/*")
	req.Header.Set("Referer", "https://www.nseindia.com/")

	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, err
	}
	return data, resp.StatusCode, nil
}

func looksLikeMFVarCSV(data []byte) bool {
	if len(data) == 0 {
		return false
	}
	// Reject HTML error pages.
	trim := bytes.TrimSpace(data)
	if len(trim) >= 9 && (bytes.HasPrefix(trim, []byte("<!DOCTYPE")) ||
		bytes.HasPrefix(trim, []byte("<html")) ||
		bytes.HasPrefix(trim, []byte("<HTML"))) {
		return false
	}
	head := string(trim)
	if len(head) > 200 {
		head = head[:200]
	}
	upper := strings.ToUpper(head)
	return strings.Contains(upper, "ISIN") && strings.Contains(upper, "NAV")
}

// PullAndImport downloads the latest MF_VAR CSV and imports NAV rows.
func PullAndImport(db *gorm.DB, now time.Time) (mfimport.Result, error) {
	data, filename, _, err := DownloadLatestMFVarCSV(now)
	if err != nil {
		return mfimport.Result{}, err
	}
	return mfimport.ImportBytes(db, data, filename)
}
