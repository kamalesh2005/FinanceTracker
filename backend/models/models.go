package models

import (
	"time"
)

type Stock struct {
	ID                uint          `json:"id" gorm:"primaryKey"`
	Symbol            string        `json:"symbol" gorm:"not null;uniqueIndex"`
	Name              string        `json:"name"`
	Sector            string        `json:"sector"`
	CurrentPrice      float64       `json:"current_price"`
	SixthHighestPrice float64       `json:"sixth_highest_price"`
	SixthLowestPrice  float64       `json:"sixth_lowest_price"`
	LastFetchedDate   *time.Time    `json:"last_fetched_date"`
	CreatedAt         time.Time     `json:"created_at"`
	UpdatedAt         time.Time     `json:"updated_at"`
	Transactions      []Transaction `json:"transactions" gorm:"foreignKey:StockID"`
	// Legacy fields for migration - will be removed after migration
	LegacyQuantity     float64   `json:"-" gorm:"column:quantity"`
	LegacyBuyPrice     float64   `json:"-" gorm:"column:buy_price"`
	LegacyPurchaseDate time.Time `json:"-" gorm:"column:purchase_date"`
}

type TransactionType string

const (
	TransactionTypeBuy  TransactionType = "buy"
	TransactionTypeSell TransactionType = "sell"
)

type Transaction struct {
	ID                uint            `json:"id" gorm:"primaryKey"`
	StockID           uint            `json:"stock_id" gorm:"not null;index"`
	Type              TransactionType `json:"type" gorm:"not null"`
	Quantity          float64         `json:"quantity" gorm:"not null"`
	Price             float64         `json:"price" gorm:"not null"`
	RemainingQuantity float64         `json:"remaining_quantity" gorm:"not null"`
	TransactionDate   time.Time       `json:"transaction_date" gorm:"not null"`
	CreatedAt         time.Time       `json:"created_at"`
	UpdatedAt         time.Time       `json:"updated_at"`
	Stock             Stock           `json:"stock" gorm:"foreignKey:StockID"`
}

type MutualFund struct {
	ID           uint      `json:"id" gorm:"primaryKey"`
	SchemeCode   string    `json:"scheme_code" gorm:"not null"`
	SchemeName   string    `json:"scheme_name"`
	FundHouse    string    `json:"fund_house"`
	Quantity     float64   `json:"quantity" gorm:"not null"`
	NAV          float64   `json:"nav" gorm:"not null"`
	CurrentNAV   float64   `json:"current_nav"`
	PurchaseDate time.Time `json:"purchase_date"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type Portfolio struct {
	ID             uint      `json:"id" gorm:"primaryKey"`
	Name           string    `json:"name" gorm:"not null"`
	TotalValue     float64   `json:"total_value"`
	InvestedAmount float64   `json:"invested_amount"`
	ProfitLoss     float64   `json:"profit_loss"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}
