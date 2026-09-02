package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"financetracker/models"
	"financetracker/notify"
	"financetracker/recrules"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// StockReviewEmailEligible reports whether a user should receive review emails.
func StockReviewEmailEligible(user models.User, cfg *models.UserConfig, hasConfigRow bool) bool {
	email := userEmail(user)
	if email == "" || !user.Enabled {
		return false
	}
	userOptIn := true
	adminEnabled := false
	if hasConfigRow && cfg != nil {
		userOptIn = cfg.StockReviewEmailEnabled
		adminEnabled = cfg.StockReviewEmailAdminEnabled
	}
	return userOptIn && adminEnabled
}

func userEmail(u models.User) string {
	if u.Email == nil {
		return ""
	}
	return strings.TrimSpace(*u.Email)
}

func stockReviewEmailPrefs(user models.User, cfg *models.UserConfig, hasConfigRow bool) (enabled, adminEnabled, effective bool) {
	email := userEmail(user)
	available := email != ""
	enabled = available
	adminEnabled = false
	if hasConfigRow && cfg != nil {
		enabled = cfg.StockReviewEmailEnabled
		adminEnabled = cfg.StockReviewEmailAdminEnabled
	}
	effective = StockReviewEmailEligible(user, cfg, hasConfigRow)
	return enabled, adminEnabled, effective
}

// SendStockReviewEmails sends review emails to eligible users.
func (h *Handler) SendStockReviewEmails(source string, filterUserID *uint) error {
	var users []models.User
	q := h.DB.Where("enabled = ?", true).Where("email IS NOT NULL AND TRIM(email) <> ''")
	if filterUserID != nil {
		q = q.Where("id = ?", *filterUserID)
	}
	if err := q.Find(&users).Error; err != nil {
		return err
	}

	var configs []models.UserConfig
	_ = h.DB.Find(&configs).Error
	cfgByUser := make(map[uint]models.UserConfig, len(configs))
	for _, c := range configs {
		cfgByUser[c.UserID] = c
	}

	appCfg, err := h.getAppConfig()
	if err != nil {
		return err
	}

	sent := 0
	skipped := 0
	failed := 0
	var firstErr error

	for _, user := range users {
		cfg, hasCfg := cfgByUser[user.ID]
		var cfgPtr *models.UserConfig
		if hasCfg {
			c := cfg
			cfgPtr = &c
		}
		if !StockReviewEmailEligible(user, cfgPtr, hasCfg) {
			skipped++
			continue
		}

		rows, err := h.buildReviewEmailRows(user.ID, &cfg, appCfg)
		if err != nil {
			failed++
			if firstErr == nil {
				firstErr = fmt.Errorf("user %d: %w", user.ID, err)
			}
			continue
		}
		if len(rows) == 0 {
			skipped++
			continue
		}

		if err := notify.SendStockReviewEmail(userEmail(user), rows); err != nil {
			failed++
			if firstErr == nil {
				firstErr = fmt.Errorf("user %d: %w", user.ID, err)
			}
			continue
		}
		sent++
	}

	summary := &ImportSummary{
		Created: sent,
		Skipped: skipped,
		Errors:  failed,
	}
	var recordErr error
	if failed > 0 && sent == 0 {
		recordErr = firstErr
	}
	_ = RecordImportStatus(h.DB, models.ImportKindStockReviewEmail, source, recordErr, summary)
	if failed > 0 && sent > 0 {
		return firstErr
	}
	return recordErr
}

