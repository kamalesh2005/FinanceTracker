package models

import (
	"strings"
	"time"
)

// FF expense category constants.
const (
	FFExpenseRent                 = "rent"
	FFExpenseHouseHelp            = "house_help"
	FFExpenseUtilities            = "utilities"
	FFExpenseClothesEntertainment = "clothes_entertainment"
	FFExpensePetrolTravel         = "petrol_travel"
	FFExpenseMedicineHealth       = "medicine_health"
	FFExpenseEducation            = "education"
	FFExpenseVacation             = "vacation"
	FFExpenseMisc                 = "misc"
	FFExpenseInsurance            = "insurance_payment"
	FFExpenseEMI                  = "emi"
)

// FF asset category constants.
const (
	FFAssetCatLiquidCash     = "liquid_cash"
	FFAssetCatMarketEquity   = "market_equity"
	FFAssetCatPFBonds        = "pf_bonds"
	FFAssetCatRealEstateGold = "real_estate_gold"
)

// FFAsset is a named personal asset for Financial Freedom planning.
type FFAsset struct {
	ID                   uint      `json:"id" gorm:"primaryKey"`
	UserID               uint      `json:"user_id" gorm:"not null;index"`
	Category             string    `json:"category" gorm:"not null;size:32;index;default:liquid_cash"`
	PresetKey            *string   `json:"preset_key,omitempty" gorm:"size:64;index"`
	Name                 string    `json:"name" gorm:"not null;size:128"`
	Value                float64   `json:"value" gorm:"not null;default:0"`
	IsLiquid             bool      `json:"is_liquid" gorm:"not null;default:false"`
	LinkedLiability      float64   `json:"linked_liability" gorm:"not null;default:0"`
	EmiAmount            float64   `json:"emi_amount" gorm:"not null;default:0"`
	EmiInstallmentsLeft  int       `json:"emi_installments_left" gorm:"not null;default:0"`
	IncomePct            float64   `json:"income_pct" gorm:"not null;default:0"`
	IncomeStartYear      int       `json:"income_start_year" gorm:"not null;default:0"`
	IncomeEndYear        *int      `json:"income_end_year,omitempty"`
	TaxPct               float64   `json:"tax_pct" gorm:"not null;default:0"`
	CreatedAt            time.Time `json:"created_at"`
	UpdatedAt            time.Time `json:"updated_at"`
}

// CalculatedIncome is value × income_pct / 100.
func (a FFAsset) CalculatedIncome() float64 {
	return a.Value * a.IncomePct / 100
}

// EffectiveIncome is calculated income after tax.
func (a FFAsset) EffectiveIncome() float64 {
	return a.CalculatedIncome() * (1 - a.TaxPct/100)
}

// ValidFFAssetCategory reports whether category is one of the fixed FF asset groups.
func ValidFFAssetCategory(c string) bool {
	switch c {
	case FFAssetCatLiquidCash, FFAssetCatMarketEquity, FFAssetCatPFBonds, FFAssetCatRealEstateGold:
		return true
	default:
		return false
	}
}

// FFJobIncome is annual job/salary income. End year is optional; 0 means ongoing.
// Pension rows use preset_key "pension" and start_year instead of end_year.
// Amount is always stored as annual INR; UI may edit monthly (= amount/12).
type FFJobIncome struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	UserID    uint      `json:"user_id" gorm:"not null;uniqueIndex:idx_ff_job_user_preset;index"`
	PresetKey *string   `json:"preset_key,omitempty" gorm:"size:64;uniqueIndex:idx_ff_job_user_preset"`
	Label     string    `json:"label" gorm:"not null;size:128;default:Job"`
	Amount    float64   `json:"amount" gorm:"not null;default:0"`
	EndYear   int       `json:"end_year" gorm:"not null"`
	StartYear *int      `json:"start_year,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

const FFJobPensionPreset = "pension"

// IsFFJobPensionPreset reports whether preset_key is the fixed pension line.
func IsFFJobPensionPreset(key *string) bool {
	if key == nil {
		return false
	}
	return strings.TrimSpace(*key) == FFJobPensionPreset
}

// IsFFJobPension reports whether a job income row is post-retirement pension.
func IsFFJobPension(j FFJobIncome) bool {
	return IsFFJobPensionPreset(j.PresetKey)
}

// FFExpense is a recurring annual expense in a fixed category.
// Amount is always stored as annual INR; UI may edit monthly (= amount/12).
type FFExpense struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	UserID    uint      `json:"user_id" gorm:"not null;uniqueIndex:idx_ff_expense_user_preset;index"`
	PresetKey *string   `json:"preset_key,omitempty" gorm:"size:64;uniqueIndex:idx_ff_expense_user_preset"`
	Category  string    `json:"category" gorm:"not null;size:128;index"`
	Amount    float64   `json:"amount" gorm:"not null;default:0"`
	EndYear   *int      `json:"end_year,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// FFOneTimeExpense is a major one-time expense in an expected year.
