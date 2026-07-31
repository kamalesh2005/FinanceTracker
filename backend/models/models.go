package models

import (
	"strings"
	"time"
)

type Stock struct {
	ID                   uint        `json:"id" gorm:"primaryKey"`
	Symbol               string      `json:"symbol" gorm:"not null;uniqueIndex"`
	ISIN                 string      `json:"isin" gorm:"size:64;index"`
	Name                 string      `json:"name"`
	Sector               string      `json:"sector"`
	MarketCap            string      `json:"market_cap"` // "Large Cap" | "Mid Cap" | "Small Cap" | ""
	CurrentPrice         float64     `json:"current_price"`
	SixthHighestPrice    float64     `json:"sixth_highest_price"`
	SixthLowestPrice     float64     `json:"sixth_lowest_price"`
	MA7                  float64     `json:"ma7"`
	MA20                 float64     `json:"ma20"`
	MA50                 float64     `json:"ma50"`
	SensexMA7            float64     `json:"sensex_ma7"`
	SensexMA20           float64     `json:"sensex_ma20"`
	SensexMA50           float64     `json:"sensex_ma50"`
	StockSTDelta         float64     `json:"stock_st_delta"`
	MarketSTDelta        float64     `json:"market_st_delta"`
	AdjustedSTDelta      float64     `json:"adjusted_st_delta"`
	StockMTDelta         float64     `json:"stock_mt_delta"`
	MarketMTDelta        float64     `json:"market_mt_delta"`
	AdjustedMTDelta      float64     `json:"adjusted_mt_delta"`
	Trend                string      `json:"trend"`
	LastFetchedDate      *time.Time  `json:"last_fetched_date"`
	LastPriceFetchedDate *time.Time  `json:"last_price_fetched_date"`
	LastTrendFetchedDate *time.Time  `json:"last_trend_fetched_date"`
	// Trendlyne consensus target (scraped from research-reports page).
	TrendlyneURL              string     `json:"trendlyne_url" gorm:"size:512"`
	ConsensusDate             *time.Time `json:"consensus_date"`
	ConsensusLTP              float64    `json:"consensus_ltp"`
	ConsensusTarget           float64    `json:"consensus_target"`
	ConsensusUpside           float64    `json:"consensus_upside"`
	ConsensusType             string     `json:"consensus_type" gorm:"size:32"`
	LastConsensusFetchedDate  *time.Time `json:"last_consensus_fetched_date"`
	CreatedAt                 time.Time  `json:"created_at"`
	UpdatedAt                 time.Time  `json:"updated_at"`
	UserStocks                []UserStock `json:"user_stocks,omitempty" gorm:"foreignKey:StockID"`
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
	SourceZerodha          = "Zerodha"
)

// IsReplaceableImportSource reports whether a bulk save should upsert buy lots for this source
// (update existing source+stock, insert missing, zero stale lots not in the upload).
// Any non-empty source except Manual Add is replaceable (brokers, Manual Bulk Upload, future sources).
func IsReplaceableImportSource(source string) bool {
	source = strings.TrimSpace(source)
	return source != "" && source != SourceManualAdd
}

