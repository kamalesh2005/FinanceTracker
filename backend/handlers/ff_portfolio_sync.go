package handlers

import (
	"math"
	"strings"
	"time"

	"financetracker/models"

	"gorm.io/gorm"
)

// Portfolio-synced FF asset presets (values stored in ₹ thousands / K).
const (
	ffPresetDigitalGold    = "digital_gold"
	ffPresetSGB            = "sgb"
	ffPresetETFIndex       = "etf_index"
	ffPresetStocksDomestic = "stocks_domestic"
	ffPresetMutualFunds    = "mutual_funds"
	ffPresetStocksLegacy   = "stocks"
)

const (
	ffIndustryGoldSilver = "Gold & Silver"
	ffIndustrySGB        = "SGB"
	ffIndustryETF        = "ETF"
)

type ffPortfolioBucket struct {
	PresetKey  string
	Category   string
	Name       string
	IncomePct  float64
	IsLiquid   bool
	ValueRupee float64
}

func ffRupeesToK(rupees float64) float64 {
	if rupees == 0 {
		return 0
	}
	return math.Round(rupees/10) / 100 // /1000, 2 decimal places
}

// ffClassifyStockBucket maps a holding to an FF preset key.
// Direct Stocks — International is manual (not classified here).
func ffClassifyStockBucket(industry, isin string) string {
	_ = isin
	ind := strings.TrimSpace(industry)
	if strings.EqualFold(ind, ffIndustryGoldSilver) {
		return ffPresetDigitalGold
	}
	if strings.EqualFold(ind, ffIndustrySGB) {
		return ffPresetSGB
	}
	if strings.EqualFold(ind, ffIndustryETF) {
		return ffPresetETFIndex
	}
	return ffPresetStocksDomestic
}

func ffIsPortfolioSyncedPreset(presetKey string) bool {
	switch strings.TrimSpace(presetKey) {
	case ffPresetDigitalGold, ffPresetSGB, ffPresetETFIndex, ffPresetStocksDomestic, ffPresetMutualFunds:
		return true
	default:
		return false
	}
}

func computeFFPortfolioBuckets(db *gorm.DB, userID uint) (map[string]float64, error) {
	totals := map[string]float64{
		ffPresetDigitalGold:    0,
		ffPresetSGB:            0,
		ffPresetETFIndex:       0,
		ffPresetStocksDomestic: 0,
		ffPresetMutualFunds:    0,
	}

	var positions []models.UserStock
	if err := db.Where("user_id = ? AND quantity > 0", userID).Find(&positions).Error; err != nil {
		return nil, err
	}
	if len(positions) > 0 {
		stockIDs := make([]uint, 0, len(positions))
		seen := map[uint]struct{}{}
		for _, p := range positions {
			if _, ok := seen[p.StockID]; ok {
				continue
			}
			seen[p.StockID] = struct{}{}
			stockIDs = append(stockIDs, p.StockID)
		}
		var stocks []models.Stock
		if err := db.Where("id IN ?", stockIDs).Find(&stocks).Error; err != nil {
			return nil, err
		}
		byID := make(map[uint]models.Stock, len(stocks))
		for _, s := range stocks {
			byID[s.ID] = s
		}
		for _, p := range positions {
			s, ok := byID[p.StockID]
			if !ok {
				continue
			}
			key := ffClassifyStockBucket(s.Industry, s.ISIN)
			totals[key] += p.Quantity * s.CurrentPrice
		}
	}

	var mfs []models.MutualFund
	if err := db.Where("user_id = ? AND quantity > 0", userID).Find(&mfs).Error; err != nil {
		return nil, err
	}
	enrichUserMutualFundsNAV(db, mfs)
	for _, mf := range mfs {
		nav := mf.CurrentNAV
		if nav <= 0 {
			nav = mf.NAV
		}
		totals[ffPresetMutualFunds] += mf.Quantity * nav
	}

	return totals, nil
}

