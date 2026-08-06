package middleware

import (
	"financetracker/auth"
	"financetracker/models"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const (
	ContextUserIDKey = "userID"
	ContextRoleKey   = "role"
	ContextUserKey   = "user"
)

func AuthRequired(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" || !strings.HasPrefix(header, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing or invalid authorization header"})
			return
		}
		tokenStr := strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
		claims, err := auth.ParseToken(tokenStr)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}

		var user models.User
		if err := db.First(&user, claims.UserID).Error; err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
			return
		}
		if !user.Enabled {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "account disabled"})
			return
		}

		c.Set(ContextUserIDKey, user.ID)
		c.Set(ContextRoleKey, user.Role)
		c.Set(ContextUserKey, user)
		c.Next()
	}
}

// OptionalAuth sets user context when a valid Bearer token is present.
// Invalid or missing tokens are ignored so public routes still work.
func OptionalAuth(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" || !strings.HasPrefix(header, "Bearer ") {
			c.Next()
			return
		}
		tokenStr := strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
		claims, err := auth.ParseToken(tokenStr)
		if err != nil {
			c.Next()
			return
		}
		var user models.User
		if err := db.First(&user, claims.UserID).Error; err != nil || !user.Enabled {
			c.Next()
			return
		}
		c.Set(ContextUserIDKey, user.ID)
		c.Set(ContextRoleKey, user.Role)
		c.Set(ContextUserKey, user)
		c.Next()
	}
}

func RequireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, _ := c.Get(ContextRoleKey)
		if role != models.RoleAdmin {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "admin access required"})
			return
		}
		c.Next()
	}
}

func CurrentUserID(c *gin.Context) uint {
	v, _ := c.Get(ContextUserIDKey)
	id, _ := v.(uint)
	return id
}
