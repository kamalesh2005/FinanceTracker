package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
)

func putStockNotes(h *Handler, userID uint, path string, body any) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.PUT("/stocks/:id/notes", func(c *gin.Context) {
		c.Set(middleware.ContextUserIDKey, userID)
		h.SetStockNotes(c)
	})
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPut, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestSetStockNotes_SaveAndClear(t *testing.T) {
	db := clearReviewTestDB(t)
	h := &Handler{DB: db}
	buyDay := time.Date(2026, 1, 15, 0, 0, 0, 0, time.UTC)
	stock, pos := seedHolding(t, db, 1, "TCS", buyDay)

	w := putStockNotes(h, 1, fmt.Sprintf("/stocks/%d/notes", stock.ID), gin.H{
		"source": models.SourceManualAdd,
		"notes":  "  watch earnings  ",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("save status=%d body=%s", w.Code, w.Body.String())
	}
	got := reloadPos(t, db, pos.ID)
	if got.Notes != "watch earnings" {
		t.Fatalf("notes=%q want trimmed value", got.Notes)
	}

	w = putStockNotes(h, 1, fmt.Sprintf("/stocks/%d/notes", stock.ID), gin.H{
		"source": models.SourceManualAdd,
		"notes":  "   ",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("clear status=%d body=%s", w.Code, w.Body.String())
	}
	got = reloadPos(t, db, pos.ID)
	if got.Notes != "" {
		t.Fatalf("notes=%q want empty after clear", got.Notes)
	}
}

func TestSetStockNotes_RejectsOverLength(t *testing.T) {
	db := clearReviewTestDB(t)
	h := &Handler{DB: db}
	buyDay := time.Date(2026, 1, 15, 0, 0, 0, 0, time.UTC)
	stock, pos := seedHolding(t, db, 1, "INFY", buyDay)

	w := putStockNotes(h, 1, fmt.Sprintf("/stocks/%d/notes", stock.ID), gin.H{
		"source": models.SourceManualAdd,
		"notes":  strings.Repeat("a", 201),
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("status=%d want 400 body=%s", w.Code, w.Body.String())
	}
	got := reloadPos(t, db, pos.ID)
	if got.Notes != "" {
		t.Fatalf("notes=%q want unchanged empty", got.Notes)
	}
}
