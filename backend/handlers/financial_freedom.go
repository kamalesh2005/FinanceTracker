package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const ffInflationPct = 6.0

// RegisterFinancialFreedomRoutes mounts FF APIs for any authenticated user.
func RegisterFinancialFreedomRoutes(g *gin.RouterGroup, h *Handler) {
	g.GET("/ff/summary", h.GetFFSummary)

	g.GET("/ff/assets", h.ListFFAssets)
	g.POST("/ff/assets/reset-income-defaults", h.ResetFFAssetIncomeDefaults)
	g.POST("/ff/assets", h.CreateFFAsset)
	g.PUT("/ff/assets/:id", h.UpdateFFAsset)
	g.DELETE("/ff/assets/:id", h.DeleteFFAsset)

	g.GET("/ff/job-income", h.ListFFJobIncome)
	g.POST("/ff/job-income", h.CreateFFJobIncome)
	g.PUT("/ff/job-income/:id", h.UpdateFFJobIncome)
	g.DELETE("/ff/job-income/:id", h.DeleteFFJobIncome)

	g.GET("/ff/expenses", h.ListFFExpenses)
	g.POST("/ff/expenses", h.CreateFFExpense)
	g.PUT("/ff/expenses/:id", h.UpdateFFExpense)
	g.DELETE("/ff/expenses/:id", h.DeleteFFExpense)

	g.GET("/ff/one-time-expenses", h.ListFFOneTimeExpenses)
	g.POST("/ff/one-time-expenses", h.CreateFFOneTimeExpense)
	g.PUT("/ff/one-time-expenses/:id", h.UpdateFFOneTimeExpense)
	g.DELETE("/ff/one-time-expenses/:id", h.DeleteFFOneTimeExpense)
}

func ffAssetJSON(a models.FFAsset) gin.H {
	return gin.H{
		"id":                     a.ID,
		"user_id":                a.UserID,
		"category":               a.Category,
		"preset_key":             a.PresetKey,
		"name":                   a.Name,
		"value":                  a.Value,
		"is_liquid":              a.IsLiquid,
		"linked_liability":       a.LinkedLiability,
		"emi_amount":             a.EmiAmount,
		"emi_installments_left":  a.EmiInstallmentsLeft,
		"income_pct":             a.IncomePct,
		"income_start_year":      a.IncomeStartYear,
		"income_end_year":        a.IncomeEndYear,
		"tax_pct":                a.TaxPct,
		"calculated_income":      a.CalculatedIncome(),
		"effective_income":       a.EffectiveIncome(),
		"created_at":             a.CreatedAt,
		"updated_at":             a.UpdatedAt,
	}
}

func (h *Handler) loadFFData(userID uint) (assets []models.FFAsset, jobs []models.FFJobIncome, expenses []models.FFExpense, oneTime []models.FFOneTimeExpense, err error) {
	if err = h.DB.Where("user_id = ?", userID).Order("id ASC").Find(&assets).Error; err != nil {
		return
	}
	if err = h.DB.Where("user_id = ?", userID).Order("id ASC").Find(&jobs).Error; err != nil {
		return
	}
	if err = h.DB.Where("user_id = ?", userID).Order("id ASC").Find(&expenses).Error; err != nil {
		return
	}
	err = h.DB.Where("user_id = ?", userID).Order("expected_year ASC, id ASC").Find(&oneTime).Error
	return
}

func ffPassiveIncome(assets []models.FFAsset, year int) float64 {
	var sum float64
	for _, a := range assets {
		if a.IncomeStartYear > year {
			continue
		}
		if a.IncomeEndYear != nil && year > *a.IncomeEndYear {
			continue
		}
		sum += a.EffectiveIncome()
	}
	return sum
}

// ffAdjustedIncomePct is return % minus inflation (6%) for non–real-estate/gold assets.
func ffAdjustedIncomePct(a models.FFAsset) float64 {
	if a.Category == models.FFAssetCatRealEstateGold {
		return a.IncomePct
	}
	p := a.IncomePct - ffInflationPct
	if p < 0 {
		return 0
	}
	return p
}

func ffInflationAdjustedEffectiveIncome(a models.FFAsset) float64 {
	return a.Value * ffAdjustedIncomePct(a) / 100 * (1 - a.TaxPct/100)
}

func ffInflationAdjustedPassiveIncome(assets []models.FFAsset, year int) float64 {
	var sum float64
	for _, a := range assets {
		if a.IncomeStartYear > year {
			continue
		}
		if a.IncomeEndYear != nil && year > *a.IncomeEndYear {
			continue
		}
		sum += ffInflationAdjustedEffectiveIncome(a)
	}
	return sum
}

func ffJobIncome(jobs []models.FFJobIncome, year int) float64 {
	var sum float64
	for _, j := range jobs {
		if models.IsFFJobPension(j) {
			if j.StartYear != nil && year >= *j.StartYear {
				sum += j.Amount
			}
			continue
		}
		if year <= j.EndYear {
			sum += j.Amount
		}
	}
	return sum
}

