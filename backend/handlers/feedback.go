package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const (
	maxFeedbackMessageRunes  = 2000
	maxFeedbackResponseRunes = 4000
	maxFeedbackScreenRunes   = 128
	defaultFeedbackPageSize  = 5
	maxFeedbackPageSize      = 20
)

type feedbackItem struct {
	models.Feedback
	Username string `json:"username,omitempty"`
}

func feedbackPageParams(c *gin.Context) (page, pageSize int) {
	page = 1
	if raw := strings.TrimSpace(c.Query("page")); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			page = n
		}
	}
	pageSize = defaultFeedbackPageSize
	if raw := strings.TrimSpace(c.Query("page_size")); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			pageSize = n
		}
	}
	if pageSize > maxFeedbackPageSize {
		pageSize = maxFeedbackPageSize
	}
	return page, pageSize
}

func normalizeScreenName(raw string) string {
	name := strings.TrimSpace(raw)
	if name == "" {
		return "Unknown"
	}
	if utf8.RuneCountInString(name) > maxFeedbackScreenRunes {
		runes := []rune(name)
		name = string(runes[:maxFeedbackScreenRunes])
	}
	return name
}

// SubmitFeedback creates a new feedback item for the current user.
func (h *Handler) SubmitFeedback(c *gin.Context) {
	var req struct {
		Message    string `json:"message" binding:"required"`
		ScreenName string `json:"screen_name"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	msg := strings.TrimSpace(req.Message)
	if msg == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message is required"})
		return
	}
	if utf8.RuneCountInString(msg) > maxFeedbackMessageRunes {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message cannot exceed 2000 characters"})
		return
	}

	row := models.Feedback{
		UserID:     middleware.CurrentUserID(c),
		ScreenName: normalizeScreenName(req.ScreenName),
		Message:    msg,
		Status:     models.FeedbackStatusOpen,
	}
	if err := h.DB.Create(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save feedback"})
		return
	}
	c.JSON(http.StatusCreated, row)
}

// ListMyFeedback returns paginated feedback for the current user.
func (h *Handler) ListMyFeedback(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	page, pageSize := feedbackPageParams(c)

	q := h.DB.Model(&models.Feedback{}).Where("user_id = ?", userID)
	var total int64
	if err := q.Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var items []models.Feedback
	offset := (page - 1) * pageSize
	if err := q.Order("created_at DESC").Offset(offset).Limit(pageSize).Find(&items).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"items":     items,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// ListFeedbackAdmin returns paginated feedback for all users (admin only).
// Query status: open (default), closed, all.
func (h *Handler) ListFeedbackAdmin(c *gin.Context) {
	page, pageSize := feedbackPageParams(c)
	status := strings.ToLower(strings.TrimSpace(c.Query("status")))
	if status == "" {
		status = models.FeedbackStatusOpen
	}
	if status != models.FeedbackStatusOpen && status != models.FeedbackStatusClosed && status != "all" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status filter"})
		return
	}

	q := h.DB.Model(&models.Feedback{})
	if status != "all" {
		q = q.Where("status = ?", status)
	}

	var total int64
	if err := q.Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var rows []models.Feedback
	offset := (page - 1) * pageSize
	if err := q.Order("created_at DESC").Offset(offset).Limit(pageSize).Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	userIDs := make([]uint, 0, len(rows))
	seen := map[uint]struct{}{}
	for _, row := range rows {
		if _, ok := seen[row.UserID]; ok {
			continue
		}
		seen[row.UserID] = struct{}{}
		userIDs = append(userIDs, row.UserID)
	}

	usernames := map[uint]string{}
	if len(userIDs) > 0 {
		var users []models.User
		if err := h.DB.Where("id IN ?", userIDs).Find(&users).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		for _, u := range users {
			if u.Username != nil {
				usernames[u.ID] = *u.Username
			}
		}
	}

	items := make([]feedbackItem, 0, len(rows))
	for _, row := range rows {
		items = append(items, feedbackItem{
			Feedback: row,
			Username: usernames[row.UserID],
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"items":     items,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// RespondToFeedback saves an admin response without closing the item.
func (h *Handler) RespondToFeedback(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid feedback id"})
		return
	}

	var req struct {
		Response string `json:"response" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	response := strings.TrimSpace(req.Response)
	if response == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "response is required"})
		return
	}
	if utf8.RuneCountInString(response) > maxFeedbackResponseRunes {
		c.JSON(http.StatusBadRequest, gin.H{"error": "response cannot exceed 4000 characters"})
		return
	}

	var row models.Feedback
	if err := h.DB.First(&row, uint(id)).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "feedback not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if row.Status == models.FeedbackStatusClosed {
		c.JSON(http.StatusBadRequest, gin.H{"error": "feedback is closed"})
		return
	}

	adminID := middleware.CurrentUserID(c)
	now := time.Now().UTC()
	row.AdminResponse = response
	row.RespondedAt = &now
	row.RespondedBy = &adminID
	if err := h.DB.Save(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save response"})
		return
	}
	c.JSON(http.StatusOK, row)
}

// CloseFeedback marks a feedback item as closed.
func (h *Handler) CloseFeedback(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid feedback id"})
		return
	}

	var row models.Feedback
	if err := h.DB.First(&row, uint(id)).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "feedback not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if row.Status == models.FeedbackStatusClosed {
		c.JSON(http.StatusOK, row)
		return
	}

	row.Status = models.FeedbackStatusClosed
	if err := h.DB.Save(&row).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to close feedback"})
		return
	}
	c.JSON(http.StatusOK, row)
}
