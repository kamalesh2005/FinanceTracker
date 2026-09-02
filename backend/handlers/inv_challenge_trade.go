package handlers

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func invChStockID(c *gin.Context) (uint, bool) {
	id, err := strconv.ParseUint(c.Param("stockId"), 10, 32)
	if err != nil || id == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stock id"})
		return 0, false
	}
	return uint(id), true
}

func (h *Handler) requireActiveTrader(c *gin.Context, mustOpen bool) (invChAccess, bool) {
	id, ok := requireInvChID(c)
	if !ok {
		return invChAccess{}, false
	}
	userID := middleware.CurrentUserID(c)
	acc, err := h.loadInvChAccess(id, userID)
	if err != nil {
		writeInvChAccessError(c, err)
		return acc, false
	}
	if acc.Member.ID == 0 || acc.Member.Status != models.InvChMemberActive || acc.Member.UserID == nil {
		c.JSON(http.StatusForbidden, gin.H{"error": errInvChNotActive.Error()})
		return acc, false
	}
	if mustOpen && !invChTradingOpen(acc.Challenge, time.Now()) {
		c.JSON(http.StatusBadRequest, gin.H{"error": errInvChEnded.Error()})
		return acc, false
	}
	return acc, true
}

func recomputeInvChHolding(db *gorm.DB, challengeID, userID, stockID uint) (models.InvChHolding, error) {
	var txs []models.InvChTransaction
	if err := db.Where("challenge_id = ? AND user_id = ? AND stock_id = ?", challengeID, userID, stockID).
		Order("transaction_date ASC, id ASC").
		Find(&txs).Error; err != nil {
		return models.InvChHolding{}, err
	}

	qty := 0.0
	invested := 0.0
	avg := 0.0
	var lastBuyPrice float64
	var lastSalePrice float64
	var lastBuyDate *time.Time
	var lastSaleDate *time.Time

	for _, tx := range txs {
		switch tx.Type {
		case models.TransactionTypeBuy:
			if tx.Quantity > 1e-9 {
				invested += tx.Price * tx.Quantity
				qty += tx.Quantity
			}
			lastBuyPrice = tx.Price
			d := tx.TransactionDate
			lastBuyDate = &d
		case models.TransactionTypeSell:
			lastSalePrice = tx.Price
			d := tx.TransactionDate
			lastSaleDate = &d
		}
	}
	if qty > 1e-9 {
		avg = invested / qty
	} else {
		qty = 0
		avg = 0
	}

	var pos models.InvChHolding
	err := db.Where("challenge_id = ? AND user_id = ? AND stock_id = ?", challengeID, userID, stockID).First(&pos).Error
	if err != nil && err != gorm.ErrRecordNotFound {
		return models.InvChHolding{}, err
	}
	pos.ChallengeID = challengeID
	pos.UserID = userID
	pos.StockID = stockID
	pos.Quantity = qty
	pos.AvgBuyPrice = avg
	pos.LastBuyPrice = lastBuyPrice
	pos.LastBuyDate = lastBuyDate
	pos.LastSalePrice = lastSalePrice
	pos.LastSaleDate = lastSaleDate

	if err == gorm.ErrRecordNotFound {
		if err := db.Create(&pos).Error; err != nil {
			return models.InvChHolding{}, err
		}
		return pos, nil
	}
	if err := db.Save(&pos).Error; err != nil {
		return models.InvChHolding{}, err
	}
	return pos, nil
}

func applyInvChFIFOSell(db *gorm.DB, challengeID, userID, stockID uint, sellQty, salePrice float64, saleDate time.Time) error {
	var buys []models.InvChTransaction
	if err := db.Where(
		"challenge_id = ? AND user_id = ? AND stock_id = ? AND type = ? AND quantity > 0",
		challengeID, userID, stockID, models.TransactionTypeBuy,
	).Order("transaction_date ASC, id ASC").Find(&buys).Error; err != nil {
		return err
	}

	remaining := sellQty
	for i := range buys {
		if remaining < 1e-9 {
			break
		}
		openQty := buys[i].Quantity
		if openQty <= remaining+1e-9 {
			d := saleDate
			buys[i].Quantity = 0
			buys[i].SalePrice = salePrice
			buys[i].SaleDate = &d
			if err := db.Save(&buys[i]).Error; err != nil {
				return err
			}
			remaining -= openQty
			if remaining < 1e-9 {
				remaining = 0
			}
			continue
		}

		take := remaining
		remainderQty := openQty - take
		d := saleDate
		sold := buys[i]
		sold.ID = 0
		sold.CreatedAt = time.Time{}
		sold.Quantity = 0
		sold.OriginalQuantity = take
		sold.SalePrice = salePrice
		sold.SaleDate = &d
		if err := db.Create(&sold).Error; err != nil {
			return err
		}

		buys[i].Quantity = remainderQty
		buys[i].OriginalQuantity = remainderQty
		buys[i].SalePrice = 0
		buys[i].SaleDate = nil
		if err := db.Save(&buys[i]).Error; err != nil {
			return err
		}
		remaining = 0
	}
	if remaining > 1e-9 {
		return fmt.Errorf("%w: could not allocate %.4f from buy lots", errInsufficientQuantity, remaining)
	}
	return nil
}