func ffPensionIncome(jobs []models.FFJobIncome, year int) float64 {
	var sum float64
	for _, j := range jobs {
		if !models.IsFFJobPension(j) {
			continue
		}
		if j.StartYear != nil && year >= *j.StartYear {
			sum += j.Amount
		}
	}
	return sum
}

func ffRecurringExpenses(expenses []models.FFExpense, year int) float64 {
	var sum float64
	for _, e := range expenses {
		if e.EndYear != nil && year > *e.EndYear {
			continue
		}
		sum += e.Amount
	}
	return sum
}

// ffOneTimeInYear returns nominal one-time costs due in year.
func ffOneTimeInYear(oneTime []models.FFOneTimeExpense, year int) float64 {
	var sum float64
	for _, o := range oneTime {
		if o.ExpectedYear == year {
			sum += o.Amount
		}
	}
	return sum
}

func ffEMIExpenses(expenses []models.FFExpense, year int) float64 {
	var sum float64
	for _, e := range expenses {
		if e.Category != models.FFExpenseEMI {
			continue
		}
		if e.EndYear != nil && year > *e.EndYear {
			continue
		}
		sum += e.Amount
	}
	return sum
}

// ffAssetEMIForYear returns annual EMI cash outflow from assets in calendar year y0+offset.
// Installments are consumed from the current year forward (12 per year).
func ffAssetEMIForYear(assets []models.FFAsset, y0, year int) float64 {
	var sum float64
	yearsFromNow := year - y0
	if yearsFromNow < 0 {
		return 0
	}
	for _, a := range assets {
		if a.EmiAmount <= 0 || a.EmiInstallmentsLeft <= 0 {
			continue
		}
		startInst := yearsFromNow * 12
		if startInst >= a.EmiInstallmentsLeft {
			continue
		}
		months := a.EmiInstallmentsLeft - startInst
		if months > 12 {
			months = 12
		}
		sum += a.EmiAmount * float64(months)
	}
	return sum
}

// ffLastOneTimeYear is the latest expected_year among one-time rows (0 if none).
func ffLastOneTimeYear(oneTime []models.FFOneTimeExpense) int {
	last := 0
	for _, o := range oneTime {
		if o.ExpectedYear > last {
			last = o.ExpectedYear
		}
	}
	return last
}

func ffCloneAssets(assets []models.FFAsset) []models.FFAsset {
	out := make([]models.FFAsset, len(assets))
	copy(out, assets)
	return out
}

func ffTotalAssetValue(assets []models.FFAsset) float64 {
	var sum float64
	for _, a := range assets {
		sum += a.Value
	}
	return sum
}

// ffAdjustCorpus changes asset values proportionally; positive adds, negative deducts.
// If a deduction exceeds corpus, all asset values go to zero.
func ffAdjustCorpus(assets []models.FFAsset, delta float64) {
	if delta == 0 {
		return
	}
	if delta < 0 {
		ffDeductFromAssets(assets, -delta)
		return
	}
	total := ffTotalAssetValue(assets)
	if total <= 0 {
		if len(assets) == 0 {
			return
		}
		per := delta / float64(len(assets))
		for i := range assets {
			assets[i].Value += per
		}
		return
	}
	for i := range assets {
		assets[i].Value += delta * (assets[i].Value / total)
	}
}

func ffDeductFromAssets(assets []models.FFAsset, amount float64) {
	if amount <= 0 {
		return
	}
	total := ffTotalAssetValue(assets)
	if amount >= total {
		for i := range assets {
			assets[i].Value = 0
		}
		return
	}
	factor := (total - amount) / total
	for i := range assets {
		assets[i].Value *= factor
	}
}

// ffRetireSimRow is one year of the ready-to-retire simulation (amounts in INR, end of year).
type ffRetireSimRow struct {
	Year               int     `json:"year"`
	Corpus             float64 `json:"corpus"`
	PassiveIncome      float64 `json:"passive_income"`
	PassivePct         float64 `json:"passive_pct"`
	ActiveIncome       float64 `json:"active_income"`
	TotalExpenses      float64 `json:"total_expenses"`
	FlagExpenses       float64 `json:"flag_expenses"`
	OneTimeExpense     float64 `json:"one_time_expense"`
	EndIncome          float64 `json:"end_income"`
	IncomeMeetsExpense bool    `json:"income_meets_expense"`
	Ready              bool    `json:"ready"`
}

// ffRetireSimHorizonEndYear is the last calendar year to simulate (inclusive).
func ffRetireSimHorizonEndYear(oneTime []models.FFOneTimeExpense, jobs []models.FFJobIncome, y0 int) int {
	horizon := y0
	if lastOT := ffLastOneTimeYear(oneTime); lastOT > 0 {
		if y := lastOT + 1; y > horizon {
			horizon = y
		}
	}
	if maxEnd, ok := ffMaxJobEndYear(jobs); ok {
		if y := maxEnd + 1; y > horizon {
			horizon = y
		}
	}
	for _, j := range jobs {
		if models.IsFFJobPension(j) && j.StartYear != nil {
			if y := *j.StartYear + 1; y > horizon {
				horizon = y
			}
		}
	}
	return horizon
}

