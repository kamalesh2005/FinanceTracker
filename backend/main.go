package main

import (
	"financetracker/handlers"
	"financetracker/models"
	"log"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func migrateStocksToTransactions(db *gorm.DB) {
	var stocks []models.Stock

	// Find stocks with legacy data (quantity > 0) but no transactions
	db.Where("quantity > 0").Find(&stocks)

	for _, stock := range stocks {
		// Check if stock already has transactions
		var transactionCount int64
		db.Model(&models.Transaction{}).Where("stock_id = ?", stock.ID).Count(&transactionCount)

		if transactionCount == 0 && stock.LegacyQuantity > 0 {
			// Create a buy transaction from legacy data
			transaction := models.Transaction{
				StockID:           stock.ID,
				Type:              models.TransactionTypeBuy,
				Quantity:          stock.LegacyQuantity,
				Price:             stock.LegacyBuyPrice,
				RemainingQuantity: stock.LegacyQuantity,
				TransactionDate:   stock.LegacyPurchaseDate,
			}

			if err := db.Create(&transaction).Error; err != nil {
				log.Printf("Failed to migrate stock %s: %v", stock.Symbol, err)
			} else {
				log.Printf("Migrated stock %s: %.2f shares @ ₹%.2f", stock.Symbol, stock.LegacyQuantity, stock.LegacyBuyPrice)
			}
		}
	}
}

func main() {
	// Initialize database
	dsn := "host=localhost user=finance password=finance dbname=financetracker port=5432 sslmode=disable"
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}

	// Auto migrate models
	db.AutoMigrate(&models.Stock{}, &models.MutualFund{}, &models.Portfolio{}, &models.Transaction{})

	// Migrate existing stock data to transactions
	migrateStocksToTransactions(db)

	// Initialize Gin router
	r := gin.Default()

	// Add CORS middleware
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
	}))

	// Initialize handlers with database
	h := handlers.NewHandler(db)

	// API routes
	api := r.Group("/api/v1")
	{
		// Stock routes
		api.GET("/stocks", h.GetStocks)
		api.POST("/stocks", h.CreateStock)
		api.POST("/stocks/bulk", h.CreateStocksBulk)
		api.GET("/stocks/trends", h.GetStockTrends)
		api.GET("/stocks/history", h.GetStockHistory)
		api.POST("/stocks/refresh-prices", h.RefreshStockPrices)
		api.GET("/stocks/:id", h.GetStock)
		api.PUT("/stocks/:id", h.UpdateStock)
		api.DELETE("/stocks/:id", h.DeleteStock)

		// Transaction routes
		api.POST("/transactions/buy", h.CreateBuyTransaction)
		api.POST("/transactions/sell", h.CreateSellTransaction)
		api.GET("/transactions", h.GetTransactions)

		// Mutual Fund routes
		api.GET("/mutualfunds", h.GetMutualFunds)
		api.POST("/mutualfunds", h.CreateMutualFund)
		api.GET("/mutualfunds/:id", h.GetMutualFund)
		api.PUT("/mutualfunds/:id", h.UpdateMutualFund)
		api.DELETE("/mutualfunds/:id", h.DeleteMutualFund)

		// Portfolio routes
		api.GET("/portfolio", h.GetPortfolio)
		api.GET("/portfolio/summary", h.GetPortfolioSummary)
	}

	// Start server
	log.Println("Server starting on :8080")
	r.Run(":8080")
}