func clearInvChThresholds(pos *models.InvChHolding) {
	pos.SetBuyPrice = 0
	pos.SetProfitBookingPrice = 0
	pos.SetStopLossPrice = 0
}

type invChTradeResult struct {
	Ledger  models.InvChTransaction
	Holding models.InvChHolding
	Cash    float64
}

func applyInvChTrade(db *gorm.DB, challengeID, userID uint, txType models.TransactionType, symbol string, quantity float64, now time.Time) (invChTradeResult, error) {
	var out invChTradeResult
	if quantity <= 0 {
		return out, fmt.Errorf("quantity must be greater than 0")
	}
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if symbol == "" {
		return out, fmt.Errorf("symbol is required")
	}

	err := db.Transaction(func(tx *gorm.DB) error {
		var ch models.InvChChallenge
		if err := tx.First(&ch, challengeID).Error; err != nil {
			return err
		}
		if !invChTradingOpen(ch, now) {
			return errInvChEnded
		}

		var member models.InvChMember
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("challenge_id = ? AND user_id = ? AND status = ?", challengeID, userID, models.InvChMemberActive).
			First(&member).Error; err != nil {
			if err == gorm.ErrRecordNotFound {
				return errInvChNotActive
			}
			return err
		}

		var stock models.Stock
		if err := tx.Where("UPPER(symbol) = ?", symbol).First(&stock).Error; err != nil {
			if err == gorm.ErrRecordNotFound {
				return fmt.Errorf("stock not found in catalog")
			}
			return err
		}
		price := stock.CurrentPrice
		if price <= 0 {
			return fmt.Errorf("no live price available for %s", stock.Symbol)
		}

		fee := models.InvChTransactionFee
		var cashDelta float64
		if txType == models.TransactionTypeBuy {
			cost := quantity*price + fee
			if member.CashBalance+1e-9 < cost {
				return fmt.Errorf("%w: need %.2f, have %.2f", errInvChInsufficient, cost, member.CashBalance)
			}
			cashDelta = -cost
		} else {
			var holding models.InvChHolding
			err := tx.Where("challenge_id = ? AND user_id = ? AND stock_id = ?", challengeID, userID, stock.ID).First(&holding).Error
			if err == gorm.ErrRecordNotFound || holding.Quantity < quantity-1e-9 {
				available := 0.0
				if err == nil {
					available = holding.Quantity
				}
				return fmt.Errorf("%w: available %.2f, requested %.2f", errInsufficientQuantity, available, quantity)
			}
			if err != nil && err != gorm.ErrRecordNotFound {
				return err
			}
			proceeds := quantity * price
			if proceeds <= fee+1e-9 {
				return errInvChFee
			}
			cashDelta = proceeds - fee
		}

		ledger := models.InvChTransaction{
			ChallengeID:      challengeID,
			UserID:           userID,
			StockID:          stock.ID,
			Type:             txType,
			Quantity:         quantity,
			OriginalQuantity: quantity,
			Price:            price,
			Fee:              fee,
			CashDelta:        cashDelta,
			TransactionDate:  now,
		}
		if err := tx.Create(&ledger).Error; err != nil {
			return err
		}
		if txType == models.TransactionTypeSell {
			if err := applyInvChFIFOSell(tx, challengeID, userID, stock.ID, quantity, price, now); err != nil {
				return err
			}
		}
		pos, err := recomputeInvChHolding(tx, challengeID, userID, stock.ID)
		if err != nil {
			return err
		}
		clearInvChThresholds(&pos)
		pos.BSHClearDate = nil
		if err := tx.Save(&pos).Error; err != nil {
			return err
		}
		member.CashBalance += cashDelta
		if err := tx.Save(&member).Error; err != nil {
			return err
		}
		markStockPullDataY(tx, stock.ID)
		out.Ledger = ledger
		out.Holding = pos
		out.Cash = member.CashBalance
		return nil
	})
	return out, err
}

