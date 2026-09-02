package handlers

import (
	"financetracker/auth"
	"financetracker/models"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func (h *Handler) persistRefreshToken(userID uint, refresh string) error {
	record := models.RefreshToken{
		UserID:    userID,
		TokenHash: auth.HashRefreshToken(refresh),
		ExpiresAt: time.Now().Add(auth.RefreshTokenTTL()),
	}
	return h.DB.Create(&record).Error
}

func (h *Handler) writeAuthResponse(c *gin.Context, status int, user models.User) {
	access, err := auth.GenerateToken(user.ID, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create token"})
		return
	}
	refresh, err := auth.NewRefreshToken()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create refresh token"})
		return
	}
	if err := h.persistRefreshToken(user.ID, refresh); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store refresh token"})
		return
	}
	c.JSON(status, gin.H{
		"token":         access,
		"refresh_token": refresh,
		"user":          publicUser(user),
	})
}

// Refresh exchanges a valid refresh token for a new access/refresh token pair.
func (h *Handler) Refresh(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := auth.ValidateRefreshTokenFormat(req.RefreshToken); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired refresh token"})
		return
	}

	hash := auth.HashRefreshToken(req.RefreshToken)
	var record models.RefreshToken
	err := h.DB.Where("token_hash = ?", hash).First(&record).Error
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired refresh token"})
		return
	}
	if time.Now().After(record.ExpiresAt) {
		_ = h.DB.Delete(&record).Error
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired refresh token"})
		return
	}

	var user models.User
	if err := h.DB.First(&user, record.UserID).Error; err != nil {
		_ = h.DB.Delete(&record).Error
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired refresh token"})
		return
	}
	if !user.Enabled {
		_ = h.revokeRefreshTokensForUser(user.ID)
		c.JSON(http.StatusForbidden, gin.H{"error": "account disabled"})
		return
	}

	var access, refresh string
	if err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Delete(&record).Error; err != nil {
			return err
		}
		var genErr error
		access, genErr = auth.GenerateToken(user.ID, user.Role)
		if genErr != nil {
			return genErr
		}
		refresh, genErr = auth.NewRefreshToken()
		if genErr != nil {
			return genErr
		}
		newRecord := models.RefreshToken{
			UserID:    user.ID,
			TokenHash: auth.HashRefreshToken(refresh),
			ExpiresAt: time.Now().Add(auth.RefreshTokenTTL()),
		}
		return tx.Create(&newRecord).Error
	}); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to refresh session"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token":         access,
		"refresh_token": refresh,
		"user":          publicUser(user),
	})
}

func (h *Handler) revokeRefreshTokensForUser(userID uint) error {
	return h.DB.Where("user_id = ?", userID).Delete(&models.RefreshToken{}).Error
}
