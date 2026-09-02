package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const (
	clearFieldAll                   = "all"
	clearFieldLastBuy               = "last_buy"
	clearFieldLastSale              = "last_sale"
	clearFieldLastHold              = "last_hold"
	clearFieldSetBuyPrice           = "set_buy_price"
	clearFieldSetProfitBookingPrice = "set_profit_booking_price"
	clearFieldSetStopLossPrice      = "set_stop_loss_price"
)

func applyClearReviewFields(pos *models.UserStock, fields []string, now time.Time) error {
	if len(fields) == 0 {
		return fmt.Errorf("fields is required")
	}
	clearAll := false
	clearBSH := false
	zeroSetBuy := false
	zeroSetProfit := false
	zeroSetStop := false
	for _, raw := range fields {
		switch strings.TrimSpace(raw) {
		case clearFieldAll:
			clearAll = true
		case clearFieldLastBuy, clearFieldLastSale, clearFieldLastHold:
			clearBSH = true
		case clearFieldSetBuyPrice:
			zeroSetBuy = true
		case clearFieldSetProfitBookingPrice:
			zeroSetProfit = true
		case clearFieldSetStopLossPrice:
			zeroSetStop = true
		case "":
			return fmt.Errorf("fields contains an empty value")
		default:
			return fmt.Errorf("unknown field %q", raw)
		}
	}
	if clearAll {
		clearPriceThresholds(pos)
		pos.BSHClearDate = &now
		return nil
	}
	if clearBSH {
		pos.BSHClearDate = &now
	}
	if zeroSetBuy {
		pos.SetBuyPrice = 0
	}
	if zeroSetProfit {
		pos.SetProfitBookingPrice = 0
	}
	if zeroSetStop {
		pos.SetStopLossPrice = 0
	}
	return nil
}

// ClearStockReviewValues zeros selected thresholds and/or stamps bsh_clear_date
// so last buy/sell/hold prices are ignored in recommendation rules.
func (h *Handler) ClearStockReviewValues(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stock id"})
		return
	}

	var req struct {
		Source string   `json:"source"`
		Fields []string `json:"fields"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	now := time.Now()
	var probe models.UserStock
	if err := applyClearReviewFields(&probe, req.Fields, now); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := middleware.CurrentUserID(c)
	source := normalizeSource(req.Source)

	var stock models.Stock
	if err := h.DB.First(&stock, uint(id)).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var pos models.UserStock
	if err := h.DB.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stock.ID, source).
		First(&pos).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "holding not found for this source"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if err := applyClearReviewFields(&pos, req.Fields, now); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.DB.Save(&pos).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"stock_id":                 pos.StockID,
		"source":                   pos.Source,
		"set_buy_price":            pos.SetBuyPrice,
		"set_profit_booking_price": pos.SetProfitBookingPrice,
		"set_stop_loss_price":      pos.SetStopLossPrice,
		"bsh_clear_date":           pos.BSHClearDate,
		"last_buy_price":           pos.LastBuyPrice,
		"last_sale_price":          pos.LastSalePrice,
		"last_hold_price":          pos.LastHoldPrice,
	})
}

// ClearAllStockReviewValues zeros thresholds and stamps bsh_clear_date on every
// holding for the current user.
func (h *Handler) ClearAllStockReviewValues(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	now := time.Now()
	if err := h.DB.Model(&models.UserStock{}).
		Where("user_id = ?", userID).
		Updates(map[string]any{
			"set_buy_price":            0,
			"set_profit_booking_price": 0,
			"set_stop_loss_price":      0,
			"bsh_clear_date":           now,
		}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
