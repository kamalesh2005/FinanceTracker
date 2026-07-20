package models

import (
	"strings"
	"time"
)

type Stock struct {
	ID                uint          `json:"id" gorm:"primaryKey"`
	Symbol            string        `json:"symbol" gorm:"not null;uniqueIndex"`
	ISIN              string        `json:"isin" gorm:"size:64;index"`
	Name              string        `json:"name"`
	Sector            string        `json:"sector"`
	MarketCap         string        `json:"market_cap"` // "Large Cap" | "Mid Cap" | "Small Cap" | ""
	CurrentPrice      float64       `json:"current_price"`
	SixthHighestPrice float64       `json:"sixth_highest_price"`
	SixthLowestPrice  float64       `json:"sixth_lowest_price"`
	LastFetchedDate      *time.Time `json:"last_fetched_date"`
	LastPriceFetchedDate *time.Time `json:"last_price_fetched_date"`
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

const (
	SourceManualAdd        = "Manual Add"
	SourceManualBulkUpload = "Manual Bulk Upload"
	SourceICICIDirect      = "ICICIDirect"
	SourceHDFCSec          = "HDFCSec"
)

// IsReplaceableImportSource reports whether a bulk save should replace all prior buy lots for this source.
// Any non-empty source except Manual Add is replaceable (brokers, Manual Bulk Upload, future sources).
func IsReplaceableImportSource(source string) bool {
	source = strings.TrimSpace(source)
	return source != "" && source != SourceManualAdd
}


type Transaction struct {
	ID                uint            `json:"id" gorm:"primaryKey"`
	StockID           uint            `json:"stock_id" gorm:"not null;index"`
	Type              TransactionType `json:"type" gorm:"not null"`
	Quantity          float64         `json:"quantity" gorm:"not null"`
	Price             float64         `json:"price" gorm:"not null"`
	RemainingQuantity float64         `json:"remaining_quantity" gorm:"not null"`
	TransactionDate   time.Time       `json:"transaction_date" gorm:"not null"`
	Source            string          `json:"source" gorm:"index"`
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

// SymbolMapping maps broker/source symbols (ICICI, etc.) to Yahoo/NSE tickers.
type SymbolMapping struct {
	ID           uint      `json:"id" gorm:"primaryKey"`
	SourceSymbol string    `json:"source_symbol" gorm:"not null;uniqueIndex;size:64"`
	YahooSymbol  string    `json:"yahoo_symbol" gorm:"not null;size:64"`
	ISIN         string    `json:"isin" gorm:"size:12;index"`
	SourceFormat string    `json:"source_format" gorm:"index;size:64"` // e.g. ICICIDirect, NSE, Manual
	Notes        string    `json:"notes"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

const (
	SourceFormatICICIDirect = "ICICIDirect"
	SourceFormatNSE         = "NSE"
	SourceFormatManual      = "Manual"
)
