package handlers

import (
	"financetracker/auth"
	"financetracker/middleware"
	"financetracker/models"
	"financetracker/recrules"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func (h *Handler) ListUsers(c *gin.Context) {
	var users []models.User
	if err := h.DB.Order("id ASC").Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var configs []models.UserConfig
	_ = h.DB.Find(&configs).Error
	cfgByUser := make(map[uint]models.UserConfig, len(configs))
	for _, cfg := range configs {
		cfgByUser[cfg.UserID] = cfg
	}

	stockCounts, challengeCounts := adminUserActivityCounts(h.DB)

	out := make([]gin.H, 0, len(users))
	for _, u := range users {
		row := publicUser(u)
		row["stock_count"] = stockCounts[u.ID]
		row["inv_challenge_count"] = challengeCounts[u.ID]
		cfg, ok := cfgByUser[u.ID]
		if !ok {
			row["recommendation_fluctuation_pct"] = nil
			row["recommendation_rules_is_override"] = false
			row["recommendation_rules_count"] = 0
			row["recommendation_rules"] = nil
			enabled, adminEnabled, effective := stockReviewEmailPrefs(u, nil, false)
			row["stock_review_email_enabled"] = enabled
			row["stock_review_email_admin_enabled"] = adminEnabled
			row["stock_review_email_effective"] = effective
			out = append(out, row)
			continue
		}

		hasRulesOverride := cfg.RecommendationRulesJSON != nil &&
			strings.TrimSpace(*cfg.RecommendationRulesJSON) != ""
		var fluct any
		rulesCount := 0
		var rulesMap any
		if hasRulesOverride {
			if rs, err := recrules.Parse(*cfg.RecommendationRulesJSON); err == nil {
				rulesCount = len(rs.Rules)
				rulesMap = rs.ToMap()
				if v := recrules.FluctuationFromRuleset(rs, 0); v > 0 {
					fluct = v
				}
			}
		}
		if fluct == nil && cfg.RecommendationFluctuationPct != nil && *cfg.RecommendationFluctuationPct > 0 {
			fluct = *cfg.RecommendationFluctuationPct
		}

		row["recommendation_fluctuation_pct"] = fluct
		row["recommendation_rules_is_override"] = hasRulesOverride
		row["recommendation_rules_count"] = rulesCount
		row["recommendation_rules"] = rulesMap
		enabled, adminEnabled, effective := stockReviewEmailPrefs(u, &cfg, true)
		row["stock_review_email_enabled"] = enabled
		row["stock_review_email_admin_enabled"] = adminEnabled
		row["stock_review_email_effective"] = effective
		out = append(out, row)
	}
	c.JSON(http.StatusOK, out)
}

func (h *Handler) CreateUser(c *gin.Context) {
	var req struct {
		Username string `json:"username"`
		Email    string `json:"email"`
		Mobile   string `json:"mobile"`
		Password string `json:"password" binding:"required"`
		Role     string `json:"role"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if len(req.Password) < 6 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "password must be at least 6 characters"})
		return
	}

	username := strings.TrimSpace(req.Username)
	email := normalizeEmail(req.Email)
	mobile := normalizeMobile(req.Mobile)
	if username == "" && email == "" && mobile == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "username, email, or mobile is required"})
		return
	}

	role := strings.TrimSpace(req.Role)
	if role == "" {
		role = models.RoleUser
	}
	if role != models.RoleUser && role != models.RoleAdmin {
		c.JSON(http.StatusBadRequest, gin.H{"error": "role must be admin or user"})
		return
	}

	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	user := models.User{
		Username:     ptrString(username),
		Email:        ptrString(email),
		Mobile:       ptrString(mobile),
		PasswordHash: &hash,
		Role:         role,
		Enabled:      true,
	}
	if err := h.DB.Create(&user).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "username, email, or mobile already exists"})
		return
	}
	c.JSON(http.StatusCreated, publicUser(user))
}

func (h *Handler) SetUserEnabled(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}

	var req struct {
		Enabled bool `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	currentID := middleware.CurrentUserID(c)
	if uint(id) == currentID && !req.Enabled {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot disable your own account"})
		return
	}

	var user models.User
	if err := h.DB.First(&user, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	if user.Role == models.RoleAdmin && !req.Enabled {
		var adminCount int64
		h.DB.Model(&models.User{}).Where("role = ? AND enabled = ?", models.RoleAdmin, true).Count(&adminCount)
		if adminCount <= 1 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "cannot disable the last admin"})
			return
		}
	}

	if err := h.DB.Model(&user).Update("enabled", req.Enabled).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	user.Enabled = req.Enabled
	c.JSON(http.StatusOK, publicUser(user))
}

// adminUserActivityCounts returns per-user DhanShanti stock holdings and
// FlexStreet investment challenges (created or actively joined).
func adminUserActivityCounts(db *gorm.DB) (stocks map[uint]int, challenges map[uint]int) {
	stocks = map[uint]int{}
	challenges = map[uint]int{}

	type idCount struct {
		UserID uint  `gorm:"column:user_id"`
		Count  int64 `gorm:"column:count"`
	}
	var stockRows []idCount
	_ = db.Model(&models.UserStock{}).
		Select("user_id, COUNT(DISTINCT stock_id) AS count").
		Where("quantity > ?", 0).
		Group("user_id").
		Scan(&stockRows).Error
	for _, r := range stockRows {
		stocks[r.UserID] = int(r.Count)
	}

	type userChallenge struct {
		UserID      uint `gorm:"column:user_id"`
		ChallengeID uint `gorm:"column:challenge_id"`
	}
	seen := map[uint]map[uint]struct{}{}
	add := func(userID, challengeID uint) {
		if userID == 0 || challengeID == 0 {
			return
		}
		m, ok := seen[userID]
		if !ok {
			m = map[uint]struct{}{}
			seen[userID] = m
		}
		m[challengeID] = struct{}{}
	}

	var members []userChallenge
	_ = db.Model(&models.InvChMember{}).
		Select("user_id, challenge_id").
		Where("status = ? AND user_id IS NOT NULL", models.InvChMemberActive).
		Scan(&members).Error
	for _, r := range members {
		add(r.UserID, r.ChallengeID)
	}

	var created []userChallenge
	_ = db.Model(&models.InvChChallenge{}).
		Select("creator_user_id AS user_id, id AS challenge_id").
		Scan(&created).Error
	for _, r := range created {
		add(r.UserID, r.ChallengeID)
	}

	for userID, set := range seen {
		challenges[userID] = len(set)
	}
	return stocks, challenges
}
