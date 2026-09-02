package handlers

import (
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"strconv"
	"strings"
	"time"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const invChInviteAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var (
	errInvChNotFound     = errors.New("challenge not found")
	errInvChForbidden    = errors.New("not a member of this challenge")
	errInvChEnded        = errors.New("challenge has ended")
	errInvChNotActive    = errors.New("not an active member of this challenge")
	errInvChInsufficient = errors.New("insufficient cash")
	errInvChFee          = errors.New("sell proceeds must exceed the transaction fee")
)

type invChAccess struct {
	Challenge models.InvChChallenge
	Member    models.InvChMember
	IsCreator bool
}

func generateInviteCode() (string, error) {
	buf := make([]byte, 8)
	for i := range buf {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(invChInviteAlphabet))))
		if err != nil {
			return "", err
		}
		buf[i] = invChInviteAlphabet[n.Int64()]
	}
	return string(buf), nil
}

func invChEnded(ch models.InvChChallenge, now time.Time) bool {
	return !now.Before(ch.EndsAt)
}

func invChTradingOpen(ch models.InvChChallenge, now time.Time) bool {
	return !now.Before(ch.StartsAt) && now.Before(ch.EndsAt)
}

func invChDisplayName(u models.User, fallback string) string {
	if u.Username != nil && strings.TrimSpace(*u.Username) != "" {
		return strings.TrimSpace(*u.Username)
	}
	if u.Email != nil && strings.TrimSpace(*u.Email) != "" {
		return strings.TrimSpace(*u.Email)
	}
	if u.Mobile != nil && strings.TrimSpace(*u.Mobile) != "" {
		return strings.TrimSpace(*u.Mobile)
	}
	if strings.TrimSpace(fallback) != "" {
		return strings.TrimSpace(fallback)
	}
	return fmt.Sprintf("User %d", u.ID)
}

func ptrUint(v uint) *uint { return &v }

func (h *Handler) uniqueInviteCode() (string, error) {
	for i := 0; i < 12; i++ {
		code, err := generateInviteCode()
		if err != nil {
			return "", err
		}
		var count int64
		if err := h.DB.Model(&models.InvChChallenge{}).Where("invite_code = ?", code).Count(&count).Error; err != nil {
			return "", err
		}
		if count == 0 {
			return code, nil
		}
	}
	return "", fmt.Errorf("failed to allocate invite code")
}

func (h *Handler) loadInvChAccess(challengeID, userID uint) (invChAccess, error) {
	var acc invChAccess
	if err := h.DB.First(&acc.Challenge, challengeID).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return acc, errInvChNotFound
		}
		return acc, err
	}
	acc.IsCreator = acc.Challenge.CreatorUserID == userID
	err := h.DB.Where("challenge_id = ? AND user_id = ? AND status = ?", challengeID, userID, models.InvChMemberActive).
		First(&acc.Member).Error
	if err == nil {
		return acc, nil
	}
	if err != gorm.ErrRecordNotFound {
		return acc, err
	}
	if acc.IsCreator {
		return acc, nil
	}
	return acc, errInvChForbidden
}

func writeInvChAccessError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, errInvChNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
	case errors.Is(err, errInvChForbidden):
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
	}
}

func requireInvChID(c *gin.Context) (uint, bool) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || id == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid challenge id"})
		return 0, false
	}
	return uint(id), true
}

type invChMemberInput struct {
	UserID        *uint  `json:"user_id"`
	Identifier    string `json:"identifier"`
	DisplayName   string `json:"display_name"`
	InvitedEmail  string `json:"invited_email"`
	InvitedMobile string `json:"invited_mobile"`
}

func lookupUserForInvCh(db *gorm.DB, identifier string, userID *uint) (models.User, error) {
	if userID != nil && *userID > 0 {
		var u models.User
		if err := db.First(&u, *userID).Error; err != nil {
			return u, err
		}
		return u, nil
	}
	idStr := strings.TrimSpace(identifier)
	if idStr == "" {
		return models.User{}, gorm.ErrRecordNotFound
	}
	if n, err := strconv.ParseUint(idStr, 10, 32); err == nil && n > 0 && !strings.Contains(idStr, "@") {
		var u models.User
		if err := db.First(&u, uint(n)).Error; err == nil {
			return u, nil
		}
	}
	return findUserByIdentifierOn(db, idStr)
}

