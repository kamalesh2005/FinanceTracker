package handlers

import (
	"errors"
	"financetracker/auth"
	"financetracker/models"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

var errGoogleEmailTaken = errors.New("google email taken by password account")

func (h *Handler) GoogleLogin(c *gin.Context) {
	if !auth.GoogleEnabled() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Google Sign-In is not configured"})
		return
	}

	var req struct {
		IDToken string `json:"idToken" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	verifier := h.GoogleVerifier
	if verifier == nil {
		verifier = auth.DefaultGoogleVerifier()
	}
	identity, err := verifier.VerifyIDToken(c.Request.Context(), req.IDToken)
	if err != nil {
		log.Printf("google login: token verify failed: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid Google token"})
		return
	}

	user, err := h.findOrCreateGoogleUser(identity)
	if err != nil {
		if errors.Is(err, errGoogleEmailTaken) {
			c.JSON(http.StatusConflict, gin.H{
				"error": "An account already exists with this email. Sign in with your password.",
			})
			return
		}
		log.Printf("google login: find or create failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to sign in with Google"})
		return
	}
	if !user.Enabled {
		c.JSON(http.StatusForbidden, gin.H{"error": "account disabled"})
		return
	}

	if err := h.touchLogin(&user); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update login stats"})
		return
	}

	h.writeAuthResponse(c, http.StatusOK, user)
}

func (h *Handler) findOrCreateGoogleUser(identity auth.GoogleIdentity) (models.User, error) {
	var user models.User
	if err := h.DB.Where("google_sub = ?", identity.Sub).First(&user).Error; err == nil {
		h.syncGoogleEmail(&user, identity.Email)
		return user, nil
	} else if err != gorm.ErrRecordNotFound {
		return models.User{}, err
	}

	if err := h.DB.Where("email = ?", identity.Email).First(&user).Error; err == nil {
		if user.GoogleAuth && (user.GoogleSub == nil || *user.GoogleSub == "") {
			sub := identity.Sub
			if err := h.DB.Model(&user).Update("google_sub", sub).Error; err != nil {
				return models.User{}, err
			}
			user.GoogleSub = &sub
			return user, nil
		}
		return models.User{}, errGoogleEmailTaken
	} else if err != gorm.ErrRecordNotFound {
		return models.User{}, err
	}

	email := identity.Email
	sub := identity.Sub
	user = models.User{
		Email:      &email,
		GoogleAuth: true,
		GoogleSub:  &sub,
		Role:       models.RoleUser,
		Enabled:    true,
	}
	if err := h.DB.Create(&user).Error; err != nil {
		return models.User{}, err
	}
	return user, nil
}

func (h *Handler) syncGoogleEmail(user *models.User, email string) {
	if email == "" || derefString(user.Email) == email {
		return
	}
	var other models.User
	err := h.DB.Where("email = ? AND id <> ?", email, user.ID).First(&other).Error
	if err == nil {
		return
	}
	if err != gorm.ErrRecordNotFound {
		log.Printf("google login: email uniqueness check failed: %v", err)
		return
	}
	if dbErr := h.DB.Model(user).Update("email", email).Error; dbErr != nil {
		log.Printf("google login: email update failed: %v", dbErr)
		return
	}
	user.Email = &email
}

func (h *Handler) touchLogin(user *models.User) error {
	now := time.Now().UTC()
	if err := h.DB.Model(user).Updates(map[string]interface{}{
		"last_login_at": now,
		"login_count":   gorm.Expr("login_count + 1"),
	}).Error; err != nil {
		return err
	}
	user.LastLoginAt = &now
	user.LoginCount++
	return nil
}

func googleOnlyAccount(user models.User) bool {
	return user.GoogleAuth && !user.HasPassword()
}
