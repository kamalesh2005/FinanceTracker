package handlers

import (
	"financetracker/auth"
	"financetracker/middleware"
	"financetracker/models"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

func (h *Handler) ListUsers(c *gin.Context) {
	var users []models.User
	if err := h.DB.Order("id ASC").Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	out := make([]gin.H, 0, len(users))
	for _, u := range users {
		out = append(out, publicUser(u))
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
		PasswordHash: hash,
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