func (h *Handler) buildReviewEmailRows(userID uint, cfg *models.UserConfig, appCfg models.AppConfig) ([]notify.ReviewEmailRow, error) {
	showZeroQty := false
	if cfg != nil {
		showZeroQty = cfg.ShowZeroQuantityStocks
	}

	stocks, err := h.stocksForUser(userID)
	if err != nil {
		return nil, err
	}
	details := h.stocksWithHoldings(stocks, userID)

	effectiveRules, _, err := resolveEffectiveRuleset(cfg, appCfg)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	var rows []notify.ReviewEmailRow
	for _, d := range details {
		if !showZeroQty && d.Quantity <= 0 {
			continue
		}
		input := recrules.HoldingInput{
			CurrPrice:             d.CurrentPrice,
			AvgBuyPrice:           d.AverageBuyPrice,
			LastBuyPrice:          d.LastBuyPrice,
			LastBuyDate:           d.LastBuyDate,
			LastBuyTrend:          d.LastBuyTrend,
			LastSalePrice:         d.LastSalePrice,
			LastSaleDate:          d.LastSaleDate,
			LastSaleTrend:         d.LastSaleTrend,
			LastHoldPrice:         d.LastHoldPrice,
			LastHoldDate:          d.LastHoldDate,
			LastHoldTrend:         d.LastHoldTrend,
			BSHClearDate:          d.BSHClearDate,
			SixthHighestPrice:     d.SixthHighestPrice,
			SixthLowestPrice:      d.SixthLowestPrice,
			Trend:                 d.Trend,
			SetBuyPrice:           d.SetBuyPrice,
			SetProfitBookingPrice: d.SetProfitBookingPrice,
			SetStopLossPrice:      d.SetStopLossPrice,
			Now:                   now,
		}
		ctx := recrules.BuildEvaluateContext(input, effectiveRules)
		signal := recrules.Evaluate(effectiveRules, ctx)
		if !recrules.IsActionableSignal(signal) {
			continue
		}
		rows = append(rows, notify.ReviewEmailRow{
			Symbol:       d.Symbol,
			Name:         d.Name,
			Signal:       signal,
			CurrentPrice: d.CurrentPrice,
			MA7:          d.MA7,
			MA20:         d.MA20,
			MA50:         d.MA50,
			WeekHigh52:   d.SixthHighestPrice,
			WeekLow52:    d.SixthLowestPrice,
		})
	}
	return rows, nil
}

func (h *Handler) GetStockReviewEmailStatus(c *gin.Context) {
	var row models.StockDataImportStatus
	if err := h.DB.Where("kind = ?", models.ImportKindStockReviewEmail).First(&row).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			_ = EnsureImportStatuses(h.DB)
			_ = h.DB.Where("kind = ?", models.ImportKindStockReviewEmail).First(&row).Error
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	c.JSON(http.StatusOK, importStatusRow(row))
}

func (h *Handler) TriggerStockReviewEmails(c *gin.Context) {
	var req struct {
		UserID *uint `json:"user_id"`
	}
	_ = c.ShouldBindJSON(&req)

	go func() {
		if err := h.SendStockReviewEmails(models.ImportSourceManual, req.UserID); err != nil {
			// logged via RecordImportStatus
		}
	}()
	c.JSON(http.StatusAccepted, gin.H{"message": "stock review email job started"})
}

func (h *Handler) SetUserStockReviewEmailAdmin(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}
	var req struct {
		AdminEnabled bool `json:"admin_enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user models.User
	if err := h.DB.First(&user, uint(id)).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var cfg models.UserConfig
	err = h.DB.Where("user_id = ?", user.ID).First(&cfg).Error
	if err == gorm.ErrRecordNotFound {
		cfg = models.UserConfig{
			UserID:                       user.ID,
			StockReviewEmailEnabled:      userEmail(user) != "",
			StockReviewEmailAdminEnabled: req.AdminEnabled,
		}
		if err := h.DB.Create(&cfg).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	} else {
		cfg.StockReviewEmailAdminEnabled = req.AdminEnabled
		if err := h.DB.Save(&cfg).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	enabled, adminEnabled, effective := stockReviewEmailPrefs(user, &cfg, true)
	c.JSON(http.StatusOK, gin.H{
		"stock_review_email_enabled":       enabled,
		"stock_review_email_admin_enabled": adminEnabled,
		"stock_review_email_effective":     effective,
	})
}

func importStatusRow(row models.StockDataImportStatus) gin.H {
	out := gin.H{
		"kind":        row.Kind,
		"last_status": row.LastStatus,
		"last_error":  row.LastError,
		"last_source": row.LastSource,
	}
	if row.LastAttemptAt != nil {
		out["last_attempt_at"] = row.LastAttemptAt
	}
	if row.LastSuccessAt != nil {
		out["last_success_at"] = row.LastSuccessAt
	}
	if strings.TrimSpace(row.LastSummaryJSON) != "" {
		out["last_summary_json"] = row.LastSummaryJSON
	}
	return out
}