// ffYearsFromReadyRows derives years until ready from per-year Inc≥Exp flags (-1 if unreachable).
func ffYearsFromReadyRows(rows []ffRetireSimRow, y0 int) int {
	if len(rows) == 0 {
		return -1
	}
	last := rows[len(rows)-1]
	if !last.IncomeMeetsExpense {
		return -1
	}
	for i := len(rows) - 1; i >= 0; i-- {
		if !rows[i].IncomeMeetsExpense {
			return rows[i].Year + 1 - y0
		}
	}
	return 0
}

// ffSimulateReadyToRetire runs the year-by-year corpus simulation and returns rows plus
// years until ready (-1 if unreachable).
func ffSimulateReadyToRetire(
	assets []models.FFAsset,
	jobs []models.FFJobIncome,
	expenses []models.FFExpense,
	oneTime []models.FFOneTimeExpense,
	y0 int,
) (years int, simAssets []models.FFAsset, rows []ffRetireSimRow) {
	simAssets = ffCloneAssets(assets)
	horizonEnd := ffRetireSimHorizonEndYear(oneTime, jobs, y0)
	rows = make([]ffRetireSimRow, 0, horizonEnd-y0+1)
	for year := y0; year <= horizonEnd; year++ {
		passive := ffInflationAdjustedPassiveIncome(simAssets, year)
		recurring := ffRecurringExpenses(expenses, year)
		active := ffJobIncome(jobs, year)
		emi := ffAssetEMIForYear(assets, y0, year)
		surplus := passive + active - recurring - emi
		ffAdjustCorpus(simAssets, surplus)
		ot := ffOneTimeInYear(oneTime, year)
		ffDeductFromAssets(simAssets, ot)
		endPassive := ffInflationAdjustedPassiveIncome(simAssets, year)
		endIncome := endPassive + active
		totalExp := recurring + emi + ot
		flagExp := recurring + emi

		corpus := ffTotalAssetValue(simAssets)
		passivePct := 0.0
		if corpus > 0 {
			passivePct = endPassive / corpus * 100
		}

		rows = append(rows, ffRetireSimRow{
			Year:               year,
			Corpus:             corpus,
			PassiveIncome:      endPassive,
			PassivePct:         passivePct,
			ActiveIncome:       active,
			TotalExpenses:      totalExp,
			FlagExpenses:       flagExp,
			OneTimeExpense:     ot,
			EndIncome:          endIncome,
			IncomeMeetsExpense: endIncome >= flagExp,
			Ready:              false,
		})
	}
	years = ffYearsFromReadyRows(rows, y0)
	if years >= 0 {
		readyYear := y0 + years
		for i := range rows {
			if rows[i].Year == readyYear {
				rows[i].Ready = true
				break
			}
		}
	}
	if years < 0 {
		return -1, nil, rows
	}
	return years, simAssets, rows
}

// ffYearsUntilReadyToRetire simulates year-by-year corpus, surplus reinvestment, and
// one-time drawdowns. Returns N in [0, horizon] for the ready year, or -1.
//
// Passive income uses inflation-adjusted returns (return% − 6%) except Real Estate &
// Gold. Expenses and one-time costs are nominal. Ready is derived from the last
// simulated year: if Inc≥Exp fails there, unreachable; otherwise walk backward to
// the latest NO year and ready = that year + 1 (NOW if every year is YES).
// Inc≥Exp compares end income to recurring expenses plus asset EMI only (one-time
// costs still reduce corpus and appear in total_expenses).
func ffYearsUntilReadyToRetire(
	assets []models.FFAsset,
	jobs []models.FFJobIncome,
	expenses []models.FFExpense,
	oneTime []models.FFOneTimeExpense,
	y0 int,
) (int, []models.FFAsset) {
	n, sim, _ := ffSimulateReadyToRetire(assets, jobs, expenses, oneTime, y0)
	return n, sim
}

func ffLiquidNet(assets []models.FFAsset) float64 {
	var sum float64
	for _, a := range assets {
		if !a.IsLiquid {
			continue
		}
		net := a.Value - a.LinkedLiability
		if net < 0 {
			net = 0
		}
		sum += net
	}
	return sum
}

// ffLivingExpenses is recurring expenses excluding the EMI category (EMI is counted in debt).
func ffLivingExpenses(expenses []models.FFExpense, year int) float64 {
	var sum float64
	for _, e := range expenses {
		if e.Category == models.FFExpenseEMI {
			continue
		}
		if e.EndYear != nil && year > *e.EndYear {
			continue
		}
		sum += e.Amount
	}
	return sum
}

// ffDebtOutstanding is remaining EMI principal proxy: asset EMI×months left, plus
// expense EMI annual amount × remaining years (inclusive through end_year).
func ffDebtOutstanding(assets []models.FFAsset, expenses []models.FFExpense, y0 int) float64 {
	var debt float64
	for _, a := range assets {
		if a.EmiAmount <= 0 || a.EmiInstallmentsLeft <= 0 {
			continue
		}
		debt += a.EmiAmount * float64(a.EmiInstallmentsLeft)
	}
	for _, e := range expenses {
		if e.Category != models.FFExpenseEMI {
			continue
		}
		if e.EndYear == nil || *e.EndYear < y0 {
			continue
		}
		yearsLeft := *e.EndYear - y0 + 1
		if yearsLeft <= 0 {
			continue
		}
		debt += e.Amount * float64(yearsLeft)
	}
	return debt
}