func writeInvChTradeError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, errInvChEnded), errors.Is(err, errInvChInsufficient), errors.Is(err, errInvChFee), errors.Is(err, errInsufficientQuantity), errors.Is(err, errInvChNotActive):
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
	default:
		msg := err.Error()
		if strings.Contains(strings.ToLower(msg), "not found") || strings.Contains(strings.ToLower(msg), "no live price") {
			c.JSON(http.StatusBadRequest, gin.H{"error": msg})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": msg})
	}
}

func (h *Handler) InvChBuy(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, true)
	if !ok {
		return
	}
	var req struct {
		Symbol   string  `json:"symbol"`
		Quantity float64 `json:"quantity"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	h.enrichCatalogSymbol(req.Symbol, models.SourceFormatManual)
	res, err := applyInvChTrade(h.DB, acc.Challenge.ID, middleware.CurrentUserID(c), models.TransactionTypeBuy, req.Symbol, req.Quantity, time.Now())
	if err != nil {
		writeInvChTradeError(c, err)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"transaction": res.Ledger, "cash": res.Cash})
}

func (h *Handler) InvChSell(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, true)
	if !ok {
		return
	}
	var req struct {
		Symbol   string  `json:"symbol"`
		Quantity float64 `json:"quantity"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	h.enrichCatalogSymbol(req.Symbol, models.SourceFormatManual)
	res, err := applyInvChTrade(h.DB, acc.Challenge.ID, middleware.CurrentUserID(c), models.TransactionTypeSell, req.Symbol, req.Quantity, time.Now())
	if err != nil {
		writeInvChTradeError(c, err)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"transaction": res.Ledger, "cash": res.Cash})
}

func (h *Handler) GetInvChHoldings(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, false)
	if !ok {
		return
	}
	userID := middleware.CurrentUserID(c)
	c.JSON(http.StatusOK, h.invChHoldingsWithDetails(acc.Challenge.ID, userID))
}

func (h *Handler) invChHoldingsWithDetails(challengeID, userID uint) []StockWithDetails {
	var positions []models.InvChHolding
	h.DB.Where("challenge_id = ? AND user_id = ?", challengeID, userID).
		Order("stock_id ASC").Find(&positions)
	if len(positions) == 0 {
		return []StockWithDetails{}
	}
	ids := make([]uint, 0, len(positions))
	for _, p := range positions {
		ids = append(ids, p.StockID)
	}
	var stocks []models.Stock
	h.DB.Where("id IN ?", ids).Find(&stocks)
	byID := map[uint]models.Stock{}
	for _, s := range stocks {
		byID[s.ID] = s
	}
	var lots []models.InvChTransaction
	h.DB.Where("challenge_id = ? AND user_id = ? AND stock_id IN ? AND type = ?", challengeID, userID, ids, models.TransactionTypeBuy).
		Find(&lots)
	lotsByStock := map[uint][]models.InvChTransaction{}
	for _, lot := range lots {
		lotsByStock[lot.StockID] = append(lotsByStock[lot.StockID], lot)
	}
	asOf := time.Now()
	out := make([]StockWithDetails, 0, len(positions))
	for _, pos := range positions {
		stock, ok := byID[pos.StockID]
		if !ok {
			continue
		}
		userLots := lotsByStock[pos.StockID]
		ustx := make([]models.UserStockTransaction, 0, len(userLots))
		for _, lot := range userLots {
			ustx = append(ustx, models.UserStockTransaction{
				StockID:          lot.StockID,
				Type:             lot.Type,
				Quantity:         lot.Quantity,
				OriginalQuantity: lot.OriginalQuantity,
				Price:            lot.Price,
				SalePrice:        lot.SalePrice,
				SaleDate:         lot.SaleDate,
				TransactionDate:  timePtr(lot.TransactionDate),
			})
		}
		xirrVal := xirrRateFromLots(ustx, map[uint]float64{stock.ID: stock.CurrentPrice}, asOf)
		out = append(out, StockWithDetails{
			Stock:                 stock,
			Source:                "Challenge",
			Quantity:              pos.Quantity,
			AverageBuyPrice:       pos.AvgBuyPrice,
			LastBuyPrice:          pos.LastBuyPrice,
			LastBuyDate:           pos.LastBuyDate,
			LastSalePrice:         pos.LastSalePrice,
			LastSaleDate:          pos.LastSaleDate,
			LastHoldPrice:         pos.LastHoldPrice,
			LastHoldDate:          pos.LastHoldDate,
			SetBuyPrice:           pos.SetBuyPrice,
			SetProfitBookingPrice: pos.SetProfitBookingPrice,
			SetStopLossPrice:      pos.SetStopLossPrice,
			BSHClearDate:          pos.BSHClearDate,
			Notes:                 pos.Notes,
			XIRR:                  xirrVal,
		})
	}
	return out
}

