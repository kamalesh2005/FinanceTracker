package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func invChTestDB(t *testing.T) *gorm.DB {
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
		&models.Stock{},
		&models.InvChChallenge{},
		&models.InvChMember{},
		&models.InvChHolding{},
		&models.InvChTransaction{},
	); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func invChSeedUser(t *testing.T, db *gorm.DB, username, email, mobile string) models.User {
	t.Helper()
	u := models.User{Role: models.RoleUser, Enabled: true}
	if username != "" {
		u.Username = &username
	}
	if email != "" {
		u.Email = &email
	}
	if mobile != "" {
		u.Mobile = &mobile
	}
	if err := db.Create(&u).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	return u
}

func invChSeedStock(t *testing.T, db *gorm.DB, symbol string, price float64) models.Stock {
	t.Helper()
	s := models.Stock{Symbol: symbol, Name: symbol + " Ltd", CurrentPrice: price, PullData: models.PullDataNo}
	if err := db.Create(&s).Error; err != nil {
		t.Fatalf("create stock: %v", err)
	}
	return s
}

func invChRouter(h *Handler) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(func(c *gin.Context) {
		if raw := c.GetHeader("X-Test-User"); raw != "" {
			id, _ := strconv.ParseUint(raw, 10, 32)
			c.Set(middleware.ContextUserIDKey, uint(id))
		}
		c.Next()
	})
	g := r.Group("")
	RegisterInvChallengeRoutes(g, h)
	return r
}

func invChDo(r *gin.Engine, method, path string, userID uint, body any) *httptest.ResponseRecorder {
	var buf *bytes.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		buf = bytes.NewReader(b)
	} else {
		buf = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, buf)
	req.Header.Set("X-Test-User", strconv.FormatUint(uint64(userID), 10))
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestInvChCreateIsolatesCashAndJoinCopiesAmount(t *testing.T) {
	db := invChTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	r := invChRouter(h)
	a := invChSeedUser(t, db, "alice", "alice@example.com", "9990001111")
	b := invChSeedUser(t, db, "bob", "bob@example.com", "9990002222")

	w := invChDo(r, http.MethodPost, "/inv-challenges", a.ID, map[string]any{
		"name":             "Week 1",
		"initial_networth": 100000,
		"duration_days":    30,
		"members": []map[string]any{
			{"identifier": "bob@example.com"},
			{"display_name": "Pending Pal", "invited_email": "pal@example.com"},
		},
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create status=%d body=%s", w.Code, w.Body.String())
	}
	var created map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	if created["invite_code"] == "" {
		t.Fatal("missing invite code")
	}
	members, _ := created["members"].([]any)
	if len(members) != 3 {
		t.Fatalf("want 3 members, got %d", len(members))
	}

	w = invChDo(r, http.MethodGet, "/inv-challenges/"+strconv.Itoa(int(created["id"].(float64))), b.ID, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("bob get status=%d body=%s", w.Code, w.Body.String())
	}
	var bobView map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &bobView)
	if bobView["my_cash"].(float64) != 100000 {
		t.Fatalf("bob cash=%v want 100000", bobView["my_cash"])
	}

	pal := invChSeedUser(t, db, "pal", "pal@example.com", "")
	w = invChDo(r, http.MethodPost, "/inv-challenges/join", pal.ID, map[string]string{
		"invite_code": created["invite_code"].(string),
	})
	if w.Code != http.StatusOK {
		t.Fatalf("join status=%d body=%s", w.Code, w.Body.String())
	}
	var palView map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &palView)
	if palView["my_cash"].(float64) != 100000 {
		t.Fatalf("pal cash=%v want independent 100000", palView["my_cash"])
	}
}