// ffInvestmentsForTermCover sums asset values excluding Primary Residence and Physical Gold.
func ffInvestmentsForTermCover(assets []models.FFAsset) float64 {
	var sum float64
	for _, a := range assets {
		if a.PresetKey != nil {
			switch *a.PresetKey {
			case "primary_residence", "physical_gold":
				continue
			}
		}
		sum += a.Value
	}
	return sum
}

func ffMaxJobEndYear(jobs []models.FFJobIncome) (max int, ok bool) {
	for _, j := range jobs {
		if models.IsFFJobPension(j) {
			continue
		}
		if !ok || j.EndYear > max {
			max = j.EndYear
			ok = true
		}
	}
	return max, ok
}

func ffRetireSimRowForYear(rows []ffRetireSimRow, year int) (*ffRetireSimRow, bool) {
	for i := range rows {
		if rows[i].Year == year {
			return &rows[i], true
		}
	}
	return nil, false
}

const (
	ffLiveWellScenarioAfterOT = "after_one_time"
	ffLiveWellHalfDivisor     = 2.0
)

// ffLiveWellYearRow is one year in the Live Well Fund savings breakdown.
type ffLiveWellYearRow struct {
	Year          int     `json:"year"`
	EndIncome     float64 `json:"end_income"`
	TotalExpenses float64 `json:"total_expenses"`
	Savings       float64 `json:"savings"`
	PassivePct    float64 `json:"passive_pct"`
	TodaySavings  float64 `json:"today_savings"`
}

// ffLiveWellDetail is the Live Well Fund calculation breakdown for the UI.
type ffLiveWellDetail struct {
	Scenario        string              `json:"scenario"`
	ScenarioLabel   string              `json:"scenario_label"`
	Amount          float64             `json:"amount"`
	TargetYear      int                 `json:"target_year"`
	LastOneTimeYear int                 `json:"last_one_time_year,omitempty"`
	TotalSavings    float64             `json:"total_savings,omitempty"`
	TodaySurplus    float64             `json:"today_surplus,omitempty"`
	PassivePct      float64             `json:"passive_pct,omitempty"`
	DiscountYears   int                 `json:"discount_years,omitempty"`
	YearRows        []ffLiveWellYearRow `json:"year_rows"`
	Message         string              `json:"message,omitempty"`
}

// ffSurplusInTodayValue discounts a future-year surplus to today's money using each
// simulated year's P/Corpus % (passive_pct) from y0+1 through targetYear.
func ffSurplusInTodayValue(surplus float64, simRows []ffRetireSimRow, y0, targetYear int) (today float64, passivePct float64, discountYears int) {
	discountYears = targetYear - y0
	if surplus <= 0 {
		return 0, 0, discountYears
	}
	if discountYears <= 0 {
		row, ok := ffRetireSimRowForYear(simRows, targetYear)
		if ok {
			passivePct = row.PassivePct
		}
		return surplus, passivePct, 0
	}
	factor := 1.0
	for year := y0 + 1; year <= targetYear; year++ {
		row, ok := ffRetireSimRowForYear(simRows, year)
		if !ok {
			continue
		}
		if year == targetYear {
			passivePct = row.PassivePct
		}
		factor *= 1 + row.PassivePct/100
	}
	return surplus / factor, passivePct, discountYears
}

// ffLiveWellTargetYear is the first year after all scheduled one-time expenses (y0 if none).
func ffLiveWellTargetYear(oneTime []models.FFOneTimeExpense, y0 int) int {
	if lastOT := ffLastOneTimeYear(oneTime); lastOT > 0 {
		return lastOT + 1
	}
	return y0
}

// ffComputeLiveWellDetail: surplus in the target year after the last one-time expense,
// discounted to today's money using P/Corpus % from the retire simulation, then ÷ 2.
func ffComputeLiveWellDetail(
	oneTime []models.FFOneTimeExpense,
	y0 int,
	simRows []ffRetireSimRow,
) ffLiveWellDetail {
	targetYear := ffLiveWellTargetYear(oneTime, y0)
	lastOT := ffLastOneTimeYear(oneTime)
	label := "Year after last one-time expense"
	if lastOT == 0 {
		label = "Current year (no one-time expenses scheduled)"
	}
	d := ffLiveWellDetail{
		Scenario:        ffLiveWellScenarioAfterOT,
		ScenarioLabel:   label,
		TargetYear:      targetYear,
		LastOneTimeYear: lastOT,
	}
	row, ok := ffRetireSimRowForYear(simRows, targetYear)
	if !ok {
		d.Message = "No simulation row for the target year."
		return d
	}
	surplus := row.EndIncome - row.TotalExpenses
	todaySurplus, passivePct, discountYears := ffSurplusInTodayValue(surplus, simRows, y0, targetYear)
	d.YearRows = []ffLiveWellYearRow{{
		Year:          row.Year,
		EndIncome:     row.EndIncome,
		TotalExpenses: row.TotalExpenses,
		Savings:       surplus,
		PassivePct:    passivePct,
		TodaySavings:  todaySurplus,
	}}
	d.TotalSavings = surplus
	d.TodaySurplus = todaySurplus
	d.PassivePct = passivePct
	d.DiscountYears = discountYears
	fund := todaySurplus / ffLiveWellHalfDivisor
	if fund < 0 {
		fund = 0
	}
	d.Amount = fund
	return d
}

