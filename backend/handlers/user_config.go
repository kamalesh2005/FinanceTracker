package handlers

import (
	"net/http"
	"strings"

	"financetracker/middleware"
	"financetracker/models"

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

// EnsureAppConfig seeds singleton App_Config id=1 with default fluctuation 5%.
func EnsureAppConfig(db *gorm.DB) error {
	var cfg models.AppConfig
	err := db.First(&cfg, 1).Error
	if err == gorm.ErrRecordNotFound {
		cfg = models.AppConfig{
			ID:                                  1,
			DefaultRecommendationFluctuationPct: defaultRecommendationFluctuationPct,
		}
		return db.Create(&cfg).Error
	}
	return err
}

func (h *Handler) getAppConfig() (models.AppConfig, error) {
	var cfg models.AppConfig
	err := h.DB.First(&cfg, 1).Error
	if err == gorm.ErrRecordNotFound {
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

func preferencesResponse(cfg *models.UserConfig, appDefault float64) gin.H {
	useWatch := false
	var userPct any
	effective := appDefault
	if cfg != nil {
		useWatch = cfg.UseAsStockWatchList
		if cfg.RecommendationFluctuationPct != nil {
			userPct = *cfg.RecommendationFluctuationPct
			effective = *cfg.RecommendationFluctuationPct
		}
	}
	return gin.H{
		"use_as_stock_watch_list":                  useWatch,
		"recommendation_fluctuation_pct":           userPct,
		"effective_recommendation_fluctuation_pct": effective,
		"default_recommendation_fluctuation_pct":   appDefault,
	}
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
		c.JSON(http.StatusOK, preferencesResponse(nil, appCfg.DefaultRecommendationFluctuationPct))
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, preferencesResponse(&cfg, appCfg.DefaultRecommendationFluctuationPct))
}

func (h *Handler) PutPreferences(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var req struct {
		UseAsStockWatchList            *bool    `json:"use_as_stock_watch_list"`
		RecommendationFluctuationPct   *float64 `json:"recommendation_fluctuation_pct"`
		ClearRecommendationFluctuation bool     `json:"clear_recommendation_fluctuation"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.RecommendationFluctuationPct != nil && *req.RecommendationFluctuationPct <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "recommendation_fluctuation_pct must be greater than 0"})
		return
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
	if req.ClearRecommendationFluctuation {
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

	c.JSON(http.StatusOK, preferencesResponse(&cfg, appCfg.DefaultRecommendationFluctuationPct))
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
	c.JSON(http.StatusOK, gin.H{
		"default_recommendation_fluctuation_pct": cfg.DefaultRecommendationFluctuationPct,
	})
}

func (h *Handler) PutAdminConfig(c *gin.Context) {
	var req struct {
		DefaultRecommendationFluctuationPct *float64 `json:"default_recommendation_fluctuation_pct"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.DefaultRecommendationFluctuationPct == nil || *req.DefaultRecommendationFluctuationPct <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "default_recommendation_fluctuation_pct must be greater than 0"})
		return
	}

	cfg, err := h.getAppConfig()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	cfg.DefaultRecommendationFluctuationPct = *req.DefaultRecommendationFluctuationPct
	if err := h.DB.Save(&cfg).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"default_recommendation_fluctuation_pct": cfg.DefaultRecommendationFluctuationPct,
	})
}
