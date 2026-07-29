package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"

	"financetracker/middleware"
	"financetracker/models"
	"financetracker/recrules"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const stockColumnDelimiter = "|"
const defaultRecommendationFluctuationPct = 5.0

func splitHiddenStockColumns(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return []string{}
	}
	parts := strings.Split(raw, stockColumnDelimiter)
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func joinHiddenStockColumns(cols []string) string {
	cleaned := make([]string, 0, len(cols))
	seen := map[string]struct{}{}
	for _, c := range cols {
		c = strings.TrimSpace(c)
		if c == "" {
			continue
		}
		if _, ok := seen[c]; ok {
			continue
		}
		seen[c] = struct{}{}
		cleaned = append(cleaned, c)
	}
	return strings.Join(cleaned, stockColumnDelimiter)
}

func (h *Handler) GetStockColumnConfig(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var cfg models.UserConfig
	err := h.DB.Where("user_id = ?", userID).First(&cfg).Error
	if err == gorm.ErrRecordNotFound {
		c.JSON(http.StatusOK, gin.H{"hidden_columns": []string{}})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"hidden_columns": splitHiddenStockColumns(cfg.HiddenStockColumns)})
}

func (h *Handler) PutStockColumnConfig(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var req struct {
		HiddenColumns []string `json:"hidden_columns"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.HiddenColumns == nil {
		req.HiddenColumns = []string{}
	}
	joined := joinHiddenStockColumns(req.HiddenColumns)

	var cfg models.UserConfig
	err := h.DB.Where("user_id = ?", userID).First(&cfg).Error
	if err == gorm.ErrRecordNotFound {
		cfg = models.UserConfig{
			UserID:             userID,
			HiddenStockColumns: joined,
		}
		if err := h.DB.Create(&cfg).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	} else {
		cfg.HiddenStockColumns = joined
		if err := h.DB.Save(&cfg).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	c.JSON(http.StatusOK, gin.H{"hidden_columns": splitHiddenStockColumns(cfg.HiddenStockColumns)})
}

// EnsureAppConfig seeds singleton App_Config id=1 with current recommendation rules.
func EnsureAppConfig(db *gorm.DB) error {
	var cfg models.AppConfig
	err := db.First(&cfg, 1).Error
	if err == gorm.ErrRecordNotFound {
		fluct := defaultRecommendationFluctuationPct
		rs := recrules.DefaultRuleset(fluct)
		raw, mErr := rs.Marshal()
		if mErr != nil {
			return mErr
		}
		cfg = models.AppConfig{
			ID:                                  1,
			DefaultRecommendationFluctuationPct: fluct,
			RecommendationRulesJSON:             raw,
		}
		return db.Create(&cfg).Error
	}
	if err != nil {
		return err
	}
	// Backfill rules JSON for existing App_Config rows.
	if strings.TrimSpace(cfg.RecommendationRulesJSON) == "" {
		fluct := cfg.DefaultRecommendationFluctuationPct
		if fluct <= 0 {
			fluct = defaultRecommendationFluctuationPct
		}
		rs := recrules.DefaultRuleset(fluct)
		raw, mErr := rs.Marshal()
		if mErr != nil {
			return mErr
		}
		cfg.RecommendationRulesJSON = raw
		cfg.DefaultRecommendationFluctuationPct = fluct
		return db.Save(&cfg).Error
	}
	return nil
}

// rulesetNeedsDefaultRulesRewrite reports whether a persisted ruleset predates
// Hold/threshold rules, still has duplicate BUY/Book Profit/SELL rows, or still
// includes WATCH.
func rulesetNeedsDefaultRulesRewrite(rs recrules.Ruleset) bool {
	hasHold := false
	hasBuyThreshold := false
	hasProfitThreshold := false
	hasStopThreshold := false
	buyCount := 0
	bookProfitCount := 0
	sellCount := 0
	for _, r := range rs.Rules {
		c := strings.ToLower(r.Condition)
		if strings.EqualFold(r.Recommendation, "WATCH") {
			return true
		}
		switch r.Recommendation {
		case "BUY":
			buyCount++
		case "Book Profit":
			bookProfitCount++
		case "SELL":
			sellCount++
		}
		if strings.EqualFold(r.Recommendation, "AT HOLD PRICE") ||
			strings.Contains(c, "last_trade_is_hold") {
			hasHold = true
		}
		if strings.Contains(c, "set_buy_price") {
			hasBuyThreshold = true
		}
		if strings.Contains(c, "set_profit_booking_price") {
			hasProfitThreshold = true
		}
		if strings.Contains(c, "set_stop_loss_price") {
			hasStopThreshold = true
		}
	}
	if buyCount > 1 || bookProfitCount > 1 || sellCount > 1 {
		return true
	}
	return !hasHold || !hasBuyThreshold || !hasProfitThreshold || !hasStopThreshold
}

// MigrateRecommendationRulesHoldThresholds upgrades App_Config (and user
// overrides) to the current DefaultRuleset when they are missing Hold/threshold
// rules, still have split BUY/Book Profit/SELL rows, or still include WATCH.
// Preserves fluctuation_pct. Subsequent startups no-op once the shape matches.
func MigrateRecommendationRulesHoldThresholds(db *gorm.DB) error {
	var cfg models.AppConfig
	if err := db.First(&cfg, 1).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil
		}
		return err
	}
	if strings.TrimSpace(cfg.RecommendationRulesJSON) == "" {
		return nil
	}

	adminRS, err := recrules.Parse(cfg.RecommendationRulesJSON)
	if err != nil {
		return fmt.Errorf("migrate hold/threshold rules: parse App_Config: %w", err)
	}
	if rulesetNeedsDefaultRulesRewrite(adminRS) {
		fluct := recrules.FluctuationFromRuleset(adminRS, cfg.DefaultRecommendationFluctuationPct)
		if fluct <= 0 {
			fluct = defaultRecommendationFluctuationPct
		}
		fresh := recrules.DefaultRuleset(fluct)
		raw, mErr := fresh.Marshal()
		if mErr != nil {
			return mErr
		}
		cfg.RecommendationRulesJSON = raw
		cfg.DefaultRecommendationFluctuationPct = fluct
		if err := db.Save(&cfg).Error; err != nil {
			return err
		}
		log.Printf("Migrated App_Config recommendation rules to combined Hold/threshold defaults")
	}

	var users []models.UserConfig
	if err := db.Where("recommendation_rules_json IS NOT NULL AND recommendation_rules_json <> ''").
		Find(&users).Error; err != nil {
		return err
	}
	for i := range users {
		uc := &users[i]
		if uc.RecommendationRulesJSON == nil || strings.TrimSpace(*uc.RecommendationRulesJSON) == "" {
			continue
		}
		userRS, pErr := recrules.Parse(*uc.RecommendationRulesJSON)
		if pErr != nil {
			log.Printf("Skip user_config %d hold/threshold rules migrate: %v", uc.UserID, pErr)
			continue
		}
		if !rulesetNeedsDefaultRulesRewrite(userRS) {
			continue
		}
		fluct := recrules.FluctuationFromRuleset(userRS, cfg.DefaultRecommendationFluctuationPct)
		if fluct <= 0 {
			fluct = defaultRecommendationFluctuationPct
		}
		fresh := recrules.DefaultRuleset(fluct)
		raw, mErr := fresh.Marshal()
		if mErr != nil {
			return mErr
		}
		uc.RecommendationRulesJSON = &raw
		if err := db.Save(uc).Error; err != nil {
			return err
		}
		log.Printf("Migrated User_Config recommendation rules for user_id=%d to combined Hold/threshold defaults", uc.UserID)
	}
	return nil
}

func (h *Handler) getAppConfig() (models.AppConfig, error) {
	var cfg models.AppConfig
	err := h.DB.First(&cfg, 1).Error
	if err == gorm.ErrRecordNotFound {
		if seedErr := EnsureAppConfig(h.DB); seedErr != nil {
			return models.AppConfig{}, seedErr
		}
		err = h.DB.First(&cfg, 1).Error
	} else if err == nil && strings.TrimSpace(cfg.RecommendationRulesJSON) == "" {
		if seedErr := EnsureAppConfig(h.DB); seedErr != nil {
			return models.AppConfig{}, seedErr
		}
		err = h.DB.First(&cfg, 1).Error
	}
	return cfg, err
}

func (h *Handler) userUsesWatchList(userID uint) bool {
	var cfg models.UserConfig
	if err := h.DB.Where("user_id = ?", userID).First(&cfg).Error; err != nil {
		return false
	}
	return cfg.UseAsStockWatchList
}

func adminDefaultRuleset(appCfg models.AppConfig) (recrules.Ruleset, error) {
	if strings.TrimSpace(appCfg.RecommendationRulesJSON) != "" {
		return recrules.Parse(appCfg.RecommendationRulesJSON)
	}
	fluct := appCfg.DefaultRecommendationFluctuationPct
	if fluct <= 0 {
		fluct = defaultRecommendationFluctuationPct
	}
	return recrules.DefaultRuleset(fluct), nil
}

func resolveEffectiveRuleset(cfg *models.UserConfig, appCfg models.AppConfig) (effective recrules.Ruleset, isOverride bool, err error) {
	adminRS, err := adminDefaultRuleset(appCfg)
	if err != nil {
		return recrules.Ruleset{}, false, err
	}
	if cfg == nil {
		return adminRS, false, nil
	}
	if cfg.RecommendationRulesJSON != nil && strings.TrimSpace(*cfg.RecommendationRulesJSON) != "" {
		userRS, pErr := recrules.Parse(*cfg.RecommendationRulesJSON)
		if pErr != nil {
			return recrules.Ruleset{}, false, pErr
		}
		return userRS, true, nil
	}
	// Legacy: only fluctuation override — copy admin rules with user's pct.
	if cfg.RecommendationFluctuationPct != nil && *cfg.RecommendationFluctuationPct > 0 {
		rs := recrules.DefaultRuleset(*cfg.RecommendationFluctuationPct)
		// Prefer admin rule structure if available.
		if len(adminRS.Rules) > 0 {
			rs = adminRS
			rs.SetNamedValue("fluctuation_pct", *cfg.RecommendationFluctuationPct)
		}
		return rs, true, nil
	}
	return adminRS, false, nil
}

func preferencesResponse(cfg *models.UserConfig, appCfg models.AppConfig) (gin.H, error) {
	adminRS, err := adminDefaultRuleset(appCfg)
	if err != nil {
		return nil, err
	}
	effective, isOverride, err := resolveEffectiveRuleset(cfg, appCfg)
	if err != nil {
		return nil, err
	}
	useWatch := false
	if cfg != nil {
		useWatch = cfg.UseAsStockWatchList
	}
	fluct := recrules.FluctuationFromRuleset(effective, appCfg.DefaultRecommendationFluctuationPct)
	adminFluct := recrules.FluctuationFromRuleset(adminRS, appCfg.DefaultRecommendationFluctuationPct)
	var userPct any
	if isOverride {
		userPct = fluct
	}
	return gin.H{
		"use_as_stock_watch_list":                  useWatch,
		"recommendation_fluctuation_pct":           userPct,
		"effective_recommendation_fluctuation_pct": fluct,
		"default_recommendation_fluctuation_pct":   adminFluct,
		"effective_recommendation_rules":           effective.ToMap(),
		"default_recommendation_rules":             adminRS.ToMap(),
		"recommendation_rules_is_user_override":    isOverride,
	}, nil
}

func (h *Handler) GetPreferences(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	appCfg, err := h.getAppConfig()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	var cfg models.UserConfig
	err = h.DB.Where("user_id = ?", userID).First(&cfg).Error
	if err == gorm.ErrRecordNotFound {
		resp, rErr := preferencesResponse(nil, appCfg)
		if rErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": rErr.Error()})
			return
		}
		c.JSON(http.StatusOK, resp)
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// One-time migrate legacy fluctuation-only override into rules JSON.
	if (cfg.RecommendationRulesJSON == nil || strings.TrimSpace(*cfg.RecommendationRulesJSON) == "") &&
		cfg.RecommendationFluctuationPct != nil && *cfg.RecommendationFluctuationPct > 0 {
		adminRS, aErr := adminDefaultRuleset(appCfg)
		if aErr == nil {
			adminRS.SetNamedValue("fluctuation_pct", *cfg.RecommendationFluctuationPct)
			if raw, mErr := adminRS.Marshal(); mErr == nil {
				cfg.RecommendationRulesJSON = &raw
				_ = h.DB.Save(&cfg).Error
			}
		}
	}

	resp, rErr := preferencesResponse(&cfg, appCfg)
	if rErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": rErr.Error()})
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *Handler) PutPreferences(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var req struct {
		UseAsStockWatchList            *bool           `json:"use_as_stock_watch_list"`
		RecommendationFluctuationPct   *float64        `json:"recommendation_fluctuation_pct"`
		ClearRecommendationFluctuation bool            `json:"clear_recommendation_fluctuation"`
		RecommendationRules            json.RawMessage `json:"recommendation_rules"`
		ClearRecommendationRules       bool            `json:"clear_recommendation_rules"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.RecommendationFluctuationPct != nil && *req.RecommendationFluctuationPct <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "recommendation_fluctuation_pct must be greater than 0"})
		return
	}

	var rulesRaw *string
	if len(req.RecommendationRules) > 0 && string(req.RecommendationRules) != "null" {
		rs, err := recrules.Parse(string(req.RecommendationRules))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		raw, err := rs.Marshal()
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		rulesRaw = &raw
	}

	appCfg, err := h.getAppConfig()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}

	var cfg models.UserConfig
	err = tx.Where("user_id = ?", userID).First(&cfg).Error
	creating := err == gorm.ErrRecordNotFound
	if err != nil && err != gorm.ErrRecordNotFound {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if creating {
		cfg = models.UserConfig{UserID: userID}
	}

	wasWatch := cfg.UseAsStockWatchList
	if req.UseAsStockWatchList != nil {
		cfg.UseAsStockWatchList = *req.UseAsStockWatchList
	}
	if req.ClearRecommendationRules || req.ClearRecommendationFluctuation {
		cfg.RecommendationRulesJSON = nil
		cfg.RecommendationFluctuationPct = nil
	}
	if rulesRaw != nil {
		cfg.RecommendationRulesJSON = rulesRaw
		cfg.RecommendationFluctuationPct = nil
	} else if req.RecommendationFluctuationPct != nil {
		v := *req.RecommendationFluctuationPct
		cfg.RecommendationFluctuationPct = &v
	}

	if creating {
		if err := tx.Create(&cfg).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	} else {
		if err := tx.Save(&cfg).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	if !wasWatch && cfg.UseAsStockWatchList {
		if err := normalizeUserHoldingsToQtyOne(tx, userID); err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	resp, rErr := preferencesResponse(&cfg, appCfg)
	if rErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": rErr.Error()})
		return
	}
	c.JSON(http.StatusOK, resp)
}

// normalizeUserHoldingsToQtyOne sets every positive holding to qty 1 and open buy lots totaling 1.
func normalizeUserHoldingsToQtyOne(db *gorm.DB, userID uint) error {
	var positions []models.UserStock
	if err := db.Where("user_id = ? AND quantity > 0", userID).Find(&positions).Error; err != nil {
		return err
	}
	for _, pos := range positions {
		if err := normalizePositionLotsToOne(db, pos); err != nil {
			return err
		}
	}
	return nil
}

func normalizePositionLotsToOne(db *gorm.DB, pos models.UserStock) error {
	var buys []models.UserStockTransaction
	if err := db.Where(
		"user_id = ? AND stock_id = ? AND source = ? AND type = ? AND quantity > 0",
		pos.UserID, pos.StockID, pos.Source, models.TransactionTypeBuy,
	).Order("transaction_date ASC, id ASC").Find(&buys).Error; err != nil {
		return err
	}

	remaining := 1.0
	for i := range buys {
		if remaining < 1e-9 {
			buys[i].Quantity = 0
			if err := db.Save(&buys[i]).Error; err != nil {
				return err
			}
			continue
		}
		if buys[i].Quantity > remaining {
			buys[i].Quantity = remaining
		}
		remaining -= buys[i].Quantity
		if err := db.Save(&buys[i]).Error; err != nil {
			return err
		}
	}

	if remaining > 1e-9 {
		// No open lots left enough qty — create a single lot of 1 at avg buy.
		price := pos.AvgBuyPrice
		if price <= 0 {
			price = 1
		}
		lot := models.UserStockTransaction{
			UserID:           pos.UserID,
			StockID:          pos.StockID,
			Source:           pos.Source,
			Type:             models.TransactionTypeBuy,
			Quantity:         remaining,
			OriginalQuantity: remaining,
			Price:            price,
			TransactionDate:  pos.UpdatedAt,
		}
		if lot.TransactionDate.IsZero() {
			lot.TransactionDate = pos.CreatedAt
		}
		if err := db.Create(&lot).Error; err != nil {
			return err
		}
	}

	pos.Quantity = 1
	return db.Save(&pos).Error
}

func (h *Handler) GetAdminConfig(c *gin.Context) {
	cfg, err := h.getAppConfig()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	rs, err := adminDefaultRuleset(cfg)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"default_recommendation_fluctuation_pct": recrules.FluctuationFromRuleset(rs, cfg.DefaultRecommendationFluctuationPct),
		"recommendation_rules":                   rs.ToMap(),
	})
}