func ffLiveWellFund(
	oneTime []models.FFOneTimeExpense,
	y0 int,
	simRows []ffRetireSimRow,
) float64 {
	return ffComputeLiveWellDetail(oneTime, y0, simRows).Amount
}

// ffTermInsuranceNeed applies the 15/75 rule:
// Cover = Debt + 15 × (75% of living expenses) − Investments (floored at 0).
func ffTermInsuranceNeed(assets []models.FFAsset, expenses []models.FFExpense, y0 int) float64 {
	debt := ffDebtOutstanding(assets, expenses, y0)
	expenseCover := 15.0 * 0.75 * ffLivingExpenses(expenses, y0)
	investments := ffInvestmentsForTermCover(assets)
	need := debt + expenseCover - investments
	if need < 0 {
		return 0
	}
	return need
}

type ffMetrics struct {
	ActiveIncome        float64  `json:"active_income"`
	PassiveIncome       float64  `json:"passive_income"`
	RegularExpenses     float64  `json:"regular_expenses"`
	RetirementYear      *int     `json:"retirement_year"`
	YearsToRetire       *int     `json:"years_to_retire"`
	AnnualEnjoymentFund *float64 `json:"annual_enjoyment_fund"`
	TermInsuranceNeed   float64  `json:"term_insurance_need"`
	CurrentYear         int      `json:"current_year"`
}

func computeFFMetrics(assets []models.FFAsset, jobs []models.FFJobIncome, expenses []models.FFExpense, oneTime []models.FFOneTimeExpense, y0 int) (ffMetrics, ffLiveWellDetail) {
	m := ffMetrics{
		CurrentYear:     y0,
		ActiveIncome:    ffJobIncome(jobs, y0),
		PassiveIncome:   ffPassiveIncome(assets, y0),
		RegularExpenses: ffRecurringExpenses(expenses, y0),
	}

	n, _, simRows := ffSimulateReadyToRetire(assets, jobs, expenses, oneTime, y0)
	if n >= 0 {
		ry := y0 + n
		m.RetirementYear = &ry
		m.YearsToRetire = &n
	}
	liveWell := ffComputeLiveWellDetail(oneTime, y0, simRows)
	m.AnnualEnjoymentFund = &liveWell.Amount

	m.TermInsuranceNeed = ffTermInsuranceNeed(assets, expenses, y0)
	return m, liveWell
}

func (h *Handler) GetFFSummary(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	if err := h.syncFFAssetsFromPortfolio(userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to sync portfolio assets"})
		return
	}
	assets, jobs, expenses, oneTime, err := h.loadFFData(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load data"})
		return
	}
	y0 := time.Now().Year()
	metrics, liveWell := computeFFMetrics(assets, jobs, expenses, oneTime, y0)
	_, _, simRows := ffSimulateReadyToRetire(assets, jobs, expenses, oneTime, y0)
	simRows = ffTrimRetireSimRows(simRows, jobs, oneTime, metrics.RetirementYear, y0)

	assetJSON := make([]gin.H, 0, len(assets))
	for _, a := range assets {
		assetJSON = append(assetJSON, ffAssetJSON(a))
	}
	c.JSON(http.StatusOK, gin.H{
		"assets":             assetJSON,
		"job_income":         jobs,
		"expenses":           expenses,
		"one_time_expenses":  oneTime,
		"metrics":            metrics,
		"retire_simulation":  simRows,
		"live_well_detail":   liveWell,
	})
}

// ffTrimRetireSimRows limits table length for UI while covering horizon and ready year.
func ffTrimRetireSimRows(rows []ffRetireSimRow, jobs []models.FFJobIncome, oneTime []models.FFOneTimeExpense, retireYear *int, y0 int) []ffRetireSimRow {
	if len(rows) == 0 {
		return rows
	}
	maxYear := ffRetireSimHorizonEndYear(oneTime, jobs, y0) + 2
	if retireYear != nil && *retireYear+2 > maxYear {
		maxYear = *retireYear + 2
	}
	lastIdx := len(rows) - 1
	for i, r := range rows {
		if r.Year > maxYear {
			lastIdx = i - 1
			break
		}
	}
	if lastIdx < 0 {
		lastIdx = 0
	}
	return rows[:lastIdx+1]
}

// --- Assets ---

type ffAssetRequest struct {
	Category            string  `json:"category" binding:"required"`
	PresetKey           *string `json:"preset_key"`
	Name                string  `json:"name" binding:"required"`
	Value               float64 `json:"value"`
	IsLiquid            bool    `json:"is_liquid"`
	LinkedLiability     float64 `json:"linked_liability"`
	EmiAmount           float64 `json:"emi_amount"`
	EmiInstallmentsLeft int     `json:"emi_installments_left"`
	IncomePct           float64 `json:"income_pct"`
	IncomeStartYear     int     `json:"income_start_year" binding:"required"`
	IncomeEndYear       *int    `json:"income_end_year"`
	TaxPct              float64 `json:"tax_pct"`
}