func migrateLegacyFFStocksPreset(db *gorm.DB, userID uint) error {
	var domestic int64
	if err := db.Model(&models.FFAsset{}).
		Where("user_id = ? AND preset_key = ?", userID, ffPresetStocksDomestic).
		Count(&domestic).Error; err != nil {
		return err
	}
	if domestic == 0 {
		return db.Model(&models.FFAsset{}).
			Where("user_id = ? AND preset_key = ?", userID, ffPresetStocksLegacy).
			Update("preset_key", ffPresetStocksDomestic).Error
	}
	return db.Where("user_id = ? AND preset_key = ?", userID, ffPresetStocksLegacy).
		Delete(&models.FFAsset{}).Error
}

func upsertFFPortfolioAsset(
	db *gorm.DB,
	userID uint,
	presetKey, category, name string,
	incomePct float64,
	isLiquid bool,
	valueK float64,
) error {
	var rows []models.FFAsset
	if err := db.Where("user_id = ? AND preset_key = ?", userID, presetKey).
		Order("id ASC").Find(&rows).Error; err != nil {
		return err
	}
	if len(rows) == 0 {
		key := presetKey
		row := models.FFAsset{
			UserID:          userID,
			Category:        category,
			PresetKey:       &key,
			Name:            name,
			Value:           valueK,
			IsLiquid:        isLiquid,
			IncomePct:       incomePct,
			IncomeStartYear: time.Now().Year(),
		}
		return db.Create(&row).Error
	}
	row := rows[0]
	return db.Model(&row).Updates(map[string]any{
		"value": valueK,
		"name":  name,
	}).Error
}

// syncFFAssetsFromPortfolio fills Digital Gold, SGB, ETF+Index, Direct Stocks
// (domestic), and Mutual Funds from main-portal holdings.
// Amounts are written in ₹ thousands (K). International stocks are manual.
func (h *Handler) syncFFAssetsFromPortfolio(userID uint) error {
	return h.DB.Transaction(func(tx *gorm.DB) error {
		if err := migrateLegacyFFStocksPreset(tx, userID); err != nil {
			return err
		}
		totals, err := computeFFPortfolioBuckets(tx, userID)
		if err != nil {
			return err
		}

		defs := []ffPortfolioBucket{
			{
				PresetKey:  ffPresetDigitalGold,
				Category:   models.FFAssetCatRealEstateGold,
				Name:       "Digital Gold",
				IncomePct:  0,
				IsLiquid:   false,
				ValueRupee: totals[ffPresetDigitalGold],
			},
			{
				PresetKey:  ffPresetSGB,
				Category:   models.FFAssetCatRealEstateGold,
				Name:       "Sovereign Gold Bonds (SGBs)",
				IncomePct:  8,
				IsLiquid:   false,
				ValueRupee: totals[ffPresetSGB],
			},
			{
				PresetKey:  ffPresetETFIndex,
				Category:   models.FFAssetCatMarketEquity,
				Name:       "ETFs + Index Funds",
				IncomePct:  12,
				IsLiquid:   false,
				ValueRupee: totals[ffPresetETFIndex],
			},
			{
				PresetKey:  ffPresetStocksDomestic,
				Category:   models.FFAssetCatMarketEquity,
				Name:       "Direct Stocks — Domestic",
				IncomePct:  12,
				IsLiquid:   false,
				ValueRupee: totals[ffPresetStocksDomestic],
			},
			{
				PresetKey:  ffPresetMutualFunds,
				Category:   models.FFAssetCatMarketEquity,
				Name:       "Mutual Funds",
				IncomePct:  12,
				IsLiquid:   false,
				ValueRupee: totals[ffPresetMutualFunds],
			},
		}

		for _, d := range defs {
			if err := upsertFFPortfolioAsset(
				tx,
				userID,
				d.PresetKey,
				d.Category,
				d.Name,
				d.IncomePct,
				d.IsLiquid,
				ffRupeesToK(d.ValueRupee),
			); err != nil {
				return err
			}
		}
		return nil
	})
}
