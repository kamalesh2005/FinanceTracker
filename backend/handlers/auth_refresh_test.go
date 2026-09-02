package handlers

import (
	"bytes"
	"encoding/json"
	"financetracker/auth"
	"financetracker/models"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func authTokenTestDB(t *testing.T) *gorm.DB {
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
	if err := db.AutoMigrate(&models.User{}, &models.RefreshToken{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func TestRefresh_RotatesToken(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db := authTokenTestDB(t)
	h := &Handler{DB: db}
	user := models.User{Role: models.RoleUser, Enabled: true}
	if err := db.Create(&user).Error; err != nil {
		t.Fatal(err)
	}

	raw, err := auth.NewRefreshToken()
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.RefreshToken{
		UserID:    user.ID,
		TokenHash: auth.HashRefreshToken(raw),
		ExpiresAt: time.Now().Add(time.Hour),
	}).Error; err != nil {
		t.Fatal(err)
	}

	r := gin.New()
	r.POST("/auth/refresh", h.Refresh)
	body, _ := json.Marshal(map[string]string{"refresh_token": raw})
	req := httptest.NewRequest(http.MethodPost, "/auth/refresh", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	var resp map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp["token"] == "" || resp["refresh_token"] == "" {
		t.Fatalf("missing tokens: %v", resp)
	}
	if resp["refresh_token"] == raw {
		t.Fatal("expected rotated refresh token")
	}

	var count int64
	db.Model(&models.RefreshToken{}).Where("user_id = ?", user.ID).Count(&count)
	if count != 1 {
		t.Fatalf("expected 1 refresh token, got %d", count)
	}
}

func TestRefresh_RejectsExpired(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db := authTokenTestDB(t)
	h := &Handler{DB: db}
	user := models.User{Role: models.RoleUser, Enabled: true}
	if err := db.Create(&user).Error; err != nil {
		t.Fatal(err)
	}
	raw, err := auth.NewRefreshToken()
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.RefreshToken{
		UserID:    user.ID,
		TokenHash: auth.HashRefreshToken(raw),
		ExpiresAt: time.Now().Add(-time.Minute),
	}).Error; err != nil {
		t.Fatal(err)
	}

	r := gin.New()
	r.POST("/auth/refresh", h.Refresh)
	body, _ := json.Marshal(map[string]string{"refresh_token": raw})
	req := httptest.NewRequest(http.MethodPost, "/auth/refresh", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}