func (h *Handler) addInvChMemberRow(tx *gorm.DB, ch models.InvChChallenge, in invChMemberInput, now time.Time) (models.InvChMember, error) {
	email := normalizeEmail(in.InvitedEmail)
	mobile := normalizeMobile(in.InvitedMobile)
	name := strings.TrimSpace(in.DisplayName)

	if u, err := lookupUserForInvCh(tx, in.Identifier, in.UserID); err == nil && u.ID > 0 {
		var existing models.InvChMember
		dup := tx.Where("challenge_id = ? AND user_id = ?", ch.ID, u.ID).First(&existing).Error
		if dup == nil {
			return existing, fmt.Errorf("user is already on the team")
		}
		if dup != gorm.ErrRecordNotFound {
			return models.InvChMember{}, dup
		}
		joined := now
		m := models.InvChMember{
			ChallengeID:   ch.ID,
			UserID:        ptrUint(u.ID),
			Status:        models.InvChMemberActive,
			DisplayName:   invChDisplayName(u, name),
			InvitedEmail:  "",
			InvitedMobile: "",
			CashBalance:   ch.InitialNetworth,
			JoinedAt:      &joined,
		}
		if err := tx.Create(&m).Error; err != nil {
			return models.InvChMember{}, err
		}
		return m, nil
	}

	if name == "" && email == "" && mobile == "" {
		return models.InvChMember{}, fmt.Errorf("existing user not found; provide a name, email, or phone for a pending invite")
	}
	m := models.InvChMember{
		ChallengeID:   ch.ID,
		Status:        models.InvChMemberPending,
		DisplayName:   name,
		InvitedEmail:  email,
		InvitedMobile: mobile,
		CashBalance:   0,
	}
	if err := tx.Create(&m).Error; err != nil {
		return models.InvChMember{}, err
	}
	return m, nil
}

func (h *Handler) ListInvChallenges(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var ids []uint
	if err := h.DB.Model(&models.InvChMember{}).
		Where("user_id = ? AND status = ?", userID, models.InvChMemberActive).
		Distinct("challenge_id").
		Pluck("challenge_id", &ids).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	q := h.DB.Model(&models.InvChChallenge{}).Where("creator_user_id = ?", userID)
	if len(ids) > 0 {
		q = h.DB.Model(&models.InvChChallenge{}).Where("creator_user_id = ? OR id IN ?", userID, ids)
	}
	var rows []models.InvChChallenge
	if err := q.Order("created_at DESC").Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	now := time.Now()
	out := make([]gin.H, 0, len(rows))
	for _, ch := range rows {
		var memberCount int64
		_ = h.DB.Model(&models.InvChMember{}).Where("challenge_id = ? AND status = ?", ch.ID, models.InvChMemberActive).Count(&memberCount).Error
		var me models.InvChMember
		cash := 0.0
		if err := h.DB.Where("challenge_id = ? AND user_id = ? AND status = ?", ch.ID, userID, models.InvChMemberActive).First(&me).Error; err == nil {
			cash = me.CashBalance
		}
		out = append(out, gin.H{
			"id":               ch.ID,
			"name":             ch.Name,
			"initial_networth": ch.InitialNetworth,
			"duration_days":    ch.DurationDays,
			"starts_at":        ch.StartsAt,
			"ends_at":          ch.EndsAt,
			"invite_code":      ch.InviteCode,
			"is_creator":       ch.CreatorUserID == userID,
			"ended":            invChEnded(ch, now),
			"member_count":     memberCount,
			"my_cash":          cash,
			"created_at":       ch.CreatedAt,
		})
	}
	c.JSON(http.StatusOK, out)
}

