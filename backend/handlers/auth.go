package handlers

import (
	"crypto/rand"
	"financetracker/auth"
	"financetracker/middleware"
	"financetracker/models"
	"financetracker/notify"
	"fmt"
	"math/big"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

var usernamePattern = regexp.MustCompile(`^[a-z0-9_]{3,64}$`)

var (
	forgotMu    sync.Mutex
	forgotHits  = map[string]time.Time{}
	forgotLimit = 30 * time.Second
)

func normalizeEmail(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

func normalizeMobile(s string) string {
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, " ", "")
	s = strings.ReplaceAll(s, "-", "")
	return s
}

func normalizeUsername(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

// validateUsernameFormat checks normalized username length and charset.
func validateUsernameFormat(username string) error {
	if !usernamePattern.MatchString(username) {
		return fmt.Errorf("username must be 3–64 characters and contain only letters, numbers, and underscores")
	}
	return nil
}

func ptrString(s string) *string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return &s
}

func derefString(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

func generateOTPCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

func (h *Handler) CheckUsername(c *gin.Context) {
	username := normalizeUsername(c.Query("username"))
	if err := validateUsernameFormat(username); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var existing models.User
	err := h.DB.Where("LOWER(username) = ?", username).First(&existing).Error
	if err == nil {
		c.JSON(http.StatusOK, gin.H{"available": false})
		return
	}
	if err != gorm.ErrRecordNotFound {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check username"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"available": true})
}

func (h *Handler) Register(c *gin.Context) {
	var req struct {
		Username string `json:"username" binding:"required"`
		Email    string `json:"email"`
		Mobile   string `json:"mobile"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if len(req.Password) < 6 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "password must be at least 6 characters"})
		return
	}

	username := normalizeUsername(req.Username)
	if err := validateUsernameFormat(username); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	email := normalizeEmail(req.Email)
	mobile := normalizeMobile(req.Mobile)

	var existing models.User
	if err := h.DB.Where("LOWER(username) = ?", username).First(&existing).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "username already taken"})
		return
	} else if err != gorm.ErrRecordNotFound {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check username"})
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
		PasswordHash: hash,
		Role:         models.RoleUser,
		Enabled:      true,
	}
	if err := h.DB.Create(&user).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "username, email, or mobile already registered"})
		return
	}

	token, err := auth.GenerateToken(user.ID, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create token"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"token": token, "user": publicUser(user)})
}

func (h *Handler) Login(c *gin.Context) {
	var req struct {
		Identifier string `json:"identifier" binding:"required"`
		Password   string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.findUserByIdentifier(req.Identifier)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}
	if !user.Enabled {
		c.JSON(http.StatusForbidden, gin.H{"error": "account disabled"})
		return
	}
	if !auth.CheckPassword(user.PasswordHash, req.Password) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	now := time.Now().UTC()
	if err := h.DB.Model(&user).Updates(map[string]interface{}{
		"last_login_at": now,
		"login_count":   gorm.Expr("login_count + 1"),
	}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update login stats"})
		return
	}
	user.LastLoginAt = &now
	user.LoginCount++

	token, err := auth.GenerateToken(user.ID, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create token"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"token": token, "user": publicUser(user)})
}

func (h *Handler) findUserByIdentifier(identifier string) (models.User, error) {
	identifier = strings.TrimSpace(identifier)
	var user models.User

	email := normalizeEmail(identifier)
	if strings.Contains(email, "@") {
		if err := h.DB.Where("email = ?", email).First(&user).Error; err == nil {
			return user, nil
		}
	}

	mobile := normalizeMobile(identifier)
	if mobile != "" {
		if err := h.DB.Where("mobile = ?", mobile).First(&user).Error; err == nil {
			return user, nil
		}
	}

	username := strings.ToLower(identifier)
	if err := h.DB.Where("LOWER(username) = ?", username).First(&user).Error; err == nil {
		return user, nil
	}
	return user, gorm.ErrRecordNotFound
}

func (h *Handler) Me(c *gin.Context) {
	v, _ := c.Get(middleware.ContextUserKey)
	user, ok := v.(models.User)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	c.JSON(http.StatusOK, publicUser(user))
}

func (h *Handler) ForgotPassword(c *gin.Context) {
	var req struct {
		Identifier string `json:"identifier" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	key := strings.ToLower(strings.TrimSpace(req.Identifier))
	forgotMu.Lock()
	if last, ok := forgotHits[key]; ok && time.Since(last) < forgotLimit {
		forgotMu.Unlock()
		c.JSON(http.StatusOK, gin.H{"message": "If an account exists, a reset code has been sent"})
		return
	}
	forgotHits[key] = time.Now()
	forgotMu.Unlock()

	user, err := h.findUserByIdentifier(req.Identifier)
	if err != nil {
		// Do not reveal whether the account exists.
		c.JSON(http.StatusOK, gin.H{"message": "If an account exists, a reset code has been sent"})
		return
	}

	code, err := generateOTPCode()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate code"})
		return
	}
	codeHash, err := auth.HashPassword(code)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store code"})
		return
	}

	expires := time.Now().Add(10 * time.Minute)
	sent := false

	if email := derefString(user.Email); email != "" {
		otp := models.PasswordResetOTP{
			UserID:      user.ID,
			Channel:     models.OTPChannelEmail,
			Destination: email,
			CodeHash:    codeHash,
			ExpiresAt:   expires,
		}
		if err := h.DB.Create(&otp).Error; err == nil {
			_ = notify.SendEmailOTP(email, code)
			sent = true
		}
	}
	if mobile := derefString(user.Mobile); mobile != "" {
		otp := models.PasswordResetOTP{
			UserID:      user.ID,
			Channel:     models.OTPChannelSMS,
			Destination: mobile,
			CodeHash:    codeHash,
			ExpiresAt:   expires,
		}
		if err := h.DB.Create(&otp).Error; err == nil {
			_ = notify.SendSMSOTP(mobile, code)
			sent = true
		}
	}

	if !sent {
		// Admin username-only accounts: still create an email-channel OTP logged to console.
		otp := models.PasswordResetOTP{
			UserID:      user.ID,
			Channel:     models.OTPChannelEmail,
			Destination: "console",
			CodeHash:    codeHash,
			ExpiresAt:   expires,
		}
		_ = h.DB.Create(&otp).Error
		_ = notify.SendEmailOTP("console@"+derefString(user.Username), code)
	}

	c.JSON(http.StatusOK, gin.H{"message": "If an account exists, a reset code has been sent"})
}

func (h *Handler) ResetPassword(c *gin.Context) {
	var req struct {
		Identifier  string `json:"identifier" binding:"required"`
		Code        string `json:"code" binding:"required"`
		NewPassword string `json:"new_password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if len(req.NewPassword) < 6 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "password must be at least 6 characters"})
		return
	}

	user, err := h.findUserByIdentifier(req.Identifier)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid code or identifier"})
		return
	}

	var otps []models.PasswordResetOTP
	if err := h.DB.Where("user_id = ? AND used_at IS NULL AND expires_at > ?", user.ID, time.Now()).
		Order("created_at DESC").
		Limit(10).
		Find(&otps).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var matched *models.PasswordResetOTP
	for i := range otps {
		if auth.CheckPassword(otps[i].CodeHash, strings.TrimSpace(req.Code)) {
			matched = &otps[i]
			break
		}
	}
	if matched == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid or expired code"})
		return
	}

	hash, err := auth.HashPassword(req.NewPassword)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	now := time.Now()
	if err := h.DB.Model(&user).Update("password_hash", hash).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	_ = h.DB.Model(matched).Update("used_at", now).Error

	c.JSON(http.StatusOK, gin.H{"message": "password updated"})
}

func publicUser(u models.User) gin.H {
	return gin.H{
		"id":            u.ID,
		"username":      u.Username,
		"email":         u.Email,
		"mobile":        u.Mobile,
		"role":          u.Role,
		"enabled":       u.Enabled,
		"last_login_at": u.LastLoginAt,
		"login_count":   u.LoginCount,
	}
}

// SeedAdminUser creates the default admin account if missing.
func SeedAdminUser(db *gorm.DB) (*models.User, error) {
	var existing models.User
	err := db.Where("username = ?", "admin").First(&existing).Error
	if err == nil {
		return &existing, nil
	}
	if err != gorm.ErrRecordNotFound {
		return nil, err
	}

	hash, err := auth.HashPassword("Khanak")
	if err != nil {
		return nil, err
	}
	username := "admin"
	admin := models.User{
		Username:     &username,
		PasswordHash: hash,
		Role:         models.RoleAdmin,
		Enabled:      true,
	}
	if err := db.Create(&admin).Error; err != nil {
		return nil, err
	}
	return &admin, nil
}

// BackfillUserScopedData assigns orphan positions/ledger/MFs to the given user.
func BackfillUserScopedData(db *gorm.DB, userID uint) error {
	if err := db.Model(&models.UserStock{}).Where("user_id = 0 OR user_id IS NULL").
		Update("user_id", userID).Error; err != nil {
		return err
	}
	if err := db.Model(&models.UserStockTransaction{}).Where("user_id = 0 OR user_id IS NULL").
		Update("user_id", userID).Error; err != nil {
		return err
	}
	if err := db.Model(&models.MutualFund{}).Where("user_id = 0 OR user_id IS NULL").
		Update("user_id", userID).Error; err != nil {
		return err
	}
	return nil
}