func (h *Handler) PutAdminConfig(c *gin.Context) {
	var req struct {
		DefaultRecommendationFluctuationPct *float64        `json:"default_recommendation_fluctuation_pct"`
		RecommendationRules                 json.RawMessage `json:"recommendation_rules"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	cfg, err := h.getAppConfig()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if len(req.RecommendationRules) > 0 && string(req.RecommendationRules) != "null" {
		rs, err := recrules.Parse(string(req.RecommendationRules))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		raw, err := rs.Marshal()
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		cfg.RecommendationRulesJSON = raw
		cfg.DefaultRecommendationFluctuationPct = recrules.FluctuationFromRuleset(rs, defaultRecommendationFluctuationPct)
	} else if req.DefaultRecommendationFluctuationPct != nil {
		if *req.DefaultRecommendationFluctuationPct <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "default_recommendation_fluctuation_pct must be greater than 0"})
			return
		}
		cfg.DefaultRecommendationFluctuationPct = *req.DefaultRecommendationFluctuationPct
		rs, err := adminDefaultRuleset(cfg)
		if err != nil {
			rs = recrules.DefaultRuleset(*req.DefaultRecommendationFluctuationPct)
		} else {
			rs.SetNamedValue("fluctuation_pct", *req.DefaultRecommendationFluctuationPct)
		}
		raw, err := rs.Marshal()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		cfg.RecommendationRulesJSON = raw
	} else {
		c.JSON(http.StatusBadRequest, gin.H{"error": "recommendation_rules or default_recommendation_fluctuation_pct required"})
		return
	}

	if err := h.DB.Save(&cfg).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	rs, err := adminDefaultRuleset(cfg)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"default_recommendation_fluctuation_pct": recrules.FluctuationFromRuleset(rs, cfg.DefaultRecommendationFluctuationPct),
		"recommendation_rules":                   rs.ToMap(),
	})
}