func normalizeFFAssetRequest(req *ffAssetRequest) string {
	if !models.ValidFFAssetCategory(req.Category) {
		return "invalid category"
	}
	if req.PresetKey != nil {
		key := strings.TrimSpace(*req.PresetKey)
		if key == "" {
			req.PresetKey = nil
		} else {
			req.PresetKey = &key
		}
	}
	if req.IncomeEndYear != nil && *req.IncomeEndYear < req.IncomeStartYear {
		return "income_end_year must be >= income_start_year"
	}
	return ""
}

func (h *Handler) ListFFAssets(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var rows []models.FFAsset
	if err := h.DB.Where("user_id = ?", userID).Order("id ASC").Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list assets"})
		return
	}
	out := make([]gin.H, 0, len(rows))
	for _, a := range rows {
		out = append(out, ffAssetJSON(a))
	}
	c.JSON(http.StatusOK, out)
}

func (h *Handler) ResetFFAssetIncomeDefaults(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var rows []models.FFAsset
	if err := h.DB.Where("user_id = ?", userID).Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load assets"})
		return
	}
	updated := 0
	for i := range rows {
		if rows[i].PresetKey == nil {
			continue
		}
		key := strings.TrimSpace(*rows[i].PresetKey)
		if key == "" {
			continue
		}
		pct, ok := models.FFDefaultIncomePct(key)
		if !ok {
			continue
		}
		if rows[i].IncomePct == pct {
			continue
		}
		if err := h.DB.Model(&rows[i]).Update("income_pct", pct).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reset income defaults"})
			return
		}
		updated++
	}
	c.JSON(http.StatusOK, gin.H{"updated": updated})
}

func (h *Handler) CreateFFAsset(c *gin.Context) {
	var req ffAssetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if msg := normalizeFFAssetRequest(&req); msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	userID := middleware.CurrentUserID(c)
	row := models.FFAsset{
		UserID:              userID,
		Category:            req.Category,
		PresetKey:           req.PresetKey,
		Name:                req.Name,
		Value:               req.Value,
		IsLiquid:            req.IsLiquid,
		LinkedLiability:     req.LinkedLiability,
		EmiAmount:           req.EmiAmount,
		EmiInstallmentsLeft: req.EmiInstallmentsLeft,
		IncomePct:           req.IncomePct,
		IncomeStartYear:     req.IncomeStartYear,
		IncomeEndYear:       req.IncomeEndYear,
		TaxPct:              req.TaxPct,
	}
	if err := h.DB.Create(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create asset"})
		return
	}
	c.JSON(http.StatusCreated, ffAssetJSON(row))
}

func (h *Handler) UpdateFFAsset(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	userID := middleware.CurrentUserID(c)
	var row models.FFAsset
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&row).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "asset not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load asset"})
		return
	}
	var req ffAssetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if msg := normalizeFFAssetRequest(&req); msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	row.Category = req.Category
	row.PresetKey = req.PresetKey
	row.Name = req.Name
	row.Value = req.Value
	row.IsLiquid = req.IsLiquid
	row.LinkedLiability = req.LinkedLiability
	row.EmiAmount = req.EmiAmount
	row.EmiInstallmentsLeft = req.EmiInstallmentsLeft
	row.IncomePct = req.IncomePct
	row.IncomeStartYear = req.IncomeStartYear
	row.IncomeEndYear = req.IncomeEndYear
	row.TaxPct = req.TaxPct
	if err := h.DB.Model(&row).Select(
		"category", "preset_key", "name", "value", "is_liquid", "linked_liability",
		"emi_amount", "emi_installments_left",
		"income_pct", "income_start_year", "income_end_year", "tax_pct",
	).Updates(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update asset"})
		return
	}
	c.JSON(http.StatusOK, ffAssetJSON(row))
}

func (h *Handler) DeleteFFAsset(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	userID := middleware.CurrentUserID(c)
	var row models.FFAsset
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&row).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "asset not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load asset"})
		return
	}
	if row.PresetKey != nil && ffIsPortfolioSyncedPreset(*row.PresetKey) {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "this asset is synced from Stocks & Mutual Funds and cannot be deleted",
		})
		return
	}
	res := h.DB.Delete(&row)
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete asset"})
		return
	}
	c.Status(http.StatusNoContent)
}

// --- Job income ---

type ffJobIncomeRequest struct {
	PresetKey *string `json:"preset_key"`
	Label     string  `json:"label"`
	Amount    float64 `json:"amount"`
	EndYear   *int    `json:"end_year"`
	StartYear *int    `json:"start_year"`
}

func validateFFJobIncome(req *ffJobIncomeRequest) string {
	if models.IsFFJobPensionPreset(req.PresetKey) {
		if req.StartYear == nil {
			return "start_year is required for pension"
		}
		return ""
	}
	if req.EndYear == nil {
		return "end_year is required"
	}
	return ""
}