func TestInvChBuySellFeeAndCash(t *testing.T) {
	db := invChTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	r := invChRouter(h)
	u := invChSeedUser(t, db, "trader", "t@example.com", "")
	invChSeedStock(t, db, "RELIANCE", 1000)

	w := invChDo(r, http.MethodPost, "/inv-challenges", u.ID, map[string]any{
		"name": "Cash Test", "initial_networth": 50000, "duration_days": 7,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create=%d %s", w.Code, w.Body.String())
	}
	var ch map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &ch)
	id := strconv.Itoa(int(ch["id"].(float64)))

	w = invChDo(r, http.MethodPost, "/inv-challenges/"+id+"/buy", u.ID, map[string]any{
		"symbol": "RELIANCE", "quantity": 10,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("buy=%d %s", w.Code, w.Body.String())
	}
	var buy map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &buy)
	// 10*1000 + 20 = 10020; cash 50000-10020=39980
	if buy["cash"].(float64) != 39980 {
		t.Fatalf("cash after buy=%v want 39980", buy["cash"])
	}

	w = invChDo(r, http.MethodPost, "/inv-challenges/"+id+"/sell", u.ID, map[string]any{
		"symbol": "RELIANCE", "quantity": 4,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("sell=%d %s", w.Code, w.Body.String())
	}
	var sell map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &sell)
	// credit 4000-20=3980; cash 39980+3980=43960
	if sell["cash"].(float64) != 43960 {
		t.Fatalf("cash after sell=%v want 43960", sell["cash"])
	}

	w = invChDo(r, http.MethodPost, "/inv-challenges/"+id+"/buy", u.ID, map[string]any{
		"symbol": "RELIANCE", "quantity": 100,
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("overspend status=%d want 400 body=%s", w.Code, w.Body.String())
	}
}

func TestInvChFIFOAndLeaderboard(t *testing.T) {
	db := invChTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	r := invChRouter(h)
	a := invChSeedUser(t, db, "a", "a@example.com", "")
	invChSeedUser(t, db, "b", "b@example.com", "")
	invChSeedStock(t, db, "INFY", 200)

	w := invChDo(r, http.MethodPost, "/inv-challenges", a.ID, map[string]any{
		"name": "LB", "initial_networth": 10000, "duration_days": 5,
		"members": []map[string]any{{"identifier": "b@example.com"}},
	})
	var ch map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &ch)
	id := strconv.Itoa(int(ch["id"].(float64)))

	if w := invChDo(r, http.MethodPost, "/inv-challenges/"+id+"/buy", a.ID, map[string]any{
		"symbol": "INFY", "quantity": 10,
	}); w.Code != http.StatusCreated {
		t.Fatalf("a buy=%d %s", w.Code, w.Body.String())
	}
	if w := invChDo(r, http.MethodPost, "/inv-challenges/"+id+"/sell", a.ID, map[string]any{
		"symbol": "INFY", "quantity": 3,
	}); w.Code != http.StatusCreated {
		t.Fatalf("a sell=%d %s", w.Code, w.Body.String())
	}

	var buys []models.InvChTransaction
	db.Where("type = ? AND user_id = ?", models.TransactionTypeBuy, a.ID).Order("id ASC").Find(&buys)
	open := 0.0
	for _, lot := range buys {
		open += lot.Quantity
	}
	if open < 6.9 || open > 7.1 {
		t.Fatalf("open buy qty=%v want 7", open)
	}

	w = invChDo(r, http.MethodGet, "/inv-challenges/"+id+"/leaderboard", a.ID, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("lb=%d %s", w.Code, w.Body.String())
	}
	var board []map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &board)
	if len(board) != 2 {
		t.Fatalf("leaderboard len=%d", len(board))
	}
	if int(board[0]["rank"].(float64)) != 1 {
		t.Fatalf("rank0=%v", board[0]["rank"])
	}
	// B never traded, still 10000 cash. A spent fees so networth should be lower.
	if board[0]["display_name"] != "b" {
		t.Fatalf("expected b first (no fees), got %v networth=%v vs %v", board[0]["display_name"], board[0]["networth"], board[1]["networth"])
	}
}

