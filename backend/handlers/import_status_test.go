package handlers

import (
	"errors"
	"strings"
	"testing"
	"time"

	"financetracker/models"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func testImportStatusDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := gorm.Open(sqlite.Open("file:import_status_"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&models.StockDataImportStatus{}); err != nil {
		t.Fatal(err)
	}
	if err := EnsureImportStatuses(db); err != nil {
		t.Fatal(err)
	}
	return db
}

func TestRecordImportStatus_SuccessSetsLastSuccess(t *testing.T) {
	db := testImportStatusDB(t)

	if err := RecordImportStatus(db, models.ImportKindETF, models.ImportSourceCron, nil, &ImportSummary{Updated: 3}); err != nil {
		t.Fatal(err)
	}

	var row models.StockDataImportStatus
	if err := db.Where("kind = ?", models.ImportKindETF).First(&row).Error; err != nil {
		t.Fatal(err)
	}
	if row.LastStatus != models.ImportStatusSuccess {
		t.Fatalf("status=%q", row.LastStatus)
	}
	if row.LastSuccessAt == nil || row.LastAttemptAt == nil {
		t.Fatal("expected attempt and success timestamps")
	}
	if row.LastSource != models.ImportSourceCron {
		t.Fatalf("source=%q", row.LastSource)
	}
	if !strings.Contains(row.LastSummaryJSON, `"updated":3`) {
		t.Fatalf("summary=%q", row.LastSummaryJSON)
	}
}

func TestRecordImportStatus_FailurePreservesLastSuccess(t *testing.T) {
	db := testImportStatusDB(t)

	if err := RecordImportStatus(db, models.ImportKindCloses, models.ImportSourceManual, nil, nil); err != nil {
		t.Fatal(err)
	}
	var ok models.StockDataImportStatus
	if err := db.Where("kind = ?", models.ImportKindCloses).First(&ok).Error; err != nil {
		t.Fatal(err)
	}
	successAt := *ok.LastSuccessAt

	time.Sleep(5 * time.Millisecond)
	if err := RecordImportStatus(db, models.ImportKindCloses, models.ImportSourceCron, errors.New("download failed"), nil); err != nil {
		t.Fatal(err)
	}

	var row models.StockDataImportStatus
	if err := db.Where("kind = ?", models.ImportKindCloses).First(&row).Error; err != nil {
		t.Fatal(err)
	}
	if row.LastStatus != models.ImportStatusFailure {
		t.Fatalf("status=%q", row.LastStatus)
	}
	if row.LastError != "download failed" {
		t.Fatalf("error=%q", row.LastError)
	}
	if row.LastSuccessAt == nil || !row.LastSuccessAt.Equal(successAt) {
		t.Fatalf("last_success_at changed: was %v now %v", successAt, row.LastSuccessAt)
	}
	if row.LastAttemptAt == nil || !row.LastAttemptAt.After(successAt) {
		t.Fatal("expected last_attempt_at after prior success")
	}
}