type FFOneTimeExpense struct {
	ID           uint      `json:"id" gorm:"primaryKey"`
	UserID       uint      `json:"user_id" gorm:"not null;uniqueIndex:idx_ff_onetime_user_preset;index"`
	PresetKey    *string   `json:"preset_key,omitempty" gorm:"size:64;uniqueIndex:idx_ff_onetime_user_preset"`
	Name         string    `json:"name" gorm:"not null;size:128"`
	Amount       float64   `json:"amount" gorm:"not null;default:0"`
	ExpectedYear int       `json:"expected_year" gorm:"not null;index"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// ValidFFExpensePresetCategory reports whether category is one of the fixed preset slugs.
func ValidFFExpensePresetCategory(c string) bool {
	switch c {
	case FFExpenseRent, FFExpenseHouseHelp, FFExpenseUtilities,
		FFExpenseClothesEntertainment, FFExpensePetrolTravel, FFExpenseMedicineHealth,
		FFExpenseEducation, FFExpenseVacation, FFExpenseMisc, FFExpenseInsurance, FFExpenseEMI:
		return true
	default:
		return false
	}
}

// FFExpenseCategoryForPreset returns the category slug for a preset key.
func FFExpenseCategoryForPreset(key string) (string, bool) {
	switch key {
	case "rent":
		return FFExpenseRent, true
	case "house_help":
		return FFExpenseHouseHelp, true
	case "utilities":
		return FFExpenseUtilities, true
	case "clothes_entertainment":
		return FFExpenseClothesEntertainment, true
	case "petrol_travel":
		return FFExpensePetrolTravel, true
	case "medicine_health":
		return FFExpenseMedicineHealth, true
	case "education":
		return FFExpenseEducation, true
	case "vacation":
		return FFExpenseVacation, true
	case "misc":
		return FFExpenseMisc, true
	case "insurance_payment":
		return FFExpenseInsurance, true
	case "emi":
		return FFExpenseEMI, true
	default:
		return "", false
	}
}

// IsFFExpensePresetRow is true when the row belongs to a fixed preset line.
func IsFFExpensePresetRow(row FFExpense) bool {
	if row.PresetKey != nil && strings.TrimSpace(*row.PresetKey) != "" {
		return true
	}
	return ValidFFExpensePresetCategory(row.Category)
}

// FFDefaultIncomePct returns the portal default return % for a known asset preset key.
func FFDefaultIncomePct(presetKey string) (float64, bool) {
	switch strings.TrimSpace(presetKey) {
	case "savings_bank":
		return 2.5, true
	case "fd", "rd", "liquid_mf":
		return 6, true
	case "stocks_domestic", "stocks_international", "stocks", "mutual_funds", "etf_index":
		return 12, true
	case "epf_ppf", "nps", "govt_bonds":
		return 8, true
	case "primary_residence", "digital_gold":
		return 0, true
	case "commercial_property":
		return 2.5, true
	case "physical_gold":
		return 6, true
	case "sgb":
		return 8, true
	default:
		return 0, false
	}
}

// FFExpenseRequiresEndYear is true for standalone EMI (not asset-linked).
func FFExpenseRequiresEndYear(c string) bool {
	return c == FFExpenseEMI
}
