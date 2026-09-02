package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func feedbackTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("db: %v", err)
	}
	sqlDB.SetMaxOpenConns(1)
	if err := db.AutoMigrate(&models.User{}, &models.Feedback{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func seedUser(t *testing.T, db *gorm.DB, username string) models.User {
	t.Helper()
	uname := username
	email := username + "@example.com"
	u := models.User{Username: &uname, Email: &email, Enabled: true}
	if err := db.Create(&u).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	return u
}

func feedbackRouter(h *Handler, userID uint, admin bool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	wrap := func(handler gin.HandlerFunc) gin.HandlerFunc {
		return func(c *gin.Context) {
			c.Set(middleware.ContextUserIDKey, userID)
			if admin {
				c.Set(middleware.ContextRoleKey, models.RoleAdmin)
			}
			handler(c)
		}
	}
	r.POST("/feedback", wrap(h.SubmitFeedback))
	r.GET("/feedback", wrap(h.ListMyFeedback))
	r.GET("/admin/feedback", wrap(h.ListFeedbackAdmin))
	r.PUT("/admin/feedback/:id/respond", wrap(h.RespondToFeedback))
	r.PUT("/admin/feedback/:id/close", wrap(h.CloseFeedback))
	return r
}

func TestSubmitFeedback_AndListMine(t *testing.T) {
	db := feedbackTestDB(t)
	u1 := seedUser(t, db, "alice")
	u2 := seedUser(t, db, "bob")
	h := &Handler{DB: db}

	r1 := feedbackRouter(h, u1.ID, false)
	body, _ := json.Marshal(gin.H{"message": "  bug on stocks  ", "screen_name": "Stocks"})
	req := httptest.NewRequest(http.MethodPost, "/feedback", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r1.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("submit status=%d body=%s", w.Code, w.Body.String())
	}

	r2 := feedbackRouter(h, u2.ID, false)
	body, _ = json.Marshal(gin.H{"message": "other user feedback"})
	req = httptest.NewRequest(http.MethodPost, "/feedback", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	r2.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("submit2 status=%d body=%s", w.Code, w.Body.String())
	}

	req = httptest.NewRequest(http.MethodGet, "/feedback?page=1&page_size=5", nil)
	w = httptest.NewRecorder()
	r1.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("list status=%d body=%s", w.Code, w.Body.String())
	}
	var resp struct {
		Items []models.Feedback `json:"items"`
		Total int64             `json:"total"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Total != 1 || len(resp.Items) != 1 {
		t.Fatalf("total=%d items=%d want 1", resp.Total, len(resp.Items))
	}
	if resp.Items[0].Message != "bug on stocks" {
		t.Fatalf("message=%q", resp.Items[0].Message)
	}
	if resp.Items[0].ScreenName != "Stocks" {
		t.Fatalf("screen=%q want Stocks", resp.Items[0].ScreenName)
	}
}

func TestListFeedbackAdmin_DefaultOpenOnly(t *testing.T) {
	db := feedbackTestDB(t)
	u := seedUser(t, db, "alice")
	h := &Handler{DB: db}
	r := feedbackRouter(h, u.ID, false)

	for i := 0; i < 2; i++ {
		body, _ := json.Marshal(gin.H{"message": fmt.Sprintf("msg %d", i)})
		req := httptest.NewRequest(http.MethodPost, "/feedback", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if w.Code != http.StatusCreated {
			t.Fatalf("submit %d status=%d", i, w.Code)
		}
	}

	var created models.Feedback
	if err := db.Order("id ASC").First(&created).Error; err != nil {
		t.Fatalf("load: %v", err)
	}
	created.Status = models.FeedbackStatusClosed
	if err := db.Save(&created).Error; err != nil {
		t.Fatalf("close: %v", err)
	}

	admin := feedbackRouter(h, u.ID, true)
	req := httptest.NewRequest(http.MethodGet, "/admin/feedback", nil)
	w := httptest.NewRecorder()
	admin.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("admin list status=%d body=%s", w.Code, w.Body.String())
	}
	var resp struct {
		Items []feedbackItem `json:"items"`
		Total int64          `json:"total"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Total != 1 || len(resp.Items) != 1 {
		t.Fatalf("open total=%d items=%d want 1", resp.Total, len(resp.Items))
	}
	if resp.Items[0].Username != "alice" {
		t.Fatalf("username=%q", resp.Items[0].Username)
	}
}

func TestRespondAndCloseFeedback(t *testing.T) {
	db := feedbackTestDB(t)
	u := seedUser(t, db, "alice")
	h := &Handler{DB: db}
	userR := feedbackRouter(h, u.ID, false)
	adminR := feedbackRouter(h, u.ID, true)

	body, _ := json.Marshal(gin.H{"message": "help"})
	req := httptest.NewRequest(http.MethodPost, "/feedback", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	userR.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("submit status=%d", w.Code)
	}
	var row models.Feedback
	if err := json.Unmarshal(w.Body.Bytes(), &row); err != nil {
		t.Fatalf("decode: %v", err)
	}

	body, _ = json.Marshal(gin.H{"response": "  thanks, fixed  "})
	req = httptest.NewRequest(http.MethodPut, fmt.Sprintf("/admin/feedback/%d/respond", row.ID), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	adminR.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("respond status=%d body=%s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &row); err != nil {
		t.Fatalf("decode respond: %v", err)
	}
	if row.AdminResponse != "thanks, fixed" || row.Status != models.FeedbackStatusOpen {
		t.Fatalf("after respond response=%q status=%q", row.AdminResponse, row.Status)
	}

	req = httptest.NewRequest(http.MethodPut, fmt.Sprintf("/admin/feedback/%d/close", row.ID), nil)
	w = httptest.NewRecorder()
	adminR.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("close status=%d body=%s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &row); err != nil {
		t.Fatalf("decode close: %v", err)
	}
	if row.Status != models.FeedbackStatusClosed {
		t.Fatalf("status=%q want closed", row.Status)
	}

	body, _ = json.Marshal(gin.H{"response": "late"})
	req = httptest.NewRequest(http.MethodPut, fmt.Sprintf("/admin/feedback/%d/respond", row.ID), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	adminR.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("respond closed status=%d want 400", w.Code)
	}
}

func TestSubmitFeedback_RejectsOverLength(t *testing.T) {
	db := feedbackTestDB(t)
	u := seedUser(t, db, "alice")
	h := &Handler{DB: db}
	r := feedbackRouter(h, u.ID, false)

	body, _ := json.Marshal(gin.H{"message": strings.Repeat("a", 2001)})
	req := httptest.NewRequest(http.MethodPost, "/feedback", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("status=%d want 400", w.Code)
	}
}