func (h *Handler) CreateInvChallenge(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var req struct {
		Name            string             `json:"name"`
		InitialNetworth float64            `json:"initial_networth"`
		DurationDays    int                `json:"duration_days"`
		Members         []invChMemberInput `json:"members"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name is required"})
		return
	}
	if req.InitialNetworth <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "initial_networth must be greater than 0"})
		return
	}
	if req.DurationDays < 1 || req.DurationDays > 3650 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "duration_days must be between 1 and 3650"})
		return
	}

	code, err := h.uniqueInviteCode()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	now := time.Now()
	ch := models.InvChChallenge{
		CreatorUserID:   userID,
		Name:            name,
		InitialNetworth: req.InitialNetworth,
		DurationDays:    req.DurationDays,
		StartsAt:        now,
		EndsAt:          now.AddDate(0, 0, req.DurationDays),
		InviteCode:      code,
	}

	var creator models.User
	if err := h.DB.First(&creator, userID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	err = h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&ch).Error; err != nil {
			return err
		}
		joined := now
		me := models.InvChMember{
			ChallengeID: ch.ID,
			UserID:      ptrUint(userID),
			Status:      models.InvChMemberActive,
			DisplayName: invChDisplayName(creator, ""),
			CashBalance: ch.InitialNetworth,
			JoinedAt:    &joined,
		}
		if err := tx.Create(&me).Error; err != nil {
			return err
		}
		for _, in := range req.Members {
			if in.UserID != nil && *in.UserID == userID {
				continue
			}
			id := strings.TrimSpace(in.Identifier)
			if n, err := strconv.ParseUint(id, 10, 32); err == nil && uint(n) == userID {
				continue
			}
			if _, err := h.addInvChMemberRow(tx, ch, in, now); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, h.invChDetailJSON(ch, userID, now))
}

func (h *Handler) GetInvChallenge(c *gin.Context) {
	id, ok := requireInvChID(c)
	if !ok {
		return
	}
	userID := middleware.CurrentUserID(c)
	acc, err := h.loadInvChAccess(id, userID)
	if err != nil {
		writeInvChAccessError(c, err)
		return
	}
	c.JSON(http.StatusOK, h.invChDetailJSON(acc.Challenge, userID, time.Now()))
}

func (h *Handler) GetInvChallengeInvite(c *gin.Context) {
	id, ok := requireInvChID(c)
	if !ok {
		return
	}
	userID := middleware.CurrentUserID(c)
	acc, err := h.loadInvChAccess(id, userID)
	if err != nil {
		writeInvChAccessError(c, err)
		return
	}
	if !acc.IsCreator {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the creator can view the invite code"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"invite_code": acc.Challenge.InviteCode,
		"invite_path": "/?learner_invite=" + acc.Challenge.InviteCode,
	})
}

func (h *Handler) invChDetailJSON(ch models.InvChChallenge, userID uint, now time.Time) gin.H {
	var members []models.InvChMember
	_ = h.DB.Where("challenge_id = ?", ch.ID).Order("id ASC").Find(&members).Error
	isCreator := ch.CreatorUserID == userID
	outMembers := make([]gin.H, 0, len(members))
	myCash := 0.0
	for _, m := range members {
		row := gin.H{
			"id":           m.ID,
			"status":       m.Status,
			"display_name": m.DisplayName,
			"cash_balance": m.CashBalance,
			"joined_at":    m.JoinedAt,
		}
		if m.UserID != nil {
			row["user_id"] = *m.UserID
			if *m.UserID == userID {
				myCash = m.CashBalance
			}
		}
		if isCreator {
			row["invited_email"] = m.InvitedEmail
			row["invited_mobile"] = m.InvitedMobile
		}
		outMembers = append(outMembers, row)
	}
	holdingsValue := invChHoldingsValue(h.DB, ch.ID, userID)
	return gin.H{
		"id":                ch.ID,
		"name":              ch.Name,
		"initial_networth":  ch.InitialNetworth,
		"duration_days":     ch.DurationDays,
		"starts_at":         ch.StartsAt,
		"ends_at":           ch.EndsAt,
		"invite_code":       ch.InviteCode,
		"is_creator":        isCreator,
		"ended":             invChEnded(ch, now),
		"trading_open":      invChTradingOpen(ch, now),
		"my_cash":           myCash,
		"my_holdings_value": holdingsValue,
		"my_networth":       myCash + holdingsValue,
		"members":           outMembers,
		"created_at":        ch.CreatedAt,
	}
}

func invChHoldingsValue(db *gorm.DB, challengeID, userID uint) float64 {
	type row struct {
		Quantity     float64
		CurrentPrice float64
	}
	var rows []row
	_ = db.Table(`"Inv_Ch_Holdings" AS h`).
		Select(`h.quantity, s.current_price`).
		Joins(`JOIN "Global_Stocks" AS s ON s.id = h.stock_id`).
		Where("h.challenge_id = ? AND h.user_id = ?", challengeID, userID).
		Scan(&rows).Error
	total := 0.0
	for _, r := range rows {
		total += r.Quantity * r.CurrentPrice
	}
	return total
}

func (h *Handler) LookupInvChUser(c *gin.Context) {
	identifier := strings.TrimSpace(c.Query("identifier"))
	if identifier == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "identifier is required"})
		return
	}
	u, err := lookupUserForInvCh(h.DB, identifier, nil)
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"id":       u.ID,
		"username": u.Username,
		"email":    u.Email,
		"mobile":   u.Mobile,
	})
}

func (h *Handler) JoinInvChallenge(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var req struct {
		InviteCode string `json:"invite_code"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	code := strings.ToUpper(strings.TrimSpace(req.InviteCode))
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invite_code is required"})
		return
	}
	var ch models.InvChChallenge
	if err := h.DB.Where("UPPER(invite_code) = ?", code).First(&ch).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "invite code not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	var me models.User
	if err := h.DB.First(&me, userID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	now := time.Now()
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		var existing models.InvChMember
		err := tx.Where("challenge_id = ? AND user_id = ?", ch.ID, userID).First(&existing).Error
		if err == nil {
			if existing.Status != models.InvChMemberActive {
				existing.Status = models.InvChMemberActive
				existing.CashBalance = ch.InitialNetworth
				existing.DisplayName = invChDisplayName(me, existing.DisplayName)
				joined := now
				existing.JoinedAt = &joined
				return tx.Save(&existing).Error
			}
			return nil
		}
		if err != gorm.ErrRecordNotFound {
			return err
		}

		email := ""
		if me.Email != nil {
			email = normalizeEmail(*me.Email)
		}
		mobile := ""
		if me.Mobile != nil {
			mobile = normalizeMobile(*me.Mobile)
		}

		var pending []models.InvChMember
		q := tx.Where("challenge_id = ? AND status = ? AND user_id IS NULL", ch.ID, models.InvChMemberPending)
		_ = q.Order("id ASC").Find(&pending).Error
		for i := range pending {
			match := false
			if email != "" && pending[i].InvitedEmail != "" && pending[i].InvitedEmail == email {
				match = true
			}
			if mobile != "" && pending[i].InvitedMobile != "" && pending[i].InvitedMobile == mobile {
				match = true
			}
			if match {
				pending[i].UserID = ptrUint(userID)
				pending[i].Status = models.InvChMemberActive
				pending[i].CashBalance = ch.InitialNetworth
				pending[i].DisplayName = invChDisplayName(me, pending[i].DisplayName)
				joined := now
				pending[i].JoinedAt = &joined
				return tx.Save(&pending[i]).Error
			}
		}

		joined := now
		m := models.InvChMember{
			ChallengeID: ch.ID,
			UserID:      ptrUint(userID),
			Status:      models.InvChMemberActive,
			DisplayName: invChDisplayName(me, ""),
			CashBalance: ch.InitialNetworth,
			JoinedAt:    &joined,
		}
		return tx.Create(&m).Error
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.invChDetailJSON(ch, userID, now))
}

