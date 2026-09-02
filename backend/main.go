package main

import (
	"financetracker/handlers"
	"financetracker/jobs"
	"financetracker/middleware"
	"financetracker/models"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func migrateLegacyTableNames(db *gorm.DB) error {
	renames := []struct{ old, new string }{
		{"stocks", "Global_Stocks"},
		{"symbol_mappings", "Global_SymbolMappings"},
		{"users", "Global_Users"},
		{"transactions", "User_Stocks"},
		{"User_Transactions", "User_Stocks"},
		{"mutual_funds", "User_MutualFunds"},
		{"password_reset_otps", "User_PasswordResetOTPs"},
		{"portfolios", "User_Portfolios"},
	}
	m := db.Migrator()
	for _, r := range renames {
		if m.HasTable(r.old) && !m.HasTable(r.new) {
			if err := m.RenameTable(r.old, r.new); err != nil {
				return err
			}
			log.Printf("Renamed table %s -> %s", r.old, r.new)
		}
	}
	return nil
}

func renameUserStockLastTradeColumns(db *gorm.DB) error {
	m := db.Migrator()
	if !m.HasTable(&models.UserStock{}) && !m.HasTable("User_Stocks") {
		return nil
	}
	// Skip while still lot-shaped (type column) — lot migration rebuilds the table.
	if m.HasColumn("User_Stocks", "type") || m.HasColumn("User_Stocks", "remaining_quantity") {
		return nil
	}
	renames := []struct{ old, new string }{
		{"buy_price", "last_buy_price"},
		{"buy_date", "last_buy_date"},
		{"sell_price", "last_sale_price"},
		{"sell_date", "last_sale_date"},
	}
	for _, r := range renames {
		if m.HasColumn("User_Stocks", r.old) && !m.HasColumn("User_Stocks", r.new) {
			if err := db.Exec(fmt.Sprintf(`ALTER TABLE "User_Stocks" RENAME COLUMN %s TO %s`, r.old, r.new)).Error; err != nil {
				return fmt.Errorf("rename %s -> %s: %w", r.old, r.new, err)
			}
			log.Printf("Renamed User_Stocks.%s -> %s", r.old, r.new)
		}
	}
	return nil
}

// migrateGlobalMFFYNAVColumns renames calendar YE columns to FY columns
// (nav_ye* / nav_ye_* → nav_fy_*), then zeros FY values once when a YE→FY
// rename happened so Mar-end backfill re-runs (Dec 31 data must not be reused).
func migrateGlobalMFFYNAVColumns(db *gorm.DB) error {
	const table = "Global_MutualFunds"
	m := db.Migrator()
	if !m.HasTable(table) {
		return nil
	}
	renamedFromYE := false
	// Normalize legacy GORM defaults first, then YE → FY.
	renames := []struct{ old, new string }{
		{"nav_ye2020", "nav_fy_2020"},
		{"nav_ye2021", "nav_fy_2021"},
		{"nav_ye2022", "nav_fy_2022"},
		{"nav_ye2023", "nav_fy_2023"},
		{"nav_ye2024", "nav_fy_2024"},
		{"nav_ye2025", "nav_fy_2025"},
		{"nav_ye_2020", "nav_fy_2020"},
		{"nav_ye_2021", "nav_fy_2021"},
		{"nav_ye_2022", "nav_fy_2022"},
		{"nav_ye_2023", "nav_fy_2023"},
		{"nav_ye_2024", "nav_fy_2024"},
		{"nav_ye_2025", "nav_fy_2025"},
	}
	for _, r := range renames {
		hasOld := m.HasColumn(table, r.old)
		hasNew := m.HasColumn(table, r.new)
		if hasOld && !hasNew {
			if err := db.Exec(fmt.Sprintf(`ALTER TABLE "%s" RENAME COLUMN %s TO %s`, table, r.old, r.new)).Error; err != nil {
				return fmt.Errorf("rename %s.%s -> %s: %w", table, r.old, r.new, err)
			}
			log.Printf("Renamed %s.%s -> %s", table, r.old, r.new)
			renamedFromYE = true
		} else if hasOld && hasNew {
			if err := db.Exec(fmt.Sprintf(`ALTER TABLE "%s" DROP COLUMN %s`, table, r.old)).Error; err != nil {
				return fmt.Errorf("drop %s.%s: %w", table, r.old, err)
			}
			log.Printf("Dropped duplicate %s.%s (kept %s)", table, r.old, r.new)
			renamedFromYE = true
		}
	}
	if !renamedFromYE {
		return nil
	}
	fyCols := []string{"nav_fy_2020", "nav_fy_2021", "nav_fy_2022", "nav_fy_2023", "nav_fy_2024", "nav_fy_2025"}
	for _, c := range fyCols {
		if !m.HasColumn(table, c) {
			continue
		}
		if err := db.Exec(fmt.Sprintf(`UPDATE "Global_MutualFunds" SET %s = 0`, c)).Error; err != nil {
			return fmt.Errorf("zero %s.%s: %w", table, c, err)
		}
	}
	log.Printf("migrateGlobalMFFYNAVColumns: zeroed FY NAV columns for re-backfill")
	return nil
}

// migrateGlobalIndexFYColumns renames calendar ye_* to fy_* on Global_Indices.
func migrateGlobalIndexFYColumns(db *gorm.DB) error {
	const table = "Global_Indices"
	m := db.Migrator()
	if !m.HasTable(table) {
		return nil
	}
	renames := []struct{ old, new string }{
		{"ye_2020", "fy_2020"},
		{"ye_2021", "fy_2021"},
		{"ye_2022", "fy_2022"},
		{"ye_2023", "fy_2023"},
		{"ye_2024", "fy_2024"},
		{"ye_2025", "fy_2025"},
	}
	for _, r := range renames {
		hasOld := m.HasColumn(table, r.old)
		hasNew := m.HasColumn(table, r.new)
		if hasOld && !hasNew {
			if err := db.Exec(fmt.Sprintf(`ALTER TABLE "%s" RENAME COLUMN %s TO %s`, table, r.old, r.new)).Error; err != nil {
				return fmt.Errorf("rename %s.%s -> %s: %w", table, r.old, r.new, err)
			}
			log.Printf("Renamed %s.%s -> %s", table, r.old, r.new)
		} else if hasOld && hasNew {
			if err := db.Exec(fmt.Sprintf(`ALTER TABLE "%s" DROP COLUMN %s`, table, r.old)).Error; err != nil {
				return fmt.Errorf("drop %s.%s: %w", table, r.old, err)
			}
			log.Printf("Dropped duplicate %s.%s (kept %s)", table, r.old, r.new)
		}
	}
	return nil
}

// migrateGoogleAuthPasswordHash drops NOT NULL on password_hash so Google-only
// users can be stored without a bcrypt hash. GORM AutoMigrate will not do this.
func migrateGoogleAuthPasswordHash(db *gorm.DB) error {
	m := db.Migrator()
	if !m.HasTable("Global_Users") {
		return nil
	}
	if !m.HasColumn("Global_Users", "password_hash") {
		return nil
	}
	if err := db.Exec(`ALTER TABLE "Global_Users" ALTER COLUMN password_hash DROP NOT NULL`).Error; err != nil {
		return fmt.Errorf("drop Global_Users.password_hash NOT NULL: %w", err)
	}
	return nil
}

// legacyLotRow mirrors the old lot-shaped User_Stocks / transactions table.
type legacyLotRow struct {
	ID                uint
	UserID            uint
	StockID           uint
	Type              string
	Quantity          float64
	Price             float64
	RemainingQuantity float64
	TransactionDate   time.Time
	Source            string
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

func migrateLotShapedUserStocks(db *gorm.DB) error {
	m := db.Migrator()
	if !m.HasTable("User_Stocks") {
		return nil
	}
	// Already position-shaped (no type column).
	if !m.HasColumn("User_Stocks", "type") && !m.HasColumn("User_Stocks", "remaining_quantity") {
		return nil
	}

	log.Println("Migrating lot-shaped User_Stocks → User_Stock_Transactions + position User_Stocks")

	if err := db.AutoMigrate(&models.UserStockTransaction{}); err != nil {
		return err
	}

	var ledgerCount int64
	if err := db.Model(&models.UserStockTransaction{}).Count(&ledgerCount).Error; err != nil {
		return err
	}

	var lots []legacyLotRow
	if err := db.Table(`"User_Stocks"`).Find(&lots).Error; err != nil {
		return err
	}

	if ledgerCount == 0 && len(lots) > 0 {
		for _, lot := range lots {
			source := strings.TrimSpace(lot.Source)
			if source == "" {
				source = models.SourceManualAdd
			}
			txType := models.TransactionType(lot.Type)
			if txType != models.TransactionTypeBuy && txType != models.TransactionTypeSell {
				txType = models.TransactionTypeBuy
			}
			row := models.UserStockTransaction{
				UserID:           lot.UserID,
				StockID:          lot.StockID,
				Source:           source,
				Type:             txType,
				Quantity:         lot.Quantity,
				OriginalQuantity: lot.Quantity,
				Price:            lot.Price,
				CreatedAt:        lot.CreatedAt,
			}
			if !lot.TransactionDate.IsZero() {
				d := lot.TransactionDate
				row.TransactionDate = &d
			}
			if txType == models.TransactionTypeBuy && lot.RemainingQuantity >= 0 && lot.RemainingQuantity <= lot.Quantity {
				// Prefer remaining as open qty when migrating from lot-shaped table.
				row.OriginalQuantity = lot.Quantity
				row.Quantity = lot.RemainingQuantity
			}
			if err := db.Create(&row).Error; err != nil {
				return err
			}
		}
		log.Printf("Copied %d legacy lots into User_Stock_Transactions", len(lots))
	}

	type posKey struct {
		UserID  uint
		StockID uint
		Source  string
	}
	type posAgg struct {
		Quantity      float64
		Invested      float64
		LastBuyPrice  float64
		LastBuyDate   *time.Time
		LastSalePrice float64
		LastSaleDate  *time.Time
	}
	aggs := map[posKey]*posAgg{}

	for _, lot := range lots {
		source := strings.TrimSpace(lot.Source)
		if source == "" {
			source = models.SourceManualAdd
		}
		key := posKey{UserID: lot.UserID, StockID: lot.StockID, Source: source}
		agg, ok := aggs[key]
		if !ok {
			agg = &posAgg{}
			aggs[key] = agg
		}
		d := lot.TransactionDate
		if lot.Type == string(models.TransactionTypeSell) {
			agg.LastSalePrice = lot.Price
			agg.LastSaleDate = &d
			continue
		}
		// Buys contribute open remaining quantity to the position.
		if lot.RemainingQuantity > 0 {
			agg.Quantity += lot.RemainingQuantity
			agg.Invested += lot.Price * lot.RemainingQuantity
		}
		if agg.LastBuyDate == nil || lot.TransactionDate.After(*agg.LastBuyDate) {
			agg.LastBuyPrice = lot.Price
			agg.LastBuyDate = &d
		}
	}

	legacyName := "User_Stocks_LegacyLots"
	if m.HasTable(legacyName) {
		_ = m.DropTable(legacyName)
	}
	if err := m.RenameTable("User_Stocks", legacyName); err != nil {
		return err
	}
	log.Printf("Renamed User_Stocks -> %s", legacyName)

	if err := db.AutoMigrate(&models.UserStock{}); err != nil {
		return err
	}

	for key, agg := range aggs {
		avg := 0.0
		if agg.Quantity > 0 {
			avg = agg.Invested / agg.Quantity
		}
		pos := models.UserStock{
			UserID:        key.UserID,
			StockID:       key.StockID,
			Source:        key.Source,
			Quantity:      agg.Quantity,
			AvgBuyPrice:   avg,
			LastBuyPrice:  agg.LastBuyPrice,
			LastBuyDate:   agg.LastBuyDate,
			LastSalePrice: agg.LastSalePrice,
			LastSaleDate:  agg.LastSaleDate,
		}
		if err := db.Create(&pos).Error; err != nil {
			return err
		}
	}
	log.Printf("Rebuilt %d User_Stocks positions", len(aggs))

	if err := m.DropTable(legacyName); err != nil {
		log.Printf("Warning: could not drop %s: %v", legacyName, err)
	}
	return nil
}

func migrateStocksToTransactions(db *gorm.DB, adminUserID uint) {
	var stocks []models.Stock
	db.Where("quantity > 0").Find(&stocks)

	for _, stock := range stocks {
		var ledgerCount int64
		db.Model(&models.UserStockTransaction{}).Where("stock_id = ?", stock.ID).Count(&ledgerCount)
		var posCount int64
		db.Model(&models.UserStock{}).Where("stock_id = ?", stock.ID).Count(&posCount)

		if ledgerCount == 0 && posCount == 0 && stock.LegacyQuantity > 0 {
			_, _, err := handlers.ApplyManualStockTransaction(
				db, adminUserID, stock.ID, models.TransactionTypeBuy,
				stock.LegacyQuantity, stock.LegacyBuyPrice, stock.LegacyPurchaseDate, models.SourceManualAdd,
			)
			if err != nil {
				log.Printf("Failed to migrate stock %s: %v", stock.Symbol, err)
			} else {
				log.Printf("Migrated stock %s: %.2f shares @ ₹%.2f", stock.Symbol, stock.LegacyQuantity, stock.LegacyBuyPrice)
			}
		}
	}
}

// migrateUserStockTransactionDateNullable drops NOT NULL on transaction_date.
// GORM AutoMigrate will not do this.
func migrateUserStockTransactionDateNullable(db *gorm.DB) error {
	m := db.Migrator()
	if !m.HasTable("User_Stock_Transactions") {
		return nil
	}
	if !m.HasColumn("User_Stock_Transactions", "transaction_date") {
		return nil
	}
	if err := db.Exec(`ALTER TABLE "User_Stock_Transactions" ALTER COLUMN transaction_date DROP NOT NULL`).Error; err != nil {
		return fmt.Errorf("drop User_Stock_Transactions.transaction_date NOT NULL: %w", err)
	}
	return nil
}

// migrateUserMutualFundTransactionDateNullable drops NOT NULL on transaction_date.
func migrateUserMutualFundTransactionDateNullable(db *gorm.DB) error {
	m := db.Migrator()
	if !m.HasTable("User_MutualFund_Transactions") {
		return nil
	}
	if !m.HasColumn("User_MutualFund_Transactions", "transaction_date") {
		return nil
	}
	if err := db.Exec(`ALTER TABLE "User_MutualFund_Transactions" ALTER COLUMN transaction_date DROP NOT NULL`).Error; err != nil {
		return fmt.Errorf("drop User_MutualFund_Transactions.transaction_date NOT NULL: %w", err)
	}
	return nil
}

// migrateFFAssetPresetUniqueDrop allows multiple assets with the same preset_key
// (e.g. several savings accounts or properties).
func migrateFFAssetPresetUniqueDrop(db *gorm.DB) error {
	m := db.Migrator()
	if !m.HasTable(&models.FFAsset{}) {
		return nil
	}
	// GORM may have created either name depending on dialect/version.
	for _, name := range []string{
		"idx_ff_asset_user_preset",
		"idx_user_ff_assets_user_id_preset_key",
	} {
		if m.HasIndex(&models.FFAsset{}, name) {
			if err := m.DropIndex(&models.FFAsset{}, name); err != nil {
				log.Printf("Warning: could not drop index %s: %v", name, err)
			}
		}
	}
	// Ensure a non-unique index remains for lookups.
	if !m.HasIndex(&models.FFAsset{}, "idx_ff_asset_preset_key") {
		if err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_ff_asset_preset_key ON "User_FF_Assets" (user_id, preset_key)`).Error; err != nil {
			log.Printf("Warning: could not create idx_ff_asset_preset_key: %v", err)
		}
	}
	return nil
}

// migrateMutualFundsToTransactions seeds buy lots from existing User_MutualFunds
// holdings that have no ledger rows yet (one-time backfill after introducing the table).
func migrateMutualFundsToTransactions(db *gorm.DB) {
	m := db.Migrator()
	if !m.HasTable("User_MutualFunds") || !m.HasTable("User_MutualFund_Transactions") {
		return
	}

	var holdings []models.MutualFund
	if err := db.Where("quantity > 0").Find(&holdings).Error; err != nil {
		log.Printf("migrateMutualFundsToTransactions: load holdings: %v", err)
		return
	}
	created := 0
	for _, mf := range holdings {
		source := strings.TrimSpace(mf.Source)
		if source == "" {
			source = models.SourceManualAdd
		}
		isin := strings.ToUpper(strings.TrimSpace(mf.ISIN))
		var existing int64
		q := db.Model(&models.UserMutualFundTransaction{}).
			Where("user_id = ? AND source = ?", mf.UserID, source)
		if isin != "" {
			q = q.Where("UPPER(isin) = ?", isin)
		} else {
			q = q.Where(
				"(isin IS NULL OR TRIM(isin) = '') AND LOWER(TRIM(source_scheme_name)) = ?",
				strings.ToLower(strings.TrimSpace(mf.SourceSchemeName)),
			)
		}
		if err := q.Count(&existing).Error; err != nil {
			log.Printf("migrateMutualFundsToTransactions: count: %v", err)
			continue
		}
		if existing > 0 {
			continue
		}
		var txDate *time.Time
		if !mf.PurchaseDate.IsZero() {
			d := mf.PurchaseDate
			txDate = &d
		}
		row := models.UserMutualFundTransaction{
			UserID:           mf.UserID,
			ISIN:             mf.ISIN,
			SourceSchemeName: mf.SourceSchemeName,
			Source:           source,
			Type:             models.TransactionTypeBuy,
			Quantity:         mf.Quantity,
			OriginalQuantity: mf.Quantity,
			Price:            mf.NAV,
			TransactionDate:  txDate,
			Origin:           models.TxOriginSnapshot,
		}
		if err := db.Create(&row).Error; err != nil {
			log.Printf("migrateMutualFundsToTransactions: create: %v", err)
			continue
		}
		created++
	}
	if created > 0 {
		log.Printf("migrateMutualFundsToTransactions: seeded %d buy lots from holdings", created)
	}
}

func databaseDSN() string {
	if dsn := strings.TrimSpace(os.Getenv("DATABASE_URL")); dsn != "" {
		return dsn
	}
	return "host=localhost user=finance password=finance dbname=financetracker port=5432 sslmode=disable"
}

func listenPort() string {
	if port := strings.TrimSpace(os.Getenv("PORT")); port != "" {
		return port
	}
	return "8080"
}

// loadDotEnv loads KEY=VALUE pairs from path into the process env when the key
// is not already set. Missing file is ignored.
func loadDotEnv(path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq := strings.IndexByte(line, '=')
		if eq <= 0 {
			continue
		}
		key := strings.TrimSpace(line[:eq])
		val := strings.TrimSpace(line[eq+1:])
		if len(val) >= 2 {
			if (val[0] == '"' && val[len(val)-1] == '"') || (val[0] == '\'' && val[len(val)-1] == '\'') {
				val = val[1 : len(val)-1]
			}
		}
		if key == "" {
			continue
		}
		if _, exists := os.LookupEnv(key); exists {
			continue
		}
		_ = os.Setenv(key, val)
	}
}

func main() {
	loadDotEnv(".env")
	dsn := databaseDSN()
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}

	if err := migrateLegacyTableNames(db); err != nil {
		log.Fatal("Failed to rename legacy tables:", err)
	}

	// Ledger table first so lot migration can copy into it.
	if err := db.AutoMigrate(&models.UserStockTransaction{}); err != nil {
		log.Fatal("Failed to migrate User_Stock_Transactions:", err)
	}

	if err := migrateLotShapedUserStocks(db); err != nil {
		log.Fatal("Failed to migrate lot-shaped User_Stocks:", err)
	}

	if err := renameUserStockLastTradeColumns(db); err != nil {
		log.Fatal("Failed to rename User_Stocks last-trade columns:", err)
	}

	if err := migrateGlobalMFFYNAVColumns(db); err != nil {
		log.Fatal("Failed to migrate Global_MutualFunds FY NAV columns:", err)
	}

	if err := migrateGlobalIndexFYColumns(db); err != nil {
		log.Fatal("Failed to migrate Global_Indices FY columns:", err)
	}

	if err := db.AutoMigrate(
		&models.User{},
		&models.PasswordResetOTP{},
		&models.RefreshToken{},
		&models.Stock{},
		&models.GlobalMutualFund{},
		&models.GlobalIndex{},
		&models.MutualFund{},
		&models.UserMutualFundTransaction{},
		&models.Portfolio{},
		&models.UserStock{},
		&models.UserWatchlist{},
		&models.UserScreenerStockLabel{},
		&models.UserStockTransaction{},
		&models.UserConfig{},
		&models.AppConfig{},
		&models.SymbolMapping{},
		&models.MFSchemeMapping{},
		&models.StockDailyClose{},
		&models.StockDailyCloseSync{},
		&models.StockDataImportStatus{},
		&models.InvChChallenge{},
		&models.InvChMember{},
		&models.InvChHolding{},
		&models.InvChTransaction{},
		&models.FFAsset{},
		&models.FFJobIncome{},
		&models.FFExpense{},
		&models.FFOneTimeExpense{},
		&models.Feedback{},
	); err != nil {
		log.Fatal("Failed to migrate database:", err)
	}

	if err := migrateFFAssetPresetUniqueDrop(db); err != nil {
		log.Fatal("Failed to drop FF asset preset unique index:", err)
	}

	if err := migrateGoogleAuthPasswordHash(db); err != nil {
		log.Fatal("Failed to migrate Global_Users password_hash nullability:", err)
	}

	if err := migrateUserStockTransactionDateNullable(db); err != nil {
		log.Fatal("Failed to make User_Stock_Transactions.transaction_date nullable:", err)
	}

	if err := migrateUserMutualFundTransactionDateNullable(db); err != nil {
		log.Fatal("Failed to make User_MutualFund_Transactions.transaction_date nullable:", err)
	}

	migrateMutualFundsToTransactions(db)

	if err := handlers.EnsureAppConfig(db); err != nil {
		log.Fatal("Failed to seed app config:", err)
	}

	if err := handlers.MigrateRecommendationRulesHoldThresholds(db); err != nil {
		log.Fatal("Failed to migrate Hold/threshold recommendation rules:", err)
	}

	admin, err := handlers.SeedAdminUser(db)
	if err != nil {
		log.Fatal("Failed to seed admin user:", err)
	}
	log.Printf("Admin user ready (id=%d username=admin)", admin.ID)

	if err := handlers.BackfillUserScopedData(db, admin.ID); err != nil {
		log.Fatal("Failed to backfill user-scoped data:", err)
	}

	migrateStocksToTransactions(db, admin.ID)

	if err := handlers.BackfillOriginalQuantityAndFIFO(db); err != nil {
		log.Fatal("Failed to backfill original_quantity / FIFO lots:", err)
	}

	if err := handlers.SeedAndLoadSymbolMappings(db); err != nil {
		log.Fatal("Failed to seed symbol mappings:", err)
	}

	if err := handlers.BackfillPullDataFromHoldings(db); err != nil {
		log.Fatal("Failed to backfill pull_data:", err)
	}

	if err := handlers.SeedNifty50Index(db); err != nil {
		log.Fatal("Failed to seed NIFTY50 index:", err)
	}

	if err := handlers.RoundExistingStockFYLTPs(db); err != nil {
		log.Fatal("Failed to round stock FY LTPs:", err)
	}

	if err := handlers.LoadNSEEquityISINIndex(); err != nil {
		csvPath := os.Getenv("NSE_EQUITY_CSV_PATH")
		if csvPath == "" {
			csvPath = "data/EQUITY_L.csv"
		}
		if fileErr := handlers.LoadNSEEquityISINIndexFromFile(csvPath); fileErr != nil {
			log.Printf("Warning: NSE ISIN index not loaded (Yahoo ISIN fallback still available): download=%v file=%v", err, fileErr)
		}
	}

	if err := handlers.EnsureImportStatuses(db); err != nil {
		log.Fatal("Failed to seed stock data import status:", err)
	}

	r := gin.Default()
	_ = r.SetTrustedProxies([]string{"127.0.0.1", "::1"})

	r.Use(middleware.NoCache())
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept", "Authorization"},
		ExposeHeaders:    []string{"Content-Length", "Retry-After"},
		AllowCredentials: true,
	}))

	h := handlers.NewHandler(db)
	jobs.StartIntradayPriceCron(h)
	jobs.StartDailyYahooRefreshCron(h)
	jobs.StartDailyNonHeldEQYahooCron(h)
	jobs.StartDailyMFNAVCron(h)
	jobs.StartMFYearEndNAVBackfill(h)
	jobs.StartStockFYBackfill(h)
	handlers.RegisterStockFYBackfillTrigger(h.RequestStockFYBackfill)
	jobs.StartDailyNSEPRCron(h)
	jobs.StartDailyMFVarCron(h)
	jobs.StartDailyBSEBhavCron(h)
	jobs.StartDailyStockReviewEmailCron(h)
	go func() {
		if err := h.RefreshNifty50CurrentValue(); err != nil {
			log.Printf("Nifty50: startup refresh FAIL: %v", err)
		}
	}()

	api := r.Group("/api/v1")
	{
		authPublic := api.Group("/auth")
		authPublic.Use(middleware.OptionalAuth(db))
		{
			authPublic.GET("/captcha-config", h.CaptchaConfig)
			authPublic.POST("/register", middleware.RateLimit(5, time.Hour), h.Register)
			authPublic.GET("/check-username", middleware.RateLimit(30, time.Minute), h.CheckUsername)
			authPublic.GET("/check-email", middleware.RateLimit(30, time.Minute), h.CheckEmail)
			authPublic.GET("/check-mobile", middleware.RateLimit(30, time.Minute), h.CheckMobile)
			authPublic.POST("/login", middleware.RateLimit(20, 15*time.Minute), h.Login)
			authPublic.POST("/refresh", middleware.RateLimit(60, 15*time.Minute), h.Refresh)
			authPublic.POST("/google", middleware.RateLimit(20, 15*time.Minute), h.GoogleLogin)
			authPublic.POST("/forgot-password", h.ForgotPassword)
			authPublic.POST("/reset-password", h.ResetPassword)
		}

		authed := api.Group("")
		authed.Use(middleware.AuthRequired(db))
		{
			authed.GET("/auth/me", h.Me)
			authed.PUT("/auth/profile", h.UpdateProfile)
			authed.PUT("/auth/default-portal", h.UpdateDefaultPortal)
			authed.POST("/auth/change-password", h.ChangePassword)

			authed.GET("/config/stock-columns", h.GetStockColumnConfig)
			authed.PUT("/config/stock-columns", h.PutStockColumnConfig)
			authed.GET("/config/mf-columns", h.GetMutualFundColumnConfig)
			authed.PUT("/config/mf-columns", h.PutMutualFundColumnConfig)
			authed.GET("/config/screener-columns", h.GetScreenerColumnConfig)
			authed.PUT("/config/screener-columns", h.PutScreenerColumnConfig)
			authed.GET("/config/preferences", h.GetPreferences)
			authed.PUT("/config/preferences", h.PutPreferences)

			authed.GET("/indices", h.GetIndices)
			authed.GET("/stocks", h.GetStocks)
			authed.POST("/stocks", h.CreateStock)
			authed.POST("/stocks/bulk", h.CreateStocksBulk)
			authed.GET("/stocks/trends", h.GetStockTrends)
			authed.GET("/stocks/history", h.GetStockHistory)
			authed.GET("/stocks/lookup", h.LookupStockBySymbol)
			authed.GET("/stocks/search", h.SearchStocks)
			authed.GET("/stocks/screener/options", h.GetScreenerOptions)
			authed.GET("/stocks/screener", h.SearchScreener)
			authed.POST("/stocks/screener/labels", h.AddScreenerLabel)
			authed.DELETE("/stocks/screener/labels/:stock_id/:label", h.RemoveScreenerLabel)
			authed.POST("/stocks/refresh-prices", h.RefreshStockPrices)
			authed.POST("/stocks/clear-review-values", h.ClearAllStockReviewValues)
			authed.DELETE("/stocks/all-holdings", h.DeleteAllUserHoldings)
			authed.GET("/watchlist", h.GetWatchlist)
			authed.POST("/watchlist", h.AddToWatchlist)
			authed.DELETE("/watchlist/:stock_id", h.RemoveFromWatchlist)
			authed.GET("/stocks/:id", h.GetStock)
			authed.PUT("/stocks/:id", h.UpdateStock)
			authed.PUT("/stocks/:id/holdings", h.UpdateStockHoldings)
			authed.DELETE("/stocks/:id/holdings", h.DeleteStockHoldings)
			authed.POST("/stocks/:id/hold", h.MarkStockHold)
			authed.PUT("/stocks/:id/thresholds", h.SetStockThresholds)
			authed.PUT("/stocks/:id/notes", h.SetStockNotes)
			authed.POST("/stocks/:id/clear-review-values", h.ClearStockReviewValues)

			authed.POST("/transactions/buy", h.CreateBuyTransaction)
			authed.POST("/transactions/buy/replace-by-source", h.ReplaceSourceBuyTransactions)
			authed.POST("/transactions/rebuild-from-ledger", h.RebuildSourceLedger)
			authed.POST("/transactions/merge-from-ledger", h.MergeSourceLedger)
			authed.POST("/transactions/sell", h.CreateSellTransaction)
			authed.GET("/transactions", h.GetTransactions)

			authed.GET("/mutualfunds", h.GetMutualFunds)
			authed.POST("/mutualfunds", h.CreateMutualFund)
			authed.POST("/mutualfunds/bulk", h.ReplaceSourceMutualFunds)
			authed.DELETE("/mutualfunds/all-holdings", h.DeleteAllUserMutualFunds)
			authed.GET("/mutualfunds/search", h.SearchMutualFunds)
			authed.GET("/mutualfunds/lookup", h.LookupMutualFundByISIN)
			authed.GET("/mutualfunds/:id", h.GetMutualFund)
			authed.PUT("/mutualfunds/:id", h.UpdateMutualFund)
			authed.DELETE("/mutualfunds/:id", h.DeleteMutualFund)

			authed.GET("/portfolio", h.GetPortfolio)
			authed.GET("/portfolio/summary", h.GetPortfolioSummary)

			authed.POST("/feedback", h.SubmitFeedback)
			authed.GET("/feedback", h.ListMyFeedback)

			handlers.RegisterInvChallengeRoutes(authed, h)
			handlers.RegisterFinancialFreedomRoutes(authed, h)

			admin := authed.Group("")
			admin.Use(middleware.RequireAdmin())
			{
				admin.DELETE("/stocks/:id", h.DeleteStock)
				admin.PUT("/stocks/:id/admin", h.UpdateStockAdminFields)
				admin.GET("/admin/stocks", h.GetAllStocksAdmin)
				admin.GET("/admin/stocks/import-status", h.GetStockImportStatusAdmin)
				admin.POST("/admin/stocks/pull-nse-pr", h.PullNSEPRDailyAdmin)
				admin.POST("/admin/stocks/pull-bse-bhav", h.PullBSEBhavDailyAdmin)
				admin.POST("/admin/stocks/import-nse", h.ImportNSECatalogAdmin)
				admin.POST("/admin/stocks/import-closes", h.ImportClosingPricesAdmin)
				admin.POST("/admin/stocks/import-etf", h.ImportETFCSVAdmin)
				admin.POST("/admin/stocks/import-bse-bhav", h.ImportBSEBhavAdmin)
				admin.GET("/admin/stocks/review-email-status", h.GetStockReviewEmailStatus)
				admin.POST("/admin/stocks/send-review-emails", h.TriggerStockReviewEmails)
				admin.GET("/admin/mutualfunds", h.GetAllMutualFundsAdmin)
				admin.GET("/admin/mutualfunds/import-status", h.GetMFImportStatusAdmin)
				admin.POST("/admin/mutualfunds/pull-mf-var", h.PullMFVarDailyAdmin)
				admin.POST("/admin/mutualfunds/import", h.ImportMutualFundsAdmin)

				admin.GET("/symbol-mappings", h.GetSymbolMappings)
				admin.POST("/symbol-mappings", h.CreateSymbolMapping)
				admin.PUT("/symbol-mappings/:id", h.UpdateSymbolMapping)
				admin.DELETE("/symbol-mappings/:id", h.DeleteSymbolMapping)
				admin.GET("/admin/unmapped-stocks", h.GetUnmappedStocks)

				admin.GET("/mf-scheme-mappings", h.GetMFSchemeMappings)
				admin.POST("/mf-scheme-mappings", h.CreateMFSchemeMapping)
				admin.PUT("/mf-scheme-mappings/:id", h.UpdateMFSchemeMapping)
				admin.DELETE("/mf-scheme-mappings/:id", h.DeleteMFSchemeMapping)
				admin.GET("/admin/unmapped-mf-schemes", h.GetUnmappedMFSchemes)

				admin.GET("/admin/users", h.ListUsers)
				admin.POST("/admin/users", h.CreateUser)
				admin.PUT("/admin/users/:id/enabled", h.SetUserEnabled)
				admin.PUT("/admin/users/:id/stock-review-email", h.SetUserStockReviewEmailAdmin)

				admin.GET("/admin/feedback", h.ListFeedbackAdmin)
				admin.PUT("/admin/feedback/:id/respond", h.RespondToFeedback)
				admin.PUT("/admin/feedback/:id/close", h.CloseFeedback)

				admin.GET("/admin/config", h.GetAdminConfig)
				admin.PUT("/admin/config", h.PutAdminConfig)
			}
		}
	}

	port := listenPort()
	log.Printf("Server starting on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}
