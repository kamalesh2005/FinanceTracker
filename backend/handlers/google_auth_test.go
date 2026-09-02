package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"financetracker/auth"
	"financetracker/models"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

type fakeGoogleVerifier struct {
	identity auth.GoogleIdentity
	err      error
}

func (f fakeGoogleVerifier) VerifyIDToken(_ context.Context, _ string) (auth.GoogleIdentity, error) {
	if f.err != nil {
		return auth.GoogleIdentity{}, f.err
	}
	return f.identity, nil
}

func googleTestHandler(t *testing.T, v auth.GoogleTokenVerifier) *Handler {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := gorm.Open(sqlite.Open("file:" + t.Name() + "?mode=memory&cache=shared"), &gorm.Config{})
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
	return &Handler{DB: db, GoogleVerifier: v}
}

func postJSON(h gin.HandlerFunc, path string, body any) *httptest.ResponseRecorder {
	b, _ := json.Marshal(body)
	r := gin.New()
	r.POST(path, h)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestGoogleLogin_NotConfigured(t *testing.T) {
	t.Setenv("GOOGLE_CLIENT_ID", "")
	h := googleTestHandler(t, fakeGoogleVerifier{
		identity: auth.GoogleIdentity{Sub: "sub-1", Email: "a@gmail.com"},
	})
	w := postJSON(h.GoogleLogin, "/auth/google", map[string]string{"idToken": "tok"})
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestGoogleLogin_VerifyFailure(t *testing.T) {
	t.Setenv("GOOGLE_CLIENT_ID", "test-client.apps.googleusercontent.com")
	h := googleTestHandler(t, fakeGoogleVerifier{err: errors.New("bad token")})
	w := postJSON(h.GoogleLogin, "/auth/google", map[string]string{"idToken": "tok"})
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestGoogleLogin_CreatesUserWithoutPassword(t *testing.T) {
	t.Setenv("GOOGLE_CLIENT_ID", "test-client.apps.googleusercontent.com")
	h := googleTestHandler(t, fakeGoogleVerifier{
		identity: auth.GoogleIdentity{Sub: "sub-new", Email: "new@gmail.com"},
	})
	w := postJSON(h.GoogleLogin, "/auth/google", map[string]string{"idToken": "tok"})
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload["token"] == nil || payload["token"] == "" {
		t.Fatalf("missing token: %v", payload)
	}
	userJSON, _ := payload["user"].(map[string]any)
	if userJSON["google_auth"] != true {
		t.Fatalf("google_auth=%v", userJSON["google_auth"])
	}
	if userJSON["email"] != "new@gmail.com" {
		t.Fatalf("email=%v", userJSON["email"])
	}

	var stored models.User
	if err := h.DB.Where("google_sub = ?", "sub-new").First(&stored).Error; err != nil {
		t.Fatal(err)
	}
	if !stored.GoogleAuth {
		t.Fatal("expected google_auth")
	}
	if stored.HasPassword() {
		t.Fatal("password should not be stored")
	}
	if stored.PasswordHash != nil {
		t.Fatalf("password_hash=%v", *stored.PasswordHash)
	}
}

func TestGoogleLogin_SecondLoginSameSub(t *testing.T) {
	t.Setenv("GOOGLE_CLIENT_ID", "test-client.apps.googleusercontent.com")
	h := googleTestHandler(t, fakeGoogleVerifier{
		identity: auth.GoogleIdentity{Sub: "sub-repeat", Email: "repeat@gmail.com"},
	})
	if w := postJSON(h.GoogleLogin, "/auth/google", map[string]string{"idToken": "tok"}); w.Code != http.StatusOK {
		t.Fatalf("first: status=%d body=%s", w.Code, w.Body.String())
	}
	if w := postJSON(h.GoogleLogin, "/auth/google", map[string]string{"idToken": "tok"}); w.Code != http.StatusOK {
		t.Fatalf("second: status=%d body=%s", w.Code, w.Body.String())
	}
	var count int64
	if err := h.DB.Model(&models.User{}).Where("google_sub = ?", "sub-repeat").Count(&count).Error; err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("count=%d", count)
	}
	var stored models.User
	if err := h.DB.Where("google_sub = ?", "sub-repeat").First(&stored).Error; err != nil {
		t.Fatal(err)
	}
	if stored.LoginCount != 2 {
		t.Fatalf("login_count=%d", stored.LoginCount)
	}
}

func TestGoogleLogin_EmailCollisionWithPasswordUser(t *testing.T) {
	t.Setenv("GOOGLE_CLIENT_ID", "test-client.apps.googleusercontent.com")
	h := googleTestHandler(t, fakeGoogleVerifier{
		identity: auth.GoogleIdentity{Sub: "sub-collide", Email: "taken@gmail.com"},
	})
	hash, err := auth.HashPassword("secret1")
	if err != nil {
		t.Fatal(err)
	}
	email := "taken@gmail.com"
	existing := models.User{
		Email:        &email,
		PasswordHash: &hash,
		Role:         models.RoleUser,
		Enabled:      true,
	}
	if err := h.DB.Create(&existing).Error; err != nil {
		t.Fatal(err)
	}

	w := postJSON(h.GoogleLogin, "/auth/google", map[string]string{"idToken": "tok"})
	if w.Code != http.StatusConflict {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	var count int64
	if err := h.DB.Model(&models.User{}).Count(&count).Error; err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("should not create a second user, count=%d", count)
	}
}

func TestLogin_GoogleOnlyAccountRejected(t *testing.T) {
	h := googleTestHandler(t, nil)
	email := "googleonly@gmail.com"
	sub := "sub-only"
	user := models.User{
		Email:      &email,
		GoogleAuth: true,
		GoogleSub:  &sub,
		Role:       models.RoleUser,
		Enabled:    true,
	}
	if err := h.DB.Create(&user).Error; err != nil {
		t.Fatal(err)
	}

	w := postJSON(h.Login, "/auth/login", map[string]string{
		"identifier": email,
		"password":   "anything",
	})
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte("Google Sign-In")) {
		t.Fatalf("body=%s", w.Body.String())
	}
}

func TestCaptchaConfig_IncludesGoogleFields(t *testing.T) {
	t.Setenv("GOOGLE_CLIENT_ID", "web-client.apps.googleusercontent.com")
	h := googleTestHandler(t, nil)
	r := gin.New()
	r.GET("/auth/captcha-config", h.CaptchaConfig)
	req := httptest.NewRequest(http.MethodGet, "/auth/captcha-config", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d", w.Code)
	}
	var payload map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload["googleEnabled"] != true {
		t.Fatalf("googleEnabled=%v", payload["googleEnabled"])
	}
	if payload["googleClientId"] != "web-client.apps.googleusercontent.com" {
		t.Fatalf("googleClientId=%v", payload["googleClientId"])
	}
}
