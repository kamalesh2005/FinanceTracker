package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func ffTestSetup(t *testing.T) (*Handler, models.User, *gin.Engine) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("db: %v", err)
	}
	sqlDB.SetMaxOpenConns(1)
	if err := db.AutoMigrate(
		&models.User{},
		&models.Stock{},
		&models.UserStock{},
		&models.MutualFund{},
		&models.GlobalMutualFund{},
		&models.FFAsset{},
		&models.FFJobIncome{},
		&models.FFExpense{},
		&models.FFOneTimeExpense{},
	); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	admin := models.User{Role: models.RoleAdmin, Enabled: true}
	if err := db.Create(&admin).Error; err != nil {
		t.Fatalf("create admin: %v", err)
	}
	h := &Handler{DB: db}
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set(middleware.ContextUserIDKey, admin.ID)
		c.Set(middleware.ContextRoleKey, admin.Role)
		c.Set(middleware.ContextUserKey, admin)
		c.Next()
	})
	RegisterFinancialFreedomRoutes(r.Group(""), h)
	return h, admin, r
}

func ffDo(r *gin.Engine, method, path string, body any) *httptest.ResponseRecorder {
	var reader *bytes.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		reader = bytes.NewReader(b)
	} else {
		reader = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, reader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestFFAssetCRUDAndDerivedIncome(t *testing.T) {
	_, _, r := ffTestSetup(t)

	w := ffDo(r, http.MethodPost, "/ff/assets", map[string]any{
		"category": "liquid_cash", "preset_key": "fd",
		"name": "FD", "value": 1000000, "is_liquid": true,
		"linked_liability": 100000, "income_pct": 7, "income_start_year": 2024,
		"tax_pct": 10,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create status=%d body=%s", w.Code, w.Body.String())
	}
	var created map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("json: %v", err)
	}
	// 1e6 * 7% = 70000; after 10% tax = 63000
	if created["calculated_income"].(float64) != 70000 {
		t.Fatalf("calculated_income=%v", created["calculated_income"])
	}
	if created["effective_income"].(float64) != 63000 {
		t.Fatalf("effective_income=%v", created["effective_income"])
	}

	id := int(created["id"].(float64))
	w = ffDo(r, http.MethodPut, "/ff/assets/"+strconv.Itoa(id), map[string]any{
		"category": "liquid_cash", "preset_key": "fd",
		"name": "FD Updated", "value": 2000000, "is_liquid": true,
		"linked_liability": 0, "income_pct": 6, "income_start_year": 2024, "tax_pct": 0,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("update status=%d body=%s", w.Code, w.Body.String())
	}

	w = ffDo(r, http.MethodDelete, "/ff/assets/"+strconv.Itoa(id), nil)
	if w.Code != http.StatusNoContent {
		t.Fatalf("delete status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestResetFFAssetIncomeDefaults(t *testing.T) {
	_, _, r := ffTestSetup(t)

	w := ffDo(r, http.MethodPost, "/ff/assets", map[string]any{
		"category": "liquid_cash", "preset_key": "fd",
		"name": "FD", "value": 1000000, "is_liquid": true,
		"linked_liability": 0, "income_pct": 99, "income_start_year": 2024, "tax_pct": 0,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create status=%d body=%s", w.Code, w.Body.String())
	}

	w = ffDo(r, http.MethodPost, "/ff/assets/reset-income-defaults", map[string]any{})
	if w.Code != http.StatusOK {
		t.Fatalf("reset status=%d body=%s", w.Code, w.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatalf("json: %v", err)
	}
	if int(payload["updated"].(float64)) != 1 {
		t.Fatalf("updated=%v want 1", payload["updated"])
	}

	w = ffDo(r, http.MethodGet, "/ff/assets", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list status=%d", w.Code)
	}
	var rows []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &rows); err != nil {
		t.Fatalf("json: %v", err)
	}
	if len(rows) != 1 || rows[0]["income_pct"].(float64) != 6 {
		t.Fatalf("income_pct=%v want 6", rows[0]["income_pct"])
	}
}

func TestFFExpenseEndYearOptional(t *testing.T) {
	_, _, r := ffTestSetup(t)

	w := ffDo(r, http.MethodPost, "/ff/expenses", map[string]any{
		"category": "emi", "amount": 120000,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("emi without end_year status=%d body=%s", w.Code, w.Body.String())
	}

	end := time.Now().Year() + 5
	w = ffDo(r, http.MethodPost, "/ff/expenses", map[string]any{
		"category": "emi", "amount": 120000, "end_year": end,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("emi with end_year status=%d body=%s", w.Code, w.Body.String())
	}

	w = ffDo(r, http.MethodPost, "/ff/expenses", map[string]any{
		"category": "rent", "amount": 240000,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("rent status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestFFJobIncomeEndYearOptional(t *testing.T) {
	_, _, r := ffTestSetup(t)

	w := ffDo(r, http.MethodPost, "/ff/job-income", map[string]any{
		"label": "Salary", "amount": 1200000,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("job without end_year status=%d body=%s", w.Code, w.Body.String())
	}
	var created map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("json: %v", err)
	}
	if created["end_year"].(float64) != 0 {
		t.Fatalf("end_year=%v want 0", created["end_year"])
	}
	id := int(created["id"].(float64))

	w = ffDo(r, http.MethodPut, "/ff/job-income/"+strconv.Itoa(id), map[string]any{
		"label": "Salary", "amount": 1500000,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("update without end_year status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestFFCustomExpenseCategory(t *testing.T) {
	_, _, r := ffTestSetup(t)

	w := ffDo(r, http.MethodPost, "/ff/expenses", map[string]any{
		"category": "Gym membership", "amount": 36000,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("custom expense status=%d body=%s", w.Code, w.Body.String())
	}
	var created map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("json: %v", err)
	}
	if created["category"] != "Gym membership" {
		t.Fatalf("category=%v", created["category"])
	}
	id := int(created["id"].(float64))

	w = ffDo(r, http.MethodDelete, "/ff/expenses/"+strconv.Itoa(id), nil)
	if w.Code != http.StatusNoContent {
		t.Fatalf("delete custom status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestFFPresetExpenseCannotDelete(t *testing.T) {
	_, _, r := ffTestSetup(t)

	w := ffDo(r, http.MethodPost, "/ff/expenses", map[string]any{
		"preset_key": "rent", "category": "rent", "amount": 240000,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("rent status=%d body=%s", w.Code, w.Body.String())
	}
	var created map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("json: %v", err)
	}
	id := int(created["id"].(float64))

	w = ffDo(r, http.MethodDelete, "/ff/expenses/"+strconv.Itoa(id), nil)
	if w.Code != http.StatusForbidden {
		t.Fatalf("delete preset status=%d want 403 body=%s", w.Code, w.Body.String())
	}
}

func TestFfReadyToRetireSimulation(t *testing.T) {
	y0 := 2026

	// Inflation-adjusted passive: 12% → 6% effective; 6% → 0%.
	eqAsset := models.FFAsset{
		Name: "Equity", Value: 10000000, IncomePct: 12, TaxPct: 0,
		IncomeStartYear: y0, Category: models.FFAssetCatMarketEquity,
	}
	reAsset := models.FFAsset{
		Name: "Rental", Value: 10000000, IncomePct: 12, TaxPct: 0,
		IncomeStartYear: y0, Category: models.FFAssetCatRealEstateGold,
	}
	if got := ffInflationAdjustedPassiveIncome([]models.FFAsset{eqAsset}, y0); got != 600000 {
		t.Fatalf("adj passive equity 12%%=%v want 600000", got)
	}
	if got := ffInflationAdjustedPassiveIncome([]models.FFAsset{reAsset}, y0); got != 1200000 {
		t.Fatalf("adj passive RE 12%%=%v want 1200000 (no inflation haircut)", got)
	}

	expenses := []models.FFExpense{{Category: models.FFExpenseRent, Amount: 500000}}

	// Already ready: adj passive covers total expenses at horizon end.
	readyAsset := models.FFAsset{
		Name: "Fund", Value: 10000000, IncomePct: 12, TaxPct: 0,
		IncomeStartYear: y0, Category: models.FFAssetCatMarketEquity,
	}
	n, _, rows := ffSimulateReadyToRetire([]models.FFAsset{readyAsset}, nil, expenses, nil, y0)
	if n != 0 {
		t.Fatalf("years=%d want 0 (NOW)", n)
	}
	if len(rows) != 1 {
		t.Fatalf("rows=%d want 1 (horizon y0 only)", len(rows))
	}

	// Salary plus strong passive: all years YES through horizon → NOW.
	assets := []models.FFAsset{{
		Name: "Fund", Value: 30000000, IncomePct: 12, TaxPct: 0,
		IncomeStartYear: y0, Category: models.FFAssetCatMarketEquity,
	}}
	jobs := []models.FFJobIncome{{Label: "Salary", Amount: 700000, EndYear: y0 + 30}}
	n, _ = ffYearsUntilReadyToRetire(assets, jobs, expenses, nil, y0)
	if n != 0 {
		t.Fatalf("years=%d want 0 when income covers expenses through horizon", n)
	}

	// Passive alone below expenses → last year NO → unreachable.
	assets = []models.FFAsset{{
		Name: "Fund", Value: 5500000, IncomePct: 8, TaxPct: 0,
		IncomeStartYear: y0, Category: models.FFAssetCatMarketEquity,
	}}
	n, _ = ffYearsUntilReadyToRetire(assets, nil, expenses, nil, y0)
	if n != -1 {
		t.Fatalf("years=%d want -1 when passive alone stays below expenses", n)
	}

	// One-time amounts are nominal (no inflation growth).
	oneTime := []models.FFOneTimeExpense{{
		Name: "Wedding", Amount: 200000, ExpectedYear: y0 + 1,
	}}
	if got := ffOneTimeInYear(oneTime, y0+1); got != 200000 {
		t.Fatalf("one-time=%v want 200000", got)
	}

	// Horizon = max(last OT+1, salary end+1, pension start+1).
	pensionStart := y0 + 20
	jobsMixed := []models.FFJobIncome{
		{Label: "Salary", Amount: 1000000, EndYear: y0 + 10},
		{
			Label: "Pension", Amount: 500000, EndYear: 0,
			PresetKey: strPtr(models.FFJobPensionPreset), StartYear: intPtr(pensionStart),
		},
	}
	if got := ffRetireSimHorizonEndYear(oneTime, jobsMixed, y0); got != pensionStart+1 {
		t.Fatalf("horizon=%d want %d", got, pensionStart+1)
	}

	// Backward-walk ready: y0 NO, later years YES, last YES → ready y0+1.
	smallAssets := []models.FFAsset{{
		Name: "Fund", Value: 5500000, IncomePct: 8, TaxPct: 0,
		IncomeStartYear: y0, Category: models.FFAssetCatMarketEquity,
	}}
	pensionFrom := y0 + 1
	jobsShort := []models.FFJobIncome{{
		Label: "Pension", Amount: 500000, EndYear: 0,
		PresetKey: strPtr(models.FFJobPensionPreset), StartYear: intPtr(pensionFrom),
	}}
	n, _, rows = ffSimulateReadyToRetire(smallAssets, jobsShort, expenses, nil, y0)
	if n != 1 {
		t.Fatalf("years=%d want 1 (ready after first NO year)", n)
	}
	if len(rows) != 3 {
		t.Fatalf("rows=%d want 3 (horizon through pension start+1)", len(rows))
	}
	if rows[0].IncomeMeetsExpense {
		t.Fatalf("year 0 should be NO")
	}
	if !rows[len(rows)-1].IncomeMeetsExpense {
		t.Fatalf("last year should be YES")
	}

	// Corpus wiped by one-times: last year NO → unreachable.
	wipeOT := []models.FFOneTimeExpense{
		{Name: "A", Amount: 30000000, ExpectedYear: y0 + 1},
		{Name: "B", Amount: 20000000, ExpectedYear: y0 + 3},
		{Name: "C", Amount: 10000000, ExpectedYear: y0 + 4},
	}
	jobsSmall := []models.FFJobIncome{{Label: "Salary", Amount: 1200000, EndYear: y0 + 30}}
	stressed := []models.FFAsset{{
		Name: "Fund", Value: 53010000, IncomePct: 12.75, TaxPct: 0,
		IncomeStartYear: y0, Category: models.FFAssetCatMarketEquity,
	}}
	stressedExp := []models.FFExpense{{Category: models.FFExpenseRent, Amount: 7620000}}
	n, _ = ffYearsUntilReadyToRetire(stressed, jobsSmall, stressedExp, wipeOT, y0)
	if n != -1 {
		t.Fatalf("years=%d want -1 when corpus gone at horizon end", n)
	}

	// Inc ≥ Exp flag uses recurring + asset EMI only; total_expenses includes one-time.
	endEMI := y0 + 2
	expensesWithEMI := []models.FFExpense{
		{Category: models.FFExpenseRent, Amount: 200000},
		{Category: models.FFExpenseEMI, Amount: 300000, EndYear: &endEMI},
	}
	weddingAssets := []models.FFAsset{{
		Name: "Fund", Value: 10000000, IncomePct: 12, TaxPct: 0,
		IncomeStartYear: y0, Category: models.FFAssetCatMarketEquity,
	}}
	weddingOT := []models.FFOneTimeExpense{{
		Name: "Wedding", Amount: 5000000, ExpectedYear: y0 + 1,
	}}
	n, _, rows = ffSimulateReadyToRetire(weddingAssets, nil, expensesWithEMI, weddingOT, y0)
	if len(rows) < 2 {
		t.Fatalf("expected >=2 rows, got %d", len(rows))
	}
	otRow := rows[1]
	if otRow.OneTimeExpense != 5000000 {
		t.Fatalf("one-time=%v want 5000000", otRow.OneTimeExpense)
	}
	if otRow.TotalExpenses != otRow.OneTimeExpense+500000 {
		t.Fatalf("total_exp=%v want one-time+recurring", otRow.TotalExpenses)
	}
	if otRow.FlagExpenses != 500000 {
		t.Fatalf("flag_exp=%v want 500000 (recurring+EMI, no one-time)", otRow.FlagExpenses)
	}
	if otRow.IncomeMeetsExpense != (otRow.EndIncome >= otRow.FlagExpenses) {
		t.Fatalf("flag should compare end income to flag_exp only")
	}

	// One-time larger than corpus wipes passive to zero that year.
	wiped := ffCloneAssets(smallAssets)
	ffDeductFromAssets(wiped, 6000000)
	if ffInflationAdjustedPassiveIncome(wiped, y0) != 0 {
		t.Fatalf("adj passive after wipe=%v want 0", ffInflationAdjustedPassiveIncome(wiped, y0))
	}
}

func TestComputeFFMetricsRetirementAndInsurance(t *testing.T) {
	y0 := 2026
	endEMI := 2028
	assets := []models.FFAsset{
		{
			Name: "Rentals", Value: 10000000, IncomePct: 6, TaxPct: 0,
			IncomeStartYear: y0, IsLiquid: true, LinkedLiability: 500000,
		},
	}
	// effective income = 600000
	expenses := []models.FFExpense{
		{Category: models.FFExpenseRent, Amount: 200000},
		{Category: models.FFExpenseEMI, Amount: 300000, EndYear: &endEMI},
	}
	// recurring at y0: 500000; end-of-year passive still ≥ expenses after wedding OT in y0+1
	oneTime := []models.FFOneTimeExpense{
		{Name: "Wedding", Amount: 1000000, ExpectedYear: y0 + 1},
	}

	m, _ := computeFFMetrics(assets, nil, expenses, oneTime, y0)
	if m.PassiveIncome != 600000 {
		t.Fatalf("passive_income=%v want 600000", m.PassiveIncome)
	}
	if m.RegularExpenses != 500000 {
		t.Fatalf("regular_expenses=%v want 500000", m.RegularExpenses)
	}
	if m.ActiveIncome != 0 {
		t.Fatalf("active_income=%v want 0", m.ActiveIncome)
	}
	wantYears, _ := ffYearsUntilReadyToRetire(assets, nil, expenses, oneTime, y0)
	if wantYears < 0 {
		if m.YearsToRetire != nil {
			t.Fatalf("years_to_retire=%v want nil (unreachable)", m.YearsToRetire)
		}
		if m.RetirementYear != nil {
			t.Fatalf("retirement_year=%v want nil", m.RetirementYear)
		}
	} else {
		if m.YearsToRetire == nil || *m.YearsToRetire != wantYears {
			t.Fatalf("years_to_retire=%v want %d", m.YearsToRetire, wantYears)
		}
		if m.RetirementYear == nil || *m.RetirementYear != y0+wantYears {
			t.Fatalf("retirement_year=%v want %d", m.RetirementYear, y0+wantYears)
		}
	}
	if m.AnnualEnjoymentFund == nil {
		t.Fatalf("enjoyment should always be set")
	}
	// Scenario 2 only applies when ready is NOW; this profile is not ready at y0.
	if *m.AnnualEnjoymentFund != 0 {
		t.Fatalf("annual_enjoyment_fund=%v want 0", *m.AnnualEnjoymentFund)
	}

	// 15/75 rule:
	// living expenses (excl EMI) = 200000
	// debt = expense EMI 300000 × (2028-2026+1) = 900000
	// investments = 10000000 (liquid rental asset)
	// cover = 900000 + 15*0.75*200000 - 10000000 = 900000 + 2250000 - 10000000 < 0 → 0
	if m.TermInsuranceNeed != 0 {
		t.Fatalf("term_insurance_need=%v want 0", m.TermInsuranceNeed)
	}

	// Lower investments; add asset EMI debt
	keyResidence := "primary_residence"
	keyMF := "mutual_funds"
	assets = []models.FFAsset{
		{
			Name: "MF", Value: 500000, IncomePct: 0, TaxPct: 0,
			IncomeStartYear: y0, PresetKey: &keyMF,
		},
		{
			Name: "Home", Value: 8000000, IncomePct: 0, TaxPct: 0,
			IncomeStartYear: y0, PresetKey: &keyResidence,
			EmiAmount: 50, EmiInstallmentsLeft: 100, // debt 5000
		},
		{
			Name: "Physical Gold", Value: 1000000, IncomePct: 0,
			IncomeStartYear: y0, PresetKey: strPtr("physical_gold"),
		},
	}
	m, _ = computeFFMetrics(assets, nil, expenses, oneTime, y0)
	// living = 200000
	// debt = 300000*3 + 50*100 = 900000 + 5000 = 905000
	// investments = 500000 only (exclude residence + physical gold)
	// cover = 905000 + 15*0.75*200000 - 500000 = 905000 + 2250000 - 500000 = 2655000
	if m.TermInsuranceNeed != 2655000 {
		t.Fatalf("term_insurance_need=%v want 2655000", m.TermInsuranceNeed)
	}
}

func strPtr(s string) *string { return &s }

func intPtr(n int) *int { return &n }

func TestFfJobIncomePension(t *testing.T) {
	y0 := 2026
	jobs := []models.FFJobIncome{
		{Label: "Salary", Amount: 1000000, EndYear: 2030},
		{
			Label: "Pension", Amount: 500000, EndYear: 0,
			PresetKey: strPtr(models.FFJobPensionPreset), StartYear: intPtr(2031),
		},
	}
	if got := ffJobIncome(jobs, y0); got != 1000000 {
		t.Fatalf("y0 active=%v want 1000000", got)
	}
	if got := ffJobIncome(jobs, 2030); got != 1000000 {
		t.Fatalf("2030 active=%v want salary only", got)
	}
	if got := ffJobIncome(jobs, 2031); got != 500000 {
		t.Fatalf("2031 active=%v want pension only", got)
	}
	if max, ok := ffMaxJobEndYear(jobs); !ok || max != 2030 {
		t.Fatalf("maxJobEnd=%v ok=%v want 2030 true", max, ok)
	}

	ongoing := []models.FFJobIncome{{Label: "Salary", Amount: 800000, EndYear: 0}}
	if got := ffJobIncome(ongoing, y0); got != 800000 {
		t.Fatalf("ongoing y0=%v want 800000", got)
	}
	if got := ffJobIncome(ongoing, y0+40); got != 800000 {
		t.Fatalf("ongoing later=%v want 800000", got)
	}
	if max, ok := ffMaxJobEndYear(ongoing); ok {
		t.Fatalf("maxJobEnd=%v ok=%v want none", max, ok)
	}
}

func TestFfLiveWellFund(t *testing.T) {
	y0 := 2026
	expenses := []models.FFExpense{{Category: models.FFExpenseRent, Amount: 500000}}

	liveWell := func(
		assets []models.FFAsset,
		jobs []models.FFJobIncome,
		ex []models.FFExpense,
		oneTime []models.FFOneTimeExpense,
	) float64 {
		n, _, rows := ffSimulateReadyToRetire(assets, jobs, ex, oneTime, y0)
		var ry *int
		if n >= 0 {
			v := y0 + n
			ry = &v
		}
		return ffLiveWellFund(oneTime, y0, rows, ry)
	}

	targetYear := func(
		oneTime []models.FFOneTimeExpense,
		jobs []models.FFJobIncome,
		assets []models.FFAsset,
		ex []models.FFExpense,
	) int {
		n, _, _ := ffSimulateReadyToRetire(assets, jobs, ex, oneTime, y0)
		if n < 0 {
			t.Fatal("targetYear: ready is unreachable")
		}
		t, _, _ := ffLiveWellTargetYear(oneTime, y0, y0+n)
		return t
	}

	surplusForYear := func(
		assets []models.FFAsset,
		jobs []models.FFJobIncome,
		ex []models.FFExpense,
		oneTime []models.FFOneTimeExpense,
		year int,
	) float64 {
		_, _, rows := ffSimulateReadyToRetire(assets, jobs, ex, oneTime, y0)
		row, ok := ffRetireSimRowForYear(rows, year)
		if !ok {
			t.Fatalf("missing sim row for %d", year)
		}
		return row.EndIncome - row.TotalExpenses
	}

	t.Run("no one-time uses current year surplus halved", func(t *testing.T) {
		assets := []models.FFAsset{{
			Name: "Fund", Value: 10000000, IncomePct: 12, TaxPct: 0,
			IncomeStartYear: y0, Category: models.FFAssetCatMarketEquity,
		}}
		_, _, rows := ffSimulateReadyToRetire(assets, nil, expenses, nil, y0)
		surplus := surplusForYear(assets, nil, expenses, nil, y0)
		today, _, _ := ffSurplusInTodayValue(surplus, rows, y0, y0)
		want := today / 2
		if want < 0 {
			want = 0
		}
		got := liveWell(assets, nil, expenses, nil)
		if got != want {
			t.Fatalf("fund=%v want %v (today surplus/2)", got, want)
		}
	})

	t.Run("after last one-time year discounted then halved", func(t *testing.T) {
		jobs := []models.FFJobIncome{{Label: "Salary", Amount: 2000000, EndYear: 0}}
		oneTime := []models.FFOneTimeExpense{{
			Name: "Trip", Amount: 1000000, ExpectedYear: 2030,
		}}
		target := targetYear(oneTime, jobs, nil, expenses)
		if target != 2031 {
			t.Fatalf("target=%d want 2031", target)
		}
		_, _, rows := ffSimulateReadyToRetire(nil, jobs, expenses, oneTime, y0)
		surplus := surplusForYear(nil, jobs, expenses, oneTime, target)
		today, _, years := ffSurplusInTodayValue(surplus, rows, y0, target)
		if years != 5 {
			t.Fatalf("discountYears=%d want 5", years)
		}
		want := today / 2
		if want < 0 {
			want = 0
		}
		got := liveWell(nil, jobs, expenses, oneTime)
		if got != want {
			t.Fatalf("fund=%v want %v", got, want)
		}
	})

	t.Run("discount uses passive pct when corpus present", func(t *testing.T) {
		assets := []models.FFAsset{{
			Name: "Fund", Value: 50000000, IncomePct: 10, TaxPct: 0,
			IncomeStartYear: y0, Category: models.FFAssetCatMarketEquity,
		}}
		jobs := []models.FFJobIncome{{Label: "Salary", Amount: 2000000, EndYear: 2035}}
		oneTime := []models.FFOneTimeExpense{{
			Name: "Trip", Amount: 1000000, ExpectedYear: 2030,
		}}
		target := targetYear(oneTime, jobs, assets, expenses)
		_, _, rows := ffSimulateReadyToRetire(assets, jobs, expenses, oneTime, y0)
		row, ok := ffRetireSimRowForYear(rows, target)
		if !ok {
			t.Fatal("missing target row")
		}
		if row.PassivePct <= 0 {
			t.Fatalf("passive_pct=%v want positive for discount test", row.PassivePct)
		}
		surplus := row.EndIncome - row.TotalExpenses
		today, _, _ := ffSurplusInTodayValue(surplus, rows, y0, target)
		want := today / 2
		got := liveWell(assets, jobs, expenses, oneTime)
		if got != want {
			t.Fatalf("fund=%v want %v", got, want)
		}
		if today >= surplus {
			t.Fatalf("today=%v should be less than nominal surplus=%v", today, surplus)
		}
	})

	t.Run("negative surplus floored at zero", func(t *testing.T) {
		jobs := []models.FFJobIncome{{Label: "Salary", Amount: 400000, EndYear: 2030}}
		got := liveWell(nil, jobs, expenses, nil)
		if got != 0 {
			t.Fatalf("fund=%v want 0", got)
		}
	})

	t.Run("detail target year fields", func(t *testing.T) {
		jobs := []models.FFJobIncome{{Label: "Salary", Amount: 2000000, EndYear: 0}}
		oneTime := []models.FFOneTimeExpense{{
			Name: "Trip", Amount: 500000, ExpectedYear: 2028,
		}}
		n, _, rows := ffSimulateReadyToRetire(nil, jobs, expenses, oneTime, y0)
		if n < 0 {
			t.Fatal("expected reachable ready year")
		}
		ry := y0 + n
		d := ffComputeLiveWellDetail(oneTime, y0, rows, &ry)
		if d.TargetYear != 2029 {
			t.Fatalf("target=%d want 2029", d.TargetYear)
		}
		if d.LastOneTimeYear != 2028 {
			t.Fatalf("lastOT=%d want 2028", d.LastOneTimeYear)
		}
		if d.Scenario != ffLiveWellScenarioAfterOT {
			t.Fatalf("scenario=%q", d.Scenario)
		}
	})

	t.Run("unreachable ready zeros live well", func(t *testing.T) {
		oneTime := []models.FFOneTimeExpense{{
			Name: "Trip", Amount: 500000, ExpectedYear: 2028,
		}}
		_, _, rows := ffSimulateReadyToRetire(nil, nil, expenses, oneTime, y0)
		d := ffComputeLiveWellDetail(oneTime, y0, rows, nil)
		if d.Amount != 0 {
			t.Fatalf("fund=%v want 0 when ready is unreachable", d.Amount)
		}
		if d.Message == "" {
			t.Fatal("expected unreachable message")
		}
		if liveWell(nil, nil, expenses, oneTime) != 0 {
			t.Fatal("liveWell helper want 0 when unreachable")
		}
	})

	t.Run("uses ready year when later than year after one-time", func(t *testing.T) {
		assets := []models.FFAsset{{
			Name: "Fund", Value: 5500000, IncomePct: 8, TaxPct: 0,
			IncomeStartYear: y0, Category: models.FFAssetCatMarketEquity,
		}}
		pensionFrom := y0 + 5
		jobs := []models.FFJobIncome{{
			Label: "Pension", Amount: 500000, EndYear: 0,
			PresetKey: strPtr(models.FFJobPensionPreset), StartYear: intPtr(pensionFrom),
		}}
		oneTime := []models.FFOneTimeExpense{{
			Name: "Trip", Amount: 10000, ExpectedYear: y0,
		}}
		n, _, rows := ffSimulateReadyToRetire(assets, jobs, expenses, oneTime, y0)
		if n != 5 {
			t.Fatalf("years=%d want 5", n)
		}
		ry := y0 + n
		target, scenario, label := ffLiveWellTargetYear(oneTime, y0, ry)
		if target != ry {
			t.Fatalf("target=%d want ready year %d (after OT would be %d)", target, ry, y0+1)
		}
		if scenario != ffLiveWellScenarioAfterReady {
			t.Fatalf("scenario=%q want %q", scenario, ffLiveWellScenarioAfterReady)
		}
		if label != "Ready to Retire year" {
			t.Fatalf("label=%q", label)
		}
		row, ok := ffRetireSimRowForYear(rows, target)
		if !ok {
			t.Fatal("missing target row")
		}
		surplus := row.EndIncome - row.TotalExpenses
		today, _, _ := ffSurplusInTodayValue(surplus, rows, y0, target)
		want := today / 2
		if want < 0 {
			want = 0
		}
		got := liveWell(assets, jobs, expenses, oneTime)
		if got != want {
			t.Fatalf("fund=%v want %v", got, want)
		}
	})
}

func TestFFSummaryEndpoint(t *testing.T) {
	_, _, r := ffTestSetup(t)

	w := ffDo(r, http.MethodPost, "/ff/assets", map[string]any{
		"category": "market_equity", "preset_key": "mutual_funds",
		"name": "Debt Fund", "value": 5000000, "is_liquid": true,
		"income_pct": 8, "income_start_year": time.Now().Year(), "tax_pct": 0,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("asset status=%d body=%s", w.Code, w.Body.String())
	}

	w = ffDo(r, http.MethodPost, "/ff/job-income", map[string]any{
		"label": "Salary", "amount": 2000000, "end_year": time.Now().Year() + 10,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("job status=%d body=%s", w.Code, w.Body.String())
	}

	w = ffDo(r, http.MethodGet, "/ff/summary", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("summary status=%d body=%s", w.Code, w.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatalf("json: %v", err)
	}
	if _, ok := payload["metrics"]; !ok {
		t.Fatalf("missing metrics: %v", payload)
	}
	assets, ok := payload["assets"].([]any)
	if !ok || len(assets) < 1 {
		t.Fatalf("assets=%v", payload["assets"])
	}
	// Portfolio sync always upserts the five linked presets (may overwrite MF value to 0).
	foundMF := false
	for _, raw := range assets {
		m, _ := raw.(map[string]any)
		if m["preset_key"] == "mutual_funds" {
			foundMF = true
			break
		}
	}
	if !foundMF {
		t.Fatalf("expected mutual_funds preset in assets: %v", assets)
	}
	sim, ok := payload["retire_simulation"].([]any)
	if !ok || len(sim) < 1 {
		t.Fatalf("retire_simulation=%v", payload["retire_simulation"])
	}
}

func TestFfLiquidityForBreakMonths(t *testing.T) {
	y0 := 2026

	t.Run("liquid plus equity over monthly expenses", func(t *testing.T) {
		assets := []models.FFAsset{
			{Name: "Cash", Value: 600, Category: models.FFAssetCatLiquidCash},
			{Name: "Equity", Value: 1800, Category: models.FFAssetCatMarketEquity},
			{Name: "PF", Value: 99999, Category: models.FFAssetCatPFBonds},
			{Name: "House", Value: 99999, Category: models.FFAssetCatRealEstateGold},
		}
		expenses := []models.FFExpense{{Category: models.FFExpenseRent, Amount: 1200}}
		got := ffLiquidityForBreakMonths(assets, expenses, y0)
		if got == nil {
			t.Fatal("nil months")
		}
		if *got != 24 {
			t.Fatalf("months=%v want 24", *got)
		}
	})

	t.Run("includes digital gold and SGB in the pool", func(t *testing.T) {
		assets := []models.FFAsset{
			{Name: "Cash", Value: 600, Category: models.FFAssetCatLiquidCash},
			{Name: "Equity", Value: 600, Category: models.FFAssetCatMarketEquity},
			{
				Name: "Digital Gold", Value: 600, Category: models.FFAssetCatRealEstateGold,
				PresetKey: strPtr("digital_gold"),
			},
			{
				Name: "SGB", Value: 600, Category: models.FFAssetCatRealEstateGold,
				PresetKey: strPtr("sgb"), IncomePct: 8, IncomeStartYear: y0,
			},
			{
				Name: "Physical Gold", Value: 99999, Category: models.FFAssetCatRealEstateGold,
				PresetKey: strPtr("physical_gold"), IncomePct: 6, IncomeStartYear: y0,
			},
		}
		expenses := []models.FFExpense{{Category: models.FFExpenseRent, Amount: 1200}}
		got := ffLiquidityForBreakMonths(assets, expenses, y0)
		if got == nil {
			t.Fatal("nil months")
		}
		if *got != 24 {
			t.Fatalf("months=%v want 24 (digital gold+SGB in pool; physical gold ignored)", *got)
		}
	})

	t.Run("ignores PF and physical gold income", func(t *testing.T) {
		assets := []models.FFAsset{
			{Name: "Cash", Value: 1200, Category: models.FFAssetCatLiquidCash, IncomeStartYear: y0},
			{
				Name: "PF", Value: 10000, IncomePct: 8, TaxPct: 0,
				IncomeStartYear: y0, Category: models.FFAssetCatPFBonds,
			},
			{
				Name: "Physical Gold", Value: 10000, IncomePct: 6, TaxPct: 0,
				IncomeStartYear: y0, Category: models.FFAssetCatRealEstateGold,
				PresetKey: strPtr("physical_gold"),
			},
		}
		expenses := []models.FFExpense{{Category: models.FFExpenseRent, Amount: 1200}}
		got := ffLiquidityForBreakMonths(assets, expenses, y0)
		if got == nil {
			t.Fatal("nil months")
		}
		if *got != 12 {
			t.Fatalf("months=%v want 12 (PF/physical gold income not extra)", *got)
		}
	})

	t.Run("subtracts rental income from expenses", func(t *testing.T) {
		assets := []models.FFAsset{
			{Name: "Cash", Value: 1200, Category: models.FFAssetCatLiquidCash, IncomeStartYear: y0},
			{
				Name: "Rental", Value: 10000, IncomePct: 2.5, TaxPct: 0,
				IncomeStartYear: y0, Category: models.FFAssetCatRealEstateGold,
				PresetKey: strPtr("commercial_property"),
			},
		}
		expenses := []models.FFExpense{{Category: models.FFExpenseRent, Amount: 1200}}
		got := ffLiquidityForBreakMonths(assets, expenses, y0)
		if got == nil {
			t.Fatal("nil months")
		}
		// extra=250, net=950, months=floor(1200/(950/12))=15
		if *got != 15 {
			t.Fatalf("months=%v want 15", *got)
		}
	})

	t.Run("nil when extra income covers expenses", func(t *testing.T) {
		assets := []models.FFAsset{
			{Name: "Cash", Value: 100, Category: models.FFAssetCatLiquidCash, IncomeStartYear: y0},
			{
				Name: "Rental", Value: 50000, IncomePct: 2.5, TaxPct: 0,
				IncomeStartYear: y0, Category: models.FFAssetCatRealEstateGold,
				PresetKey: strPtr("commercial_property"),
			},
		}
		expenses := []models.FFExpense{{Category: models.FFExpenseRent, Amount: 100}}
		got := ffLiquidityForBreakMonths(assets, expenses, y0)
		if got != nil {
			t.Fatalf("got %v want nil when extra income covers expenses", *got)
		}
	})

	t.Run("floors to whole months", func(t *testing.T) {
		assets := []models.FFAsset{
			{Name: "Cash", Value: 100, Category: models.FFAssetCatLiquidCash},
		}
		expenses := []models.FFExpense{{Category: models.FFExpenseRent, Amount: 90}}
		got := ffLiquidityForBreakMonths(assets, expenses, y0)
		if got == nil {
			t.Fatal("nil months")
		}
		if *got != 13 {
			t.Fatalf("months=%v want 13", *got)
		}
	})

	t.Run("zero expenses returns nil", func(t *testing.T) {
		assets := []models.FFAsset{
			{Name: "Cash", Value: 100, Category: models.FFAssetCatLiquidCash},
		}
		got := ffLiquidityForBreakMonths(assets, nil, y0)
		if got != nil {
			t.Fatalf("got %v want nil", *got)
		}
	})

	t.Run("zero assets returns 0", func(t *testing.T) {
		expenses := []models.FFExpense{{Category: models.FFExpenseRent, Amount: 120}}
		got := ffLiquidityForBreakMonths(nil, expenses, y0)
		if got == nil || *got != 0 {
			t.Fatalf("got %v want 0", got)
		}
	})
}
