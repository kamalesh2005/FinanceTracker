package handlers

import (
	"log"
	"strings"
	"time"

	"financetracker/mfapi"
	"financetracker/models"
)

// fyLabels are Indian FY labels: FY Y ends 31 Mar (Y+1).
var fyLabels = []int{2020, 2021, 2022, 2023, 2024, 2025}

// RefreshAllMutualFundCurrentNAVs pulls latest NAV from mfapi.in for every
// Global_MutualFunds row with a non-empty symbol (scheme code).
func (h *Handler) RefreshAllMutualFundCurrentNAVs() error {
	client := mfapi.NewClient()
	var funds []models.GlobalMutualFund
	if err := h.DB.Where("symbol <> ''").Find(&funds).Error; err != nil {
		return err
	}
	log.Printf("MFNAVCron: refreshing current NAV for %d funds", len(funds))
	ok, fail := 0, 0
	now := time.Now()
	for _, f := range funds {
		sym := strings.TrimSpace(f.Symbol)
		if sym == "" {
			continue
		}
		nav, asOf, err := client.LatestNAV(sym)
		if err != nil {
			fail++
			log.Printf("MFNAVCron: latest FAIL isin=%s symbol=%s: %v", f.ISIN, sym, err)
			continue
		}
		if nav <= 0 {
			fail++
			continue
		}
		t := asOf
		if t.IsZero() {
			t = now
		}
		if err := h.DB.Model(&models.GlobalMutualFund{}).Where("id = ?", f.ID).Updates(map[string]interface{}{
			"current_nav":   nav,
			"last_nav_date": t,
			"updated_at":    now,
		}).Error; err != nil {
			fail++
			log.Printf("MFNAVCron: db FAIL isin=%s: %v", f.ISIN, err)
			continue
		}
		ok++
	}
	log.Printf("MFNAVCron: done ok=%d fail=%d", ok, fail)
	return nil
}

// BuildMFYearEndBackfillQueue returns incomplete Global_MutualFunds ordered by
// priority: ISINs present in User_MutualFunds first, then the rest of the catalog.
// Incomplete = all of nav_fy_2020…nav_fy_2025 are still 0 (never successfully populated).
func (h *Handler) BuildMFYearEndBackfillQueue() ([]models.GlobalMutualFund, error) {
	var heldISINs []string
	if err := h.DB.Model(&models.MutualFund{}).
		Distinct("isin").
		Where("isin <> ''").
		Pluck("isin", &heldISINs).Error; err != nil {
		return nil, err
	}
	held := map[string]struct{}{}
	for _, raw := range heldISINs {
		isin := strings.ToUpper(strings.TrimSpace(raw))
		if isin != "" {
			held[isin] = struct{}{}
		}
	}

	var incomplete []models.GlobalMutualFund
	// AutoMigrate added these as nullable numerics, so existing rows are NULL
	// rather than 0. `col = 0` does not match NULL in Postgres.
	if err := h.DB.Where(
		"btrim(COALESCE(symbol, '')) <> '' AND "+
			"COALESCE(nav_fy_2020, 0) = 0 AND COALESCE(nav_fy_2021, 0) = 0 AND "+
			"COALESCE(nav_fy_2022, 0) = 0 AND COALESCE(nav_fy_2023, 0) = 0 AND "+
			"COALESCE(nav_fy_2024, 0) = 0 AND COALESCE(nav_fy_2025, 0) = 0",
	).Find(&incomplete).Error; err != nil {
		return nil, err
	}

	var priority, rest []models.GlobalMutualFund
	seen := map[uint]struct{}{}
	for _, f := range incomplete {
		if _, ok := seen[f.ID]; ok {
			continue
		}
		seen[f.ID] = struct{}{}
		isin := strings.ToUpper(strings.TrimSpace(f.ISIN))
		if _, ok := held[isin]; ok {
			priority = append(priority, f)
		} else {
			rest = append(rest, f)
		}
	}
	log.Printf("MFFYBackfill: incomplete=%d held-priority=%d catalog-rest=%d",
		len(incomplete), len(priority), len(rest))
	return append(priority, rest...), nil
}

// BackfillMFYearEndNAVs fetches FY-end NAVs for the given funds and writes columns.
func (h *Handler) BackfillMFYearEndNAVs(funds []models.GlobalMutualFund) (ok, fail int) {
	client := mfapi.NewClient()
	now := time.Now()
	for _, f := range funds {
		sym := strings.TrimSpace(f.Symbol)
		if sym == "" {
			continue
		}
		fy, err := client.FiscalYearEndNAVs(sym, fyLabels)
		if err != nil {
			fail++
			log.Printf("MFFYBackfill: FAIL isin=%s symbol=%s: %v", f.ISIN, sym, err)
			continue
		}
		updates := map[string]interface{}{"updated_at": now}
		wrote := false
		for _, y := range fyLabels {
			if nav, okNav := fy[y]; okNav && nav > 0 {
				updates[fyNAVColumn(y)] = nav
				wrote = true
			}
		}
		if !wrote {
			fail++
			log.Printf("MFFYBackfill: no FY-end NAVs isin=%s symbol=%s", f.ISIN, sym)
			continue
		}
		if err := h.DB.Model(&models.GlobalMutualFund{}).Where("id = ?", f.ID).Updates(updates).Error; err != nil {
			fail++
			log.Printf("MFFYBackfill: db FAIL isin=%s: %v", f.ISIN, err)
			continue
		}
		ok++
	}
	return ok, fail
}

func fyNAVColumn(fy int) string {
	switch fy {
	case 2020:
		return "nav_fy_2020"
	case 2021:
		return "nav_fy_2021"
	case 2022:
		return "nav_fy_2022"
	case 2023:
		return "nav_fy_2023"
	case 2024:
		return "nav_fy_2024"
	case 2025:
		return "nav_fy_2025"
	default:
		return ""
	}
}

// pctReturn returns (end-start)/start*100, or nil if either side is non-positive.
func pctReturn(start, end float64) *float64 {
	if start <= 0 || end <= 0 {
		return nil
	}
	v := (end - start) / start * 100
	return &v
}

func applyGlobalReturns(mf *models.MutualFund, g models.GlobalMutualFund) {
	mf.Return2021 = pctReturn(g.NavFY2020, g.NavFY2021)
	mf.Return2022 = pctReturn(g.NavFY2021, g.NavFY2022)
	mf.Return2023 = pctReturn(g.NavFY2022, g.NavFY2023)
	mf.Return2024 = pctReturn(g.NavFY2023, g.NavFY2024)
	mf.Return2025 = pctReturn(g.NavFY2024, g.NavFY2025)
	current := g.CurrentNAV
	if current <= 0 {
		current = mf.CurrentNAV
	}
	mf.ReturnYTD = pctReturn(g.NavFY2025, current)
}