func (h *Handler) GetInvChTrends(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, false)
	if !ok {
		return
	}
	userID := middleware.CurrentUserID(c)
	var stockIDs []uint
	_ = h.DB.Model(&models.InvChHolding{}).
		Where("challenge_id = ? AND user_id = ?", acc.Challenge.ID, userID).
		Distinct("stock_id").Pluck("stock_id", &stockIDs)
	if len(stockIDs) == 0 {
		c.JSON(http.StatusOK, []StockTrend{})
		return
	}
	var stocks []models.Stock
	_ = h.DB.Where("id IN ?", stockIDs).Find(&stocks)
	trends := make([]StockTrend, 0, len(stocks))
	for _, s := range stocks {
		trends = append(trends, stockTrendFromStock(s))
	}
	c.JSON(http.StatusOK, trends)
}

func (h *Handler) GetInvChPortfolio(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, false)
	if !ok {
		return
	}
	userID := middleware.CurrentUserID(c)
	holdings := h.invChHoldingsWithDetails(acc.Challenge.ID, userID)
	invested := 0.0
	current := 0.0
	var lots []models.InvChTransaction
	h.DB.Where("challenge_id = ? AND user_id = ? AND type = ?", acc.Challenge.ID, userID, models.TransactionTypeBuy).
		Find(&lots)
	currentByStock := map[uint]float64{}
	for _, hld := range holdings {
		invested += hld.AverageBuyPrice * hld.Quantity
		current += hld.CurrentPrice * hld.Quantity
		currentByStock[hld.ID] = hld.CurrentPrice
	}
	ustx := make([]models.UserStockTransaction, 0, len(lots))
	for _, lot := range lots {
		ustx = append(ustx, models.UserStockTransaction{
			StockID:          lot.StockID,
			Type:             lot.Type,
			Quantity:         lot.Quantity,
			OriginalQuantity: lot.OriginalQuantity,
			Price:            lot.Price,
			SalePrice:        lot.SalePrice,
			SaleDate:         lot.SaleDate,
			TransactionDate:  timePtr(lot.TransactionDate),
		})
	}
	xirrVal := xirrRateFromLots(ustx, currentByStock, time.Now())
	cash := acc.Member.CashBalance
	networth := cash + current
	pl := networth - acc.Challenge.InitialNetworth
	plPct := 0.0
	if acc.Challenge.InitialNetworth > 0 {
		plPct = (pl / acc.Challenge.InitialNetworth) * 100
	}
	c.JSON(http.StatusOK, gin.H{
		"cash":                   cash,
		"invested":               invested,
		"holdings_value":         current,
		"networth":               networth,
		"initial_networth":       acc.Challenge.InitialNetworth,
		"profit_loss":            pl,
		"profit_loss_percentage": plPct,
		"xirr":                   xirrVal,
		"holding_count":          len(holdings),
	})
}

func (h *Handler) GetInvChTransactions(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, false)
	if !ok {
		return
	}
	userID := middleware.CurrentUserID(c)
	q := h.DB.Preload("Stock").Where("challenge_id = ? AND user_id = ?", acc.Challenge.ID, userID)
	if symbol := strings.ToUpper(strings.TrimSpace(c.Query("symbol"))); symbol != "" {
		var stock models.Stock
		if err := h.DB.Where("UPPER(symbol) = ?", symbol).First(&stock).Error; err == nil {
			q = q.Where("stock_id = ?", stock.ID)
		}
	}
	var rows []models.InvChTransaction
	if err := q.Order("transaction_date DESC, id DESC").Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, rows)
}