func normalizeFFJobPreset(req *ffJobIncomeRequest) {
	if req.PresetKey != nil {
		key := strings.TrimSpace(*req.PresetKey)
		if key == "" {
			req.PresetKey = nil
		} else {
			req.PresetKey = &key
		}
	}
}

func (h *Handler) ListFFJobIncome(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var rows []models.FFJobIncome
	if err := h.DB.Where("user_id = ?", userID).Order("id ASC").Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list job income"})
		return
	}
	c.JSON(http.StatusOK, rows)
}

func (h *Handler) CreateFFJobIncome(c *gin.Context) {
	var req ffJobIncomeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	normalizeFFJobPreset(&req)
	if msg := validateFFJobIncome(&req); msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	userID := middleware.CurrentUserID(c)
	if req.PresetKey != nil {
		var existing int64
		if err := h.DB.Model(&models.FFJobIncome{}).
			Where("user_id = ? AND preset_key = ?", userID, *req.PresetKey).
			Count(&existing).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create job income"})
			return
		}
		if existing > 0 {
			c.JSON(http.StatusConflict, gin.H{"error": "preset job income already exists"})
			return
		}
	}
	label := req.Label
	if label == "" {
		if models.IsFFJobPensionPreset(req.PresetKey) {
			label = "Pension"
		} else {
			label = "Salary"
		}
	}
	row := models.FFJobIncome{
		UserID:    userID,
		PresetKey: req.PresetKey,
		Label:     label,
		Amount:    req.Amount,
	}
	if models.IsFFJobPensionPreset(req.PresetKey) {
		row.StartYear = req.StartYear
		row.EndYear = 0
	} else {
		row.EndYear = *req.EndYear
	}
	if err := h.DB.Create(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create job income"})
		return
	}
	c.JSON(http.StatusCreated, row)
}

func (h *Handler) UpdateFFJobIncome(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	userID := middleware.CurrentUserID(c)
	var row models.FFJobIncome
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&row).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "job income not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load job income"})
		return
	}
	var req ffJobIncomeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	normalizeFFJobPreset(&req)
	if msg := validateFFJobIncome(&req); msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	if req.PresetKey != nil {
		var existing int64
		if err := h.DB.Model(&models.FFJobIncome{}).
			Where("user_id = ? AND preset_key = ? AND id <> ?", userID, *req.PresetKey, id).
			Count(&existing).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update job income"})
			return
		}
		if existing > 0 {
			c.JSON(http.StatusConflict, gin.H{"error": "preset job income already exists"})
			return
		}
	}
	label := req.Label
	if label == "" {
		if models.IsFFJobPensionPreset(req.PresetKey) {
			label = "Pension"
		} else {
			label = "Salary"
		}
	}
	row.PresetKey = req.PresetKey
	row.Label = label
	row.Amount = req.Amount
	if models.IsFFJobPensionPreset(req.PresetKey) {
		row.StartYear = req.StartYear
		row.EndYear = 0
	} else {
		row.EndYear = *req.EndYear
		row.StartYear = nil
	}
	if err := h.DB.Model(&row).Select("preset_key", "label", "amount", "end_year", "start_year").Updates(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update job income"})
		return
	}
	c.JSON(http.StatusOK, row)
}

func (h *Handler) DeleteFFJobIncome(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	userID := middleware.CurrentUserID(c)
	res := h.DB.Where("id = ? AND user_id = ?", id, userID).Delete(&models.FFJobIncome{})
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete job income"})
		return
	}
	if res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "job income not found"})
		return
	}
	c.Status(http.StatusNoContent)
}

// --- Expenses ---

type ffExpenseRequest struct {
	PresetKey *string `json:"preset_key"`
	Category  string  `json:"category" binding:"required"`
	Amount    float64 `json:"amount"`
	EndYear   *int    `json:"end_year"`
}

func validateFFExpense(req *ffExpenseRequest) string {
	req.Category = strings.TrimSpace(req.Category)
	if req.Category == "" {
		return "category is required"
	}
	if len(req.Category) > 128 {
		return "category too long"
	}
	if req.PresetKey != nil {
		key := strings.TrimSpace(*req.PresetKey)
		if key == "" {
			req.PresetKey = nil
		} else {
			req.PresetKey = &key
			expected, ok := models.FFExpenseCategoryForPreset(key)
			if !ok {
				return "invalid preset_key"
			}
			if req.Category != expected {
				return "category does not match preset"
			}
		}
	}
	if models.FFExpenseRequiresEndYear(req.Category) && req.EndYear == nil {
		return "end_year is required for emi"
	}
	return ""
}

func (h *Handler) ListFFExpenses(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var rows []models.FFExpense
	if err := h.DB.Where("user_id = ?", userID).Order("id ASC").Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list expenses"})
		return
	}
	c.JSON(http.StatusOK, rows)
}

