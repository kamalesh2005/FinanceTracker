package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func defaultPortalHandler(t *testing.T) (*Handler, models.User) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("db: %v", err)
	}
	sqlDB.SetMaxOpenConns(1)
	if err := db.AutoMigrate(&models.User{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	user := models.User{Role: models.RoleUser, Enabled: true}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	return &Handler{DB: db}, user
}

func TestUpdateDefaultPortal(t *testing.T) {
	h, user := defaultPortalHandler(t)

	put := func(body any) *httptest.ResponseRecorder {
		b, _ := json.Marshal(body)
		r := gin.New()
		r.Use(func(c *gin.Context) {
			c.Set(middleware.ContextUserKey, user)
			c.Next()
		})
		r.PUT("/auth/default-portal", h.UpdateDefaultPortal)
		req := httptest.NewRequest(http.MethodPut, "/auth/default-portal", bytes.NewReader(b))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		return w
	}

	w := put(map[string]string{"default_portal": "learner"})
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatalf("json: %v", err)
	}
	if payload["default_portal"] != models.DefaultPortalLearner {
		t.Fatalf("payload default_portal=%v", payload["default_portal"])
	}

	var stored models.User
	if err := h.DB.First(&stored, user.ID).Error; err != nil {
		t.Fatalf("reload: %v", err)
	}
	if stored.EffectiveDefaultPortal() != models.DefaultPortalLearner {
		t.Fatalf("stored default_portal=%s", stored.DefaultPortal)
	}

	w = put(map[string]string{"default_portal": "stocks"})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("invalid portal status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestPublicUserIncludesDefaultPortal(t *testing.T) {
	u := models.User{ID: 1, Role: models.RoleUser, Enabled: true}
	got := publicUser(u)["default_portal"]
	if got != models.DefaultPortalMain {
		t.Fatalf("empty default_portal json=%v", got)
	}
	u.DefaultPortal = models.DefaultPortalLearner
	got = publicUser(u)["default_portal"]
	if got != models.DefaultPortalLearner {
		t.Fatalf("learner default_portal json=%v", got)
	}
}
