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
				TransactionDate:  lot.TransactionDate,
				CreatedAt:        lot.CreatedAt,
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

// backfillOriginalQuantityAndFIFO sets original_quantity from quantity where missing,
// then resets buy lots to original_quantity and replays sells FIFO so Quantity is remaining.
func backfillOriginalQuantityAndFIFO(db *gorm.DB) error {
	if err := db.Exec(`
		UPDATE "User_Stock_Transactions"
		SET original_quantity = quantity
		WHERE original_quantity = 0 AND quantity > 0
	`).Error; err != nil {
		return fmt.Errorf("backfill original_quantity: %w", err)
	}

	type groupKey struct {
		UserID  uint
		StockID uint
		Source  string
	}
	var keys []groupKey
	if err := db.Model(&models.UserStockTransaction{}).
		Select("user_id, stock_id, source").
		Group("user_id, stock_id, source").
		Scan(&keys).Error; err != nil {
		return err
	}

	for _, key := range keys {
		var txs []models.UserStockTransaction
		if err := db.Where("user_id = ? AND stock_id = ? AND source = ?", key.UserID, key.StockID, key.Source).
			Order("transaction_date ASC, id ASC").
			Find(&txs).Error; err != nil {
			return err
		}

		hasSell := false
		for _, tx := range txs {
			if tx.Type == models.TransactionTypeSell {
				hasSell = true
				break
			}
		}
		if !hasSell {
			for i := range txs {
				if txs[i].Type != models.TransactionTypeBuy {
					continue
				}
				orig := txs[i].OriginalQuantity
				if orig <= 0 {
					orig = txs[i].Quantity
				}
				if txs[i].Quantity != orig || txs[i].OriginalQuantity != orig {
					txs[i].OriginalQuantity = orig
					txs[i].Quantity = orig
					if err := db.Save(&txs[i]).Error; err != nil {
						return err
					}
				}
			}
			continue
		}

		buys := make([]*models.UserStockTransaction, 0)
		for i := range txs {
			if txs[i].Type != models.TransactionTypeBuy {
				continue
			}
			orig := txs[i].OriginalQuantity
			if orig <= 0 {
				orig = txs[i].Quantity
			}
			txs[i].OriginalQuantity = orig
			txs[i].Quantity = orig
			buys = append(buys, &txs[i])
		}

		for i := range txs {
			tx := &txs[i]
			if tx.Type != models.TransactionTypeSell {
				continue
			}
			if tx.OriginalQuantity <= 0 {
				tx.OriginalQuantity = tx.Quantity
				if err := db.Save(tx).Error; err != nil {
					return err
				}
			}
			remaining := tx.Quantity
			for _, buy := range buys {
				if remaining < 1e-9 {
					break
				}
				if buy.Quantity < 1e-9 {
					continue
				}
				take := buy.Quantity
				if take > remaining {
					take = remaining
				}
				buy.Quantity -= take
				if buy.Quantity < 1e-9 {
					buy.Quantity = 0
				}
				remaining -= take
			}
		}

		for _, buy := range buys {
			if err := db.Save(buy).Error; err != nil {
				return err
			}
		}

		if _, err := handlers.RecomputeUserStock(db, key.UserID, key.StockID, key.Source); err != nil {
			log.Printf("Warning: recompute after FIFO backfill user=%d stock=%d source=%s: %v",
				key.UserID, key.StockID, key.Source, err)
		}
	}

	log.Println("Backfilled original_quantity and FIFO remaining quantities on User_Stock_Transactions")
	return nil
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

	if err := db.AutoMigrate(
		&models.User{},
		&models.PasswordResetOTP{},
		&models.Stock{},
		&models.MutualFund{},
		&models.Portfolio{},
		&models.UserStock{},
		&models.UserStockTransaction{},
		&models.UserConfig{},
		&models.AppConfig{},
		&models.SymbolMapping{},
	); err != nil {
		log.Fatal("Failed to migrate database:", err)
	}

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

	if err := backfillOriginalQuantityAndFIFO(db); err != nil {
		log.Fatal("Failed to backfill original_quantity / FIFO lots:", err)
	}

	if err := handlers.SeedAndLoadSymbolMappings(db); err != nil {
		log.Fatal("Failed to seed symbol mappings:", err)
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

	r := gin.Default()

	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
	}))

	h := handlers.NewHandler(db)
	jobs.StartIntradayPriceCron(h)
	jobs.StartDailyYahooRefreshCron(h)

	api := r.Group("/api/v1")
	{
		authPublic := api.Group("/auth")
		{
			authPublic.POST("/register", h.Register)
			authPublic.POST("/login", h.Login)
			authPublic.POST("/forgot-password", h.ForgotPassword)
			authPublic.POST("/reset-password", h.ResetPassword)
		}

		authed := api.Group("")
		authed.Use(middleware.AuthRequired(db))
		{
			authed.GET("/auth/me", h.Me)

			authed.GET("/config/stock-columns", h.GetStockColumnConfig)
			authed.PUT("/config/stock-columns", h.PutStockColumnConfig)
			authed.GET("/config/preferences", h.GetPreferences)
			authed.PUT("/config/preferences", h.PutPreferences)

			authed.GET("/stocks", h.GetStocks)
			authed.POST("/stocks", h.CreateStock)
			authed.POST("/stocks/bulk", h.CreateStocksBulk)
			authed.GET("/stocks/trends", h.GetStockTrends)
			authed.GET("/stocks/history", h.GetStockHistory)
			authed.POST("/stocks/refresh-prices", h.RefreshStockPrices)
			authed.GET("/stocks/:id", h.GetStock)
			authed.PUT("/stocks/:id", h.UpdateStock)
			authed.PUT("/stocks/:id/holdings", h.UpdateStockHoldings)
			authed.POST("/stocks/:id/hold", h.MarkStockHold)
			authed.PUT("/stocks/:id/thresholds", h.SetStockThresholds)

			authed.POST("/transactions/buy", h.CreateBuyTransaction)
			authed.POST("/transactions/buy/replace-by-source", h.ReplaceSourceBuyTransactions)
			authed.POST("/transactions/sell", h.CreateSellTransaction)
			authed.GET("/transactions", h.GetTransactions)

			authed.GET("/mutualfunds", h.GetMutualFunds)
			authed.POST("/mutualfunds", h.CreateMutualFund)
			authed.GET("/mutualfunds/:id", h.GetMutualFund)
			authed.PUT("/mutualfunds/:id", h.UpdateMutualFund)
			authed.DELETE("/mutualfunds/:id", h.DeleteMutualFund)

			authed.GET("/portfolio", h.GetPortfolio)
			authed.GET("/portfolio/summary", h.GetPortfolioSummary)

			admin := authed.Group("")
			admin.Use(middleware.RequireAdmin())
			{
				admin.DELETE("/stocks/:id", h.DeleteStock)
				admin.PUT("/stocks/:id/admin", h.UpdateStockAdminFields)

				admin.GET("/symbol-mappings", h.GetSymbolMappings)
				admin.POST("/symbol-mappings", h.CreateSymbolMapping)
				admin.PUT("/symbol-mappings/:id", h.UpdateSymbolMapping)
				admin.DELETE("/symbol-mappings/:id", h.DeleteSymbolMapping)
				admin.GET("/admin/unmapped-stocks", h.GetUnmappedStocks)

				admin.GET("/admin/users", h.ListUsers)
				admin.POST("/admin/users", h.CreateUser)
				admin.PUT("/admin/users/:id/enabled", h.SetUserEnabled)

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