func (h *Handler) CreateFFExpense(c *gin.Context) {
	var req ffExpenseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if msg := validateFFExpense(&req); msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	userID := middleware.CurrentUserID(c)
	if req.PresetKey != nil {
		var existing int64
		if err := h.DB.Model(&models.FFExpense{}).
			Where("user_id = ? AND preset_key = ?", userID, *req.PresetKey).
			Count(&existing).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create expense"})
			return
		}
		if existing > 0 {
			c.JSON(http.StatusConflict, gin.H{"error": "preset expense already exists"})
			return
		}
	}
	row := models.FFExpense{
		UserID:    userID,
		PresetKey: req.PresetKey,
		Category:  req.Category,
		Amount:    req.Amount,
		EndYear:   req.EndYear,
	}
	if err := h.DB.Create(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create expense"})
		return
	}
	c.JSON(http.StatusCreated, row)
}

func (h *Handler) UpdateFFExpense(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	userID := middleware.CurrentUserID(c)
	var row models.FFExpense
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&row).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "expense not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load expense"})
		return
	}
	var req ffExpenseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if msg := validateFFExpense(&req); msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	if req.PresetKey != nil {
		var existing int64
		if err := h.DB.Model(&models.FFExpense{}).
			Where("user_id = ? AND preset_key = ? AND id <> ?", userID, *req.PresetKey, id).
			Count(&existing).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update expense"})
			return
		}
		if existing > 0 {
			c.JSON(http.StatusConflict, gin.H{"error": "preset expense already exists"})
			return
		}
	}
	row.PresetKey = req.PresetKey
	row.Category = req.Category
	row.Amount = req.Amount
	row.EndYear = req.EndYear
	if err := h.DB.Model(&row).Select("preset_key", "category", "amount", "end_year").Updates(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update expense"})
		return
	}
	c.JSON(http.StatusOK, row)
}

func (h *Handler) DeleteFFExpense(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	userID := middleware.CurrentUserID(c)
	var row models.FFExpense
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&row).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "expense not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load expense"})
		return
	}
	if models.IsFFExpensePresetRow(row) {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot delete preset expense"})
		return
	}
	res := h.DB.Delete(&row)
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete expense"})
		return
	}
	c.Status(http.StatusNoContent)
}

// --- One-time expenses ---

type ffOneTimeRequest struct {
	PresetKey    *string `json:"preset_key"`
	Name         string  `json:"name" binding:"required"`
	Amount       float64 `json:"amount"`
	ExpectedYear int     `json:"expected_year" binding:"required"`
}

func normalizeFFOneTimeRequest(req *ffOneTimeRequest) {
	if req.PresetKey != nil {
		key := strings.TrimSpace(*req.PresetKey)
		if key == "" {
			req.PresetKey = nil
		} else {
			req.PresetKey = &key
		}
	}
}

func (h *Handler) ListFFOneTimeExpenses(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var rows []models.FFOneTimeExpense
	if err := h.DB.Where("user_id = ?", userID).Order("expected_year ASC, id ASC").Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list one-time expenses"})
		return
	}
	c.JSON(http.StatusOK, rows)
}

func (h *Handler) CreateFFOneTimeExpense(c *gin.Context) {
	var req ffOneTimeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	normalizeFFOneTimeRequest(&req)
	userID := middleware.CurrentUserID(c)
	if req.PresetKey != nil {
		var existing int64
		if err := h.DB.Model(&models.FFOneTimeExpense{}).
			Where("user_id = ? AND preset_key = ?", userID, *req.PresetKey).
			Count(&existing).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create one-time expense"})
			return
		}
		if existing > 0 {
			c.JSON(http.StatusConflict, gin.H{"error": "preset one-time expense already exists"})
			return
		}
	}
	row := models.FFOneTimeExpense{
		UserID:       userID,
		PresetKey:    req.PresetKey,
		Name:         req.Name,
		Amount:       req.Amount,
		ExpectedYear: req.ExpectedYear,
	}
	if err := h.DB.Create(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create one-time expense"})
		return
	}
	c.JSON(http.StatusCreated, row)
}

func (h *Handler) UpdateFFOneTimeExpense(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	userID := middleware.CurrentUserID(c)
	var row models.FFOneTimeExpense
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&row).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "one-time expense not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load one-time expense"})
		return
	}
	var req ffOneTimeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	normalizeFFOneTimeRequest(&req)
	if req.PresetKey != nil {
		var existing int64
		if err := h.DB.Model(&models.FFOneTimeExpense{}).
			Where("user_id = ? AND preset_key = ? AND id <> ?", userID, *req.PresetKey, id).
			Count(&existing).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update one-time expense"})
			return
		}
		if existing > 0 {
			c.JSON(http.StatusConflict, gin.H{"error": "preset one-time expense already exists"})
			return
		}
	}
	row.PresetKey = req.PresetKey
	row.Name = req.Name
	row.Amount = req.Amount
	row.ExpectedYear = req.ExpectedYear
	if err := h.DB.Model(&row).Select("preset_key", "name", "amount", "expected_year").Updates(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update one-time expense"})
		return
	}
	c.JSON(http.StatusOK, row)
}

func (h *Handler) DeleteFFOneTimeExpense(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	userID := middleware.CurrentUserID(c)
	res := h.DB.Where("id = ? AND user_id = ?", id, userID).Delete(&models.FFOneTimeExpense{})
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete one-time expense"})
		return
	}
	if res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "one-time expense not found"})
		return
	}
	c.Status(http.StatusNoContent)
}
