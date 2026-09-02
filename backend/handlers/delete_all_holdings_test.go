package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
)

func TestDeleteAllUserHoldings(t *testing.T) {
	db := fifoTestDB(t)
	s1 := models.Stock{Symbol: "AAA"}
	s2 := models.Stock{Symbol: "BBB"}
	if err := db.Create(&s1).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&s2).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.UserStock{UserID: 1, StockID: s1.ID, Source: models.SourceHDFCSec, Quantity: 2, AvgBuyPrice: 10}).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.UserStock{UserID: 2, StockID: s2.ID, Source: models.SourceManualAdd, Quantity: 5, AvgBuyPrice: 20}).Error; err != nil {
		t.Fatal(err)
	}
	insertBuy(t, db, 1, s1.ID, models.SourceHDFCSec, 2, 10, fifoDate(2020, 1, 1))
	insertBuy(t, db, 2, s2.ID, models.SourceManualAdd, 5, 20, fifoDate(2020, 1, 1))

	gin.SetMode(gin.TestMode)
	h := &Handler{DB: db}
	r := gin.New()
	r.DELETE("/stocks/all-holdings", func(c *gin.Context) {
		c.Set(middleware.ContextUserIDKey, uint(1))
		h.DeleteAllUserHoldings(c)
	})
	req := httptest.NewRequest(http.MethodDelete, "/stocks/all-holdings", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}

	var u1pos int64
	db.Model(&models.UserStock{}).Where("user_id = ?", 1).Count(&u1pos)
	var u1tx int64
	db.Model(&models.UserStockTransaction{}).Where("user_id = ?", 1).Count(&u1tx)
	if u1pos != 0 || u1tx != 0 {
		t.Fatalf("user 1 leftover pos=%d tx=%d", u1pos, u1tx)
	}
	var u2pos int64
	db.Model(&models.UserStock{}).Where("user_id = ?", 2).Count(&u2pos)
	if u2pos != 1 {
		t.Fatalf("user 2 holdings=%d want 1", u2pos)
	}
	var stocks int64
	db.Model(&models.Stock{}).Count(&stocks)
	if stocks != 2 {
		t.Fatalf("catalog stocks=%d want 2", stocks)
	}
}

func TestDeleteAllUserMutualFunds(t *testing.T) {
	db := mfUploadTestDB(t)
	if err := db.AutoMigrate(&models.GlobalMutualFund{}); err != nil {
		t.Fatal(err)
	}
	g1 := models.GlobalMutualFund{ISIN: "INFAAA000001", Symbol: "1", SchemeName: "Fund A"}
	g2 := models.GlobalMutualFund{ISIN: "INFBBB000002", Symbol: "2", SchemeName: "Fund B"}
	if err := db.Create(&g1).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&g2).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.MutualFund{
		UserID: 1, ISIN: g1.ISIN, SchemeCode: g1.Symbol, SchemeName: g1.SchemeName,
		Source: models.SourceHDFCSec, Quantity: 2, NAV: 10,
	}).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.MutualFund{
		UserID: 2, ISIN: g2.ISIN, SchemeCode: g2.Symbol, SchemeName: g2.SchemeName,
		Source: models.SourceManualAdd, Quantity: 5, NAV: 20,
	}).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.UserMutualFundTransaction{
		UserID: 1, ISIN: g1.ISIN, Source: models.SourceHDFCSec,
		Type: models.TransactionTypeBuy, Quantity: 2, OriginalQuantity: 2, Price: 10,
	}).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.UserMutualFundTransaction{
		UserID: 2, ISIN: g2.ISIN, Source: models.SourceManualAdd,
		Type: models.TransactionTypeBuy, Quantity: 5, OriginalQuantity: 5, Price: 20,
	}).Error; err != nil {
		t.Fatal(err)
	}

	gin.SetMode(gin.TestMode)
	h := &Handler{DB: db}
	r := gin.New()
	r.DELETE("/mutualfunds/all-holdings", func(c *gin.Context) {
		c.Set(middleware.ContextUserIDKey, uint(1))
		h.DeleteAllUserMutualFunds(c)
	})
	req := httptest.NewRequest(http.MethodDelete, "/mutualfunds/all-holdings", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}

	var u1pos, u1tx int64
	db.Model(&models.MutualFund{}).Where("user_id = ?", 1).Count(&u1pos)
	db.Model(&models.UserMutualFundTransaction{}).Where("user_id = ?", 1).Count(&u1tx)
	if u1pos != 0 || u1tx != 0 {
		t.Fatalf("user 1 leftover pos=%d tx=%d", u1pos, u1tx)
	}
	var u2pos int64
	db.Model(&models.MutualFund{}).Where("user_id = ?", 2).Count(&u2pos)
	if u2pos != 1 {
		t.Fatalf("user 2 holdings=%d want 1", u2pos)
	}
	var catalog int64
	db.Model(&models.GlobalMutualFund{}).Count(&catalog)
	if catalog != 2 {
		t.Fatalf("catalog funds=%d want 2", catalog)
	}
}
