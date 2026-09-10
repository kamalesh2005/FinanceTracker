package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"financetracker/models"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func listUsersTestDB(t *testing.T) *gorm.DB {
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
	if err := db.AutoMigrate(
		&models.User{},
		&models.UserConfig{},
		&models.Stock{},
		&models.UserStock{},
		&models.InvChChallenge{},
		&models.InvChMember{},
	); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func TestListUsersIncludesStockAndChallengeCounts(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db := listUsersTestDB(t)
	h := &Handler{DB: db}

	u1 := models.User{Role: models.RoleUser, Enabled: true}
	u2 := models.User{Role: models.RoleUser, Enabled: true}
	u3 := models.User{Role: models.RoleAdmin, Enabled: true}
	if err := db.Create(&u1).Error; err != nil {
		t.Fatalf("create u1: %v", err)
	}
	if err := db.Create(&u2).Error; err != nil {
		t.Fatalf("create u2: %v", err)
	}
	if err := db.Create(&u3).Error; err != nil {
		t.Fatalf("create u3: %v", err)
	}

	s1 := models.Stock{Symbol: "TCS", Name: "TCS", PullData: models.PullDataNo}
	s2 := models.Stock{Symbol: "INFY", Name: "INFY", PullData: models.PullDataNo}
	s3 := models.Stock{Symbol: "RELIANCE", Name: "Reliance", PullData: models.PullDataNo}
	if err := db.Create(&s1).Error; err != nil {
		t.Fatalf("stock s1: %v", err)
	}
	if err := db.Create(&s2).Error; err != nil {
		t.Fatalf("stock s2: %v", err)
	}
	if err := db.Create(&s3).Error; err != nil {
		t.Fatalf("stock s3: %v", err)
	}

	// u1: TCS in two sources + INFY held + RELIANCE sold → 2 distinct live stocks.
	holdings := []models.UserStock{
		{UserID: u1.ID, StockID: s1.ID, Source: models.SourceICICIDirect, Quantity: 10},
		{UserID: u1.ID, StockID: s1.ID, Source: models.SourceZerodha, Quantity: 5},
		{UserID: u1.ID, StockID: s2.ID, Source: models.SourceManualAdd, Quantity: 2},
		{UserID: u1.ID, StockID: s3.ID, Source: models.SourceManualAdd, Quantity: 0},
		{UserID: u2.ID, StockID: s1.ID, Source: models.SourceManualAdd, Quantity: 1},
	}
	for i := range holdings {
		if err := db.Create(&holdings[i]).Error; err != nil {
			t.Fatalf("holding %d: %v", i, err)
		}
	}

	now := time.Now()
	chCreated := models.InvChChallenge{
		CreatorUserID: u1.ID, Name: "Alpha", InitialNetworth: 1e6,
		DurationDays: 30, StartsAt: now, EndsAt: now.AddDate(0, 0, 30), InviteCode: "AAAA1111",
	}
	chJoined := models.InvChChallenge{
		CreatorUserID: u2.ID, Name: "Beta", InitialNetworth: 1e6,
		DurationDays: 30, StartsAt: now, EndsAt: now.AddDate(0, 0, 30), InviteCode: "BBBB2222",
	}
	chPending := models.InvChChallenge{
		CreatorUserID: u2.ID, Name: "Gamma", InitialNetworth: 1e6,
		DurationDays: 30, StartsAt: now, EndsAt: now.AddDate(0, 0, 30), InviteCode: "CCCC3333",
	}
	if err := db.Create(&chCreated).Error; err != nil {
		t.Fatalf("ch created: %v", err)
	}
	if err := db.Create(&chJoined).Error; err != nil {
		t.Fatalf("ch joined: %v", err)
	}
	if err := db.Create(&chPending).Error; err != nil {
		t.Fatalf("ch pending: %v", err)
	}

	members := []models.InvChMember{
		{ChallengeID: chCreated.ID, UserID: &u1.ID, Status: models.InvChMemberActive, CashBalance: 1e6},
		{ChallengeID: chJoined.ID, UserID: &u2.ID, Status: models.InvChMemberActive, CashBalance: 1e6},
		{ChallengeID: chJoined.ID, UserID: &u1.ID, Status: models.InvChMemberActive, CashBalance: 1e6},
		{ChallengeID: chPending.ID, UserID: &u2.ID, Status: models.InvChMemberActive, CashBalance: 1e6},
		{ChallengeID: chPending.ID, UserID: &u3.ID, Status: models.InvChMemberPending, CashBalance: 0},
	}
	for i := range members {
		if err := db.Create(&members[i]).Error; err != nil {
			t.Fatalf("member %d: %v", i, err)
		}
	}

	r := gin.New()
	r.GET("/admin/users", h.ListUsers)
	req := httptest.NewRequest(http.MethodGet, "/admin/users", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}

	var rows []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &rows); err != nil {
		t.Fatalf("json: %v", err)
	}
	got := map[uint]map[string]any{}
	for _, row := range rows {
		id := uint(row["id"].(float64))
		got[id] = row
	}

	assertCount := func(userID uint, field string, want int) {
		t.Helper()
		row, ok := got[userID]
		if !ok {
			t.Fatalf("missing user %d", userID)
		}
		gotN, _ := row[field].(float64)
		if int(gotN) != want {
			t.Fatalf("user %d %s=%v want %d", userID, field, row[field], want)
		}
	}

	assertCount(u1.ID, "stock_count", 2)
	assertCount(u1.ID, "inv_challenge_count", 2)
	assertCount(u2.ID, "stock_count", 1)
	assertCount(u2.ID, "inv_challenge_count", 2)
	assertCount(u3.ID, "stock_count", 0)
	assertCount(u3.ID, "inv_challenge_count", 0)
}