func (h *Handler) AddInvChMember(c *gin.Context) {
	id, ok := requireInvChID(c)
	if !ok {
		return
	}
	userID := middleware.CurrentUserID(c)
	acc, err := h.loadInvChAccess(id, userID)
	if err != nil {
		writeInvChAccessError(c, err)
		return
	}
	if !acc.IsCreator {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the creator can add members"})
		return
	}
	var in invChMemberInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	now := time.Now()
	if _, err := h.addInvChMemberRow(h.DB, acc.Challenge, in, now); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.invChDetailJSON(acc.Challenge, userID, now))
}

func (h *Handler) DeleteInvChMember(c *gin.Context) {
	id, ok := requireInvChID(c)
	if !ok {
		return
	}
	mid, err := strconv.ParseUint(c.Param("mid"), 10, 32)
	if err != nil || mid == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid member id"})
		return
	}
	userID := middleware.CurrentUserID(c)
	acc, err := h.loadInvChAccess(id, userID)
	if err != nil {
		writeInvChAccessError(c, err)
		return
	}
	if !acc.IsCreator {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the creator can remove members"})
		return
	}
	var m models.InvChMember
	if err := h.DB.Where("id = ? AND challenge_id = ?", uint(mid), id).First(&m).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	}
	if m.UserID != nil && *m.UserID == acc.Challenge.CreatorUserID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot remove the challenge creator"})
		return
	}
	if m.Status == models.InvChMemberActive && m.UserID != nil {
		var txnCount int64
		_ = h.DB.Model(&models.InvChTransaction{}).
			Where("challenge_id = ? AND user_id = ?", id, *m.UserID).
			Count(&txnCount)
		if txnCount > 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "cannot remove a member who has traded"})
			return
		}
	}
	if err := h.DB.Delete(&m).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, h.invChDetailJSON(acc.Challenge, userID, time.Now()))
}

func (h *Handler) GetInvChLeaderboard(c *gin.Context) {
	id, ok := requireInvChID(c)
	if !ok {
		return
	}
	userID := middleware.CurrentUserID(c)
	acc, err := h.loadInvChAccess(id, userID)
	if err != nil {
		writeInvChAccessError(c, err)
		return
	}
	c.JSON(http.StatusOK, h.invChLeaderboard(acc.Challenge))
}