func (h *Handler) RefreshInvChPrices(c *gin.Context) {
	if _, ok := h.requireActiveTrader(c, false); !ok {
		return
	}
	if err := h.RefreshAllStockPricesAndTrends(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	userID := middleware.CurrentUserID(c)
	id, _ := requireInvChID(c)
	c.JSON(http.StatusOK, h.invChHoldingsWithDetails(id, userID))
}

func (h *Handler) loadInvChHolding(challengeID, userID, stockID uint) (models.InvChHolding, error) {
	var pos models.InvChHolding
	err := h.DB.Where("challenge_id = ? AND user_id = ? AND stock_id = ?", challengeID, userID, stockID).First(&pos).Error
	return pos, err
}

func (h *Handler) InvChHold(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, true)
	if !ok {
		return
	}
	stockID, ok := invChStockID(c)
	if !ok {
		return
	}
	userID := middleware.CurrentUserID(c)
	pos, err := h.loadInvChHolding(acc.Challenge.ID, userID, stockID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "holding not found"})
		return
	}
	var stock models.Stock
	if err := h.DB.First(&stock, stockID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "stock not found"})
		return
	}
	if stock.CurrentPrice <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no live price available"})
		return
	}
	now := time.Now()
	pos.LastHoldPrice = stock.CurrentPrice
	pos.LastHoldDate = &now
	clearInvChThresholds(&pos)
	pos.BSHClearDate = nil
	if err := h.DB.Save(&pos).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"stock_id":        pos.StockID,
		"last_hold_price": pos.LastHoldPrice,
		"last_hold_date":  pos.LastHoldDate,
	})
}

func (h *Handler) SetInvChThresholds(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, false)
	if !ok {
		return
	}
	stockID, ok := invChStockID(c)
	if !ok {
		return
	}
	var req struct {
		SetBuyPrice           float64 `json:"set_buy_price"`
		SetProfitBookingPrice float64 `json:"set_profit_booking_price"`
		SetStopLossPrice      float64 `json:"set_stop_loss_price"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.SetBuyPrice < 0 || req.SetProfitBookingPrice < 0 || req.SetStopLossPrice < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "threshold prices cannot be negative"})
		return
	}
	pos, err := h.loadInvChHolding(acc.Challenge.ID, middleware.CurrentUserID(c), stockID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "holding not found"})
		return
	}
	pos.SetBuyPrice = req.SetBuyPrice
	pos.SetProfitBookingPrice = req.SetProfitBookingPrice
	pos.SetStopLossPrice = req.SetStopLossPrice
	if err := h.DB.Save(&pos).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"stock_id":                 pos.StockID,
		"set_buy_price":            pos.SetBuyPrice,
		"set_profit_booking_price": pos.SetProfitBookingPrice,
		"set_stop_loss_price":      pos.SetStopLossPrice,
	})
}

func (h *Handler) SetInvChNotes(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, false)
	if !ok {
		return
	}
	stockID, ok := invChStockID(c)
	if !ok {
		return
	}
	var req struct {
		Notes string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	notes := strings.TrimSpace(req.Notes)
	if utf8.RuneCountInString(notes) > maxStockNotesRunes {
		c.JSON(http.StatusBadRequest, gin.H{"error": "notes cannot exceed 200 characters"})
		return
	}
	pos, err := h.loadInvChHolding(acc.Challenge.ID, middleware.CurrentUserID(c), stockID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "holding not found"})
		return
	}
	pos.Notes = notes
	if err := h.DB.Save(&pos).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"stock_id": pos.StockID, "notes": pos.Notes})
}

func applyClearInvChReviewFields(pos *models.InvChHolding, fields []string, now time.Time) error {
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
		clearInvChThresholds(pos)
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

func (h *Handler) ClearInvChReviewValues(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, false)
	if !ok {
		return
	}
	stockID, ok := invChStockID(c)
	if !ok {
		return
	}
	var req struct {
		Fields []string `json:"fields"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	now := time.Now()
	var probe models.InvChHolding
	if err := applyClearInvChReviewFields(&probe, req.Fields, now); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	pos, err := h.loadInvChHolding(acc.Challenge.ID, middleware.CurrentUserID(c), stockID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "holding not found"})
		return
	}
	if err := applyClearInvChReviewFields(&pos, req.Fields, now); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.DB.Save(&pos).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"stock_id": pos.StockID, "bsh_clear_date": pos.BSHClearDate})
}

func (h *Handler) ClearAllInvChReviewValues(c *gin.Context) {
	acc, ok := h.requireActiveTrader(c, false)
	if !ok {
		return
	}
	var req struct {
		Fields []string `json:"fields"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	now := time.Now()
	var probe models.InvChHolding
	if err := applyClearInvChReviewFields(&probe, req.Fields, now); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	userID := middleware.CurrentUserID(c)
	var positions []models.InvChHolding
	if err := h.DB.Where("challenge_id = ? AND user_id = ?", acc.Challenge.ID, userID).Find(&positions).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	for i := range positions {
		if err := applyClearInvChReviewFields(&positions[i], req.Fields, now); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if err := h.DB.Save(&positions[i]).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	c.JSON(http.StatusOK, gin.H{"updated": len(positions)})
}