// UserStock is the final holding for a user+source+stock.
type UserStock struct {
	ID                    uint       `json:"id" gorm:"primaryKey"`
	UserID                uint       `json:"user_id" gorm:"not null;uniqueIndex:idx_user_stock_source;index;default:0"`
	StockID               uint       `json:"stock_id" gorm:"not null;uniqueIndex:idx_user_stock_source;index"`
	Source                string     `json:"source" gorm:"not null;uniqueIndex:idx_user_stock_source;index;size:64"`
	Quantity              float64    `json:"quantity" gorm:"not null;default:0"`
	AvgBuyPrice           float64    `json:"avg_buy_price" gorm:"not null;default:0"`
	LastBuyPrice          float64    `json:"last_buy_price" gorm:"not null;default:0"`
	LastBuyDate           *time.Time `json:"last_buy_date"`
	LastSalePrice         float64    `json:"last_sale_price" gorm:"not null;default:0"`
	LastSaleDate          *time.Time `json:"last_sale_date"`
	LastHoldPrice         float64    `json:"last_hold_price" gorm:"not null;default:0"`
	LastHoldDate          *time.Time `json:"last_hold_date"`
	SetBuyPrice           float64    `json:"set_buy_price" gorm:"not null;default:0"`
	SetProfitBookingPrice float64    `json:"set_profit_booking_price" gorm:"not null;default:0"`
	SetStopLossPrice      float64    `json:"set_stop_loss_price" gorm:"not null;default:0"`
	CreatedAt             time.Time  `json:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
	Stock                 Stock      `json:"stock" gorm:"foreignKey:StockID"`
}

// UserStockTransaction is a buy/sell ledger entry.
// For buys, Quantity is remaining open lot size; OriginalQuantity is the size at insert.
// Sell FIFO reduces buy Quantity only (never OriginalQuantity). Sell rows are immutable.
type UserStockTransaction struct {
	ID               uint            `json:"id" gorm:"primaryKey"`
	UserID           uint            `json:"user_id" gorm:"not null;index;default:0"`
	StockID          uint            `json:"stock_id" gorm:"not null;index"`
	Source           string          `json:"source" gorm:"not null;index;size:64"`
	Type             TransactionType `json:"type" gorm:"not null;size:16"`
	Quantity         float64         `json:"quantity" gorm:"not null"`
	OriginalQuantity float64         `json:"original_quantity" gorm:"not null;default:0"`
	Price            float64         `json:"price" gorm:"not null"`
	TransactionDate  time.Time       `json:"transaction_date" gorm:"not null"`
	CreatedAt        time.Time       `json:"created_at"`
	Stock            Stock           `json:"stock" gorm:"foreignKey:StockID"`
}

type MutualFund struct {
	ID           uint      `json:"id" gorm:"primaryKey"`
	UserID       uint      `json:"user_id" gorm:"not null;index;default:0"`
	SchemeCode   string    `json:"scheme_code" gorm:"not null"`
	SchemeName   string    `json:"scheme_name"`
	FundHouse    string    `json:"fund_house"`
	Source       string    `json:"source" gorm:"not null;index;size:64;default:Manual Add"`
	Quantity     float64   `json:"quantity" gorm:"not null"`
	NAV          float64   `json:"nav" gorm:"not null"`
	CurrentNAV   float64   `json:"current_nav"`
	PurchaseDate time.Time `json:"purchase_date"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// UserConfig stores per-user UI preferences.
type UserConfig struct {
	ID                  uint   `json:"id" gorm:"primaryKey"`
	UserID              uint   `json:"user_id" gorm:"uniqueIndex;not null"`
	HiddenStockColumns  string `json:"hidden_stock_columns" gorm:"type:text"`
	UseAsStockWatchList bool   `json:"use_as_stock_watch_list" gorm:"not null;default:false"`
	// Deprecated: migrated into RecommendationRulesJSON named_values.fluctuation_pct.
	RecommendationFluctuationPct *float64 `json:"recommendation_fluctuation_pct"`
	// nil = inherit AppConfig default ruleset.
	RecommendationRulesJSON *string   `json:"recommendation_rules_json" gorm:"type:text"`
	CreatedAt               time.Time `json:"created_at"`
	UpdatedAt               time.Time `json:"updated_at"`
}

// AppConfig is a singleton (id=1) for admin-managed app defaults.
type AppConfig struct {
	ID                                  uint      `json:"id" gorm:"primaryKey"`
	DefaultRecommendationFluctuationPct float64   `json:"default_recommendation_fluctuation_pct" gorm:"not null;default:5"`
	RecommendationRulesJSON             string    `json:"recommendation_rules_json" gorm:"type:text"`
	CreatedAt                           time.Time `json:"created_at"`
	UpdatedAt                           time.Time `json:"updated_at"`
}

const (
	RoleAdmin = "admin"
	RoleUser  = "user"
)

// User is an application account (platform admin or end-user).
type User struct {
	ID           uint      `json:"id" gorm:"primaryKey"`
	Username     *string   `json:"username,omitempty" gorm:"uniqueIndex;size:64"`
	Email        *string   `json:"email,omitempty" gorm:"uniqueIndex;size:255"`
	Mobile       *string   `json:"mobile,omitempty" gorm:"uniqueIndex;size:32"`
	PasswordHash string    `json:"-" gorm:"not null"`
	Role         string    `json:"role" gorm:"not null;size:16;default:user"`
	Enabled      bool      `json:"enabled" gorm:"not null;default:true"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

const (
	OTPChannelEmail = "email"
	OTPChannelSMS   = "sms"
)

// PasswordResetOTP stores hashed one-time codes for password reset.
type PasswordResetOTP struct {
	ID          uint       `json:"id" gorm:"primaryKey"`
	UserID      uint       `json:"user_id" gorm:"not null;index"`
	Channel     string     `json:"channel" gorm:"not null;size:16"`
	Destination string     `json:"destination" gorm:"not null;size:255"`
	CodeHash    string     `json:"-" gorm:"not null"`
	ExpiresAt   time.Time  `json:"expires_at" gorm:"not null"`
	UsedAt      *time.Time `json:"used_at"`
	CreatedAt   time.Time  `json:"created_at"`
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