func (h *Handler) invChLeaderboard(ch models.InvChChallenge) []gin.H {
	var members []models.InvChMember
	_ = h.DB.Where("challenge_id = ? AND status = ?", ch.ID, models.InvChMemberActive).
		Order("id ASC").Find(&members).Error
	type hv struct {
		UserID uint
		Value  float64
	}
	var values []hv
	_ = h.DB.Table(`"Inv_Ch_Holdings" AS h`).
		Select(`h.user_id, COALESCE(SUM(h.quantity * s.current_price), 0) AS value`).
		Joins(`JOIN "Global_Stocks" AS s ON s.id = h.stock_id`).
		Where("h.challenge_id = ?", ch.ID).
		Group("h.user_id").
		Scan(&values).Error
	byUser := map[uint]float64{}
	for _, v := range values {
		byUser[v.UserID] = v.Value
	}
	type ranked struct {
		row   gin.H
		worth float64
		id    uint
	}
	items := make([]ranked, 0, len(members))
	for _, m := range members {
		uid := uint(0)
		if m.UserID != nil {
			uid = *m.UserID
		}
		hv := byUser[uid]
		nw := m.CashBalance + hv
		pl := nw - ch.InitialNetworth
		plPct := 0.0
		if ch.InitialNetworth > 0 {
			plPct = (pl / ch.InitialNetworth) * 100
		}
		items = append(items, ranked{
			id:    m.ID,
			worth: nw,
			row: gin.H{
				"member_id":       m.ID,
				"user_id":         m.UserID,
				"display_name":    m.DisplayName,
				"cash":            m.CashBalance,
				"holdings_value":  hv,
				"networth":        nw,
				"profit_loss":     pl,
				"profit_loss_pct": plPct,
			},
		})
	}
	for i := 0; i < len(items); i++ {
		for j := i + 1; j < len(items); j++ {
			if items[j].worth > items[i].worth+1e-9 || (almostEqual(items[j].worth, items[i].worth) && items[j].id < items[i].id) {
				items[i], items[j] = items[j], items[i]
			}
		}
	}
	out := make([]gin.H, 0, len(items))
	for i, it := range items {
		it.row["rank"] = i + 1
		out = append(out, it.row)
	}
	return out
}

func almostEqual(a, b float64) bool {
	d := a - b
	if d < 0 {
		d = -d
	}
	return d < 1e-9
}

// RegisterInvChallengeRoutes mounts Learner Portal APIs on an authenticated group.
func RegisterInvChallengeRoutes(g *gin.RouterGroup, h *Handler) {
	g.GET("/inv-challenges", h.ListInvChallenges)
	g.POST("/inv-challenges", h.CreateInvChallenge)
	g.POST("/inv-challenges/join", h.JoinInvChallenge)
	g.GET("/inv-challenges/lookup-user", h.LookupInvChUser)
	g.GET("/inv-challenges/:id", h.GetInvChallenge)
	g.GET("/inv-challenges/:id/invite", h.GetInvChallengeInvite)
	g.POST("/inv-challenges/:id/members", h.AddInvChMember)
	g.DELETE("/inv-challenges/:id/members/:mid", h.DeleteInvChMember)
	g.GET("/inv-challenges/:id/leaderboard", h.GetInvChLeaderboard)
	g.GET("/inv-challenges/:id/holdings", h.GetInvChHoldings)
	g.GET("/inv-challenges/:id/trends", h.GetInvChTrends)
	g.GET("/inv-challenges/:id/portfolio", h.GetInvChPortfolio)
	g.POST("/inv-challenges/:id/buy", h.InvChBuy)
	g.POST("/inv-challenges/:id/sell", h.InvChSell)
	g.GET("/inv-challenges/:id/transactions", h.GetInvChTransactions)
	g.POST("/inv-challenges/:id/refresh-prices", h.RefreshInvChPrices)
	g.POST("/inv-challenges/:id/clear-review-values", h.ClearAllInvChReviewValues)
	g.POST("/inv-challenges/:id/holdings/:stockId/hold", h.InvChHold)
	g.PUT("/inv-challenges/:id/holdings/:stockId/thresholds", h.SetInvChThresholds)
	g.PUT("/inv-challenges/:id/holdings/:stockId/notes", h.SetInvChNotes)
	g.POST("/inv-challenges/:id/holdings/:stockId/clear-review-values", h.ClearInvChReviewValues)
}
