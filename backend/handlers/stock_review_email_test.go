package handlers

import (
	"testing"

	"financetracker/models"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func TestStockReviewEmailEligible(t *testing.T) {
	email := "user@example.com"
	user := models.User{ID: 1, Email: &email, Enabled: true}

	if StockReviewEmailEligible(user, nil, false) {
		t.Fatal("expected not eligible without admin override")
	}

	cfg := &models.UserConfig{
		StockReviewEmailEnabled:      true,
		StockReviewEmailAdminEnabled: true,
	}
	if !StockReviewEmailEligible(user, cfg, true) {
		t.Fatal("expected eligible")
	}

	cfg.StockReviewEmailEnabled = false
	if StockReviewEmailEligible(user, cfg, true) {
		t.Fatal("expected not eligible when user opted out")
	}

	cfg.StockReviewEmailEnabled = true
	cfg.StockReviewEmailAdminEnabled = false
	if StockReviewEmailEligible(user, cfg, true) {
		t.Fatal("expected not eligible when admin disabled")
	}

	user.Enabled = false
	cfg.StockReviewEmailAdminEnabled = true
	if StockReviewEmailEligible(user, cfg, true) {
		t.Fatal("expected not eligible when user disabled")
	}
}

func TestStockReviewEmailPrefsDefaults(t *testing.T) {
	email := "a@b.com"
	user := models.User{Email: &email, Enabled: true}
	enabled, admin, effective := stockReviewEmailPrefs(user, nil, false)
	if !enabled || admin || effective {
		t.Fatalf("enabled=%v admin=%v effective=%v", enabled, admin, effective)
	}
}

func TestSendStockReviewEmailsSkipsIneligible(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	if err := db.AutoMigrate(&models.User{}, &models.UserConfig{}, &models.StockDataImportStatus{}, &models.AppConfig{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	_ = EnsureAppConfig(db)
	_ = EnsureImportStatuses(db)

	email := "test@example.com"
	username := "u1"
	user := models.User{Username: &username, Email: &email, Enabled: true, Role: models.RoleUser}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}

	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	if err := h.SendStockReviewEmails(models.ImportSourceManual, nil); err != nil {
		t.Fatalf("send: %v", err)
	}

	var status models.StockDataImportStatus
	if err := db.Where("kind = ?", models.ImportKindStockReviewEmail).First(&status).Error; err != nil {
		t.Fatalf("status: %v", err)
	}
	if status.LastStatus != models.ImportStatusSuccess {
		t.Fatalf("status=%q", status.LastStatus)
	}
}