func TestInvChDurationLocksTrading(t *testing.T) {
	db := invChTestDB(t)
	u := invChSeedUser(t, db, "late", "late@example.com", "")
	invChSeedStock(t, db, "TCS", 50)
	now := time.Now()
	ch := models.InvChChallenge{
		CreatorUserID:   u.ID,
		Name:            "Ended",
		InitialNetworth: 5000,
		DurationDays:    1,
		StartsAt:        now.Add(-48 * time.Hour),
		EndsAt:          now.Add(-24 * time.Hour),
		InviteCode:      "ENDED001",
	}
	if err := db.Create(&ch).Error; err != nil {
		t.Fatal(err)
	}
	joined := now.Add(-48 * time.Hour)
	m := models.InvChMember{
		ChallengeID: ch.ID, UserID: ptrUint(u.ID), Status: models.InvChMemberActive,
		DisplayName: "late", CashBalance: 5000, JoinedAt: &joined,
	}
	db.Create(&m)

	_, err := applyInvChTrade(db, ch.ID, u.ID, models.TransactionTypeBuy, "TCS", 1, now)
	if err == nil || err != errInvChEnded {
		t.Fatalf("want ended error, got %v", err)
	}
}

func TestInvChLookupUserByIDEmailPhone(t *testing.T) {
	db := invChTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	r := invChRouter(h)
	me := invChSeedUser(t, db, "me", "me@example.com", "")
	other := invChSeedUser(t, db, "other", "other@example.com", "8881112222")

	w := invChDo(r, http.MethodGet, "/inv-challenges/lookup-user?identifier=other@example.com", me.ID, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("email lookup=%d %s", w.Code, w.Body.String())
	}
	w = invChDo(r, http.MethodGet, "/inv-challenges/lookup-user?identifier=8881112222", me.ID, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("phone lookup=%d %s", w.Code, w.Body.String())
	}
	w = invChDo(r, http.MethodGet, "/inv-challenges/lookup-user?identifier="+strconv.Itoa(int(other.ID)), me.ID, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("id lookup=%d %s", w.Code, w.Body.String())
	}
}

func TestInvChCopyRosterViaCreateMembers(t *testing.T) {
	db := invChTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	r := invChRouter(h)
	a := invChSeedUser(t, db, "lead", "lead@example.com", "")
	b := invChSeedUser(t, db, "mate", "mate@example.com", "")

	w := invChDo(r, http.MethodPost, "/inv-challenges", a.ID, map[string]any{
		"name": "First", "initial_networth": 1000, "duration_days": 2,
		"members": []map[string]any{{"identifier": "mate@example.com"}},
	})
	var first map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &first)

	w = invChDo(r, http.MethodPost, "/inv-challenges", a.ID, map[string]any{
		"name": "Second", "initial_networth": 2000, "duration_days": 3,
		"members": []map[string]any{{"user_id": b.ID}},
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("copy create=%d %s", w.Code, w.Body.String())
	}
	var second map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &second)
	if second["initial_networth"].(float64) != 2000 {
		t.Fatalf("new challenge should use new cash template, got %v", second["initial_networth"])
	}
	members := second["members"].([]any)
	if len(members) != 2 {
		t.Fatalf("copied roster len=%d", len(members))
	}
}

func TestInvChSellRejectsWhenProceedsAtOrBelowFee(t *testing.T) {
	db := invChTestDB(t)
	h := &Handler{DB: db, SkipBackgroundYahooEnrichment: true}
	r := invChRouter(h)
	u := invChSeedUser(t, db, "tiny", "tiny@example.com", "")
	invChSeedStock(t, db, "PENNY", 10)
	w := invChDo(r, http.MethodPost, "/inv-challenges", u.ID, map[string]any{
		"name": "Fee", "initial_networth": 500, "duration_days": 3,
	})
	var ch map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &ch)
	id := strconv.Itoa(int(ch["id"].(float64)))
	if w := invChDo(r, http.MethodPost, "/inv-challenges/"+id+"/buy", u.ID, map[string]any{
		"symbol": "PENNY", "quantity": 1,
	}); w.Code != http.StatusCreated {
		t.Fatalf("buy=%d %s", w.Code, w.Body.String())
	}
	w = invChDo(r, http.MethodPost, "/inv-challenges/"+id+"/sell", u.ID, map[string]any{
		"symbol": "PENNY", "quantity": 1,
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("sell proceeds 10 <= fee 20 should fail, got %d %s", w.Code, w.Body.String())
	}
}
