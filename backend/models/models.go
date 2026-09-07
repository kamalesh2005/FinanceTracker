package models

import (
	"strings"
	"time"
)

const (
	PullDataYes = "Y"
	PullDataNo  = "N"
)

type Stock struct {
	ID                   uint       `json:"id" gorm:"primaryKey"`
	Symbol               string     `json:"symbol" gorm:"not null;uniqueIndex"`
	ISIN                 string     `json:"isin" gorm:"size:64;index"`
	Name                 string     `json:"name"`
	Sector               string     `json:"sector"`
	Industry             string     `json:"industry"`
	MarketCap            string     `json:"market_cap"` // "Large Cap" | "Mid Cap" | "Small Cap" | ""
	CurrentPrice         float64    `json:"current_price"`
	SixthHighestPrice    float64    `json:"sixth_highest_price"`
	SixthLowestPrice     float64    `json:"sixth_lowest_price"`
	MA7                  float64    `json:"ma7"`
	MA20                 float64    `json:"ma20"`
	MA50                 float64    `json:"ma50"`
	SensexMA7            float64    `json:"sensex_ma7"`
	SensexMA20           float64    `json:"sensex_ma20"`
	SensexMA50           float64    `json:"sensex_ma50"`
	StockSTDelta         float64    `json:"stock_st_delta"`
	MarketSTDelta        float64    `json:"market_st_delta"`
	AdjustedSTDelta      float64    `json:"adjusted_st_delta"`
	StockMTDelta         float64    `json:"stock_mt_delta"`
	MarketMTDelta        float64    `json:"market_mt_delta"`
	AdjustedMTDelta      float64    `json:"adjusted_mt_delta"`
	Trend                string     `json:"trend"`
	LastFetchedDate      *time.Time `json:"last_fetched_date"`
	LastPriceFetchedDate *time.Time `json:"last_price_fetched_date"`
	LastTrendFetchedDate *time.Time `json:"last_trend_fetched_date"`
	// NSE catalog fields (from exchange CSV imports).
	TradeDate       *time.Time `json:"trade_date"`
	Series          string     `json:"series" gorm:"size:16"`
	ListingCategory string     `json:"listing_category" gorm:"size:32"`
	LastTradeDate   *time.Time `json:"last_trade_date"`
	FaceValue       float64    `json:"face_value"`
	IssueSize       float64    `json:"issue_size"`
	MarketCapRs     float64    `json:"market_cap_rs"`
	// PullData gates Yahoo crons: Y when any user holds the symbol, else N.
	PullData string `json:"pull_data" gorm:"size:1;not null;default:N;index"`
	// LtpFY2020…2025 are FY-end closes: FY N ends 31 Mar (N+1).
	LtpFY2020 float64 `json:"ltp_fy_2020" gorm:"column:ltp_fy_2020"`
	LtpFY2021 float64 `json:"ltp_fy_2021" gorm:"column:ltp_fy_2021"`
	LtpFY2022 float64 `json:"ltp_fy_2022" gorm:"column:ltp_fy_2022"`
	LtpFY2023 float64 `json:"ltp_fy_2023" gorm:"column:ltp_fy_2023"`
	LtpFY2024 float64 `json:"ltp_fy_2024" gorm:"column:ltp_fy_2024"`
	LtpFY2025 float64 `json:"ltp_fy_2025" gorm:"column:ltp_fy_2025"`
	// Analyst 1Y target (Yahoo financialData) plus latest Yahoo headline.
	TrendlyneURL             string      `json:"trendlyne_url" gorm:"size:512"`
	ConsensusDate            *time.Time  `json:"consensus_date"`
	ConsensusLTP             float64     `json:"consensus_ltp"`
	ConsensusTarget          float64     `json:"consensus_target"`
	ConsensusUpside          float64     `json:"consensus_upside"`
	ConsensusType            string      `json:"consensus_type" gorm:"size:32"`
	LastConsensusFetchedDate *time.Time  `json:"last_consensus_fetched_date"`
	LastNewsFetchedDate      *time.Time  `json:"last_news_fetched_date"`
	// LastCatalogYahooRefreshAt gates the 02:00 non-held EQ catalog Yahoo cron (weekly + daily cap).
	LastCatalogYahooRefreshAt *time.Time `json:"last_catalog_yahoo_refresh_at"`
	NewsHeadline              string     `json:"news_headline" gorm:"size:512"`
	NewsURL                   string     `json:"news_url" gorm:"size:1024"`
	CreatedAt                time.Time   `json:"created_at"`
	UpdatedAt                time.Time   `json:"updated_at"`
	UserStocks               []UserStock `json:"user_stocks,omitempty" gorm:"foreignKey:StockID"`
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
	SourceNSDLMFFolios     = "NSDL MF Folios"
)

const (
	TxOriginUI                  = "ui"
	TxOriginICICITransactions   = "icici_transactions"
	TxOriginSnapshot            = "snapshot"
	TxOriginHDFCTransactions    = "hdfc_transactions"
	TxOriginZerodhaTransactions = "zerodha_transactions"
	TxOriginBulkTransactions    = "bulk_transactions"
)

// TxOriginForPartialLedger returns the ledger origin for a partial trade-file merge source.
func TxOriginForPartialLedger(source string) string {
	switch strings.TrimSpace(source) {
	case SourceHDFCSec:
		return TxOriginHDFCTransactions
	case SourceZerodha:
		return TxOriginZerodhaTransactions
	case SourceManualBulkUpload:
		return TxOriginBulkTransactions
	default:
		return TxOriginSnapshot
	}
}

// IsPartialLedgerImportSource reports whether source supports merge-from-ledger uploads.
func IsPartialLedgerImportSource(source string) bool {
	switch strings.TrimSpace(source) {
	case SourceHDFCSec, SourceZerodha, SourceManualBulkUpload:
		return true
	default:
		return false
	}
}

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
	LastBuyTrend          string     `json:"last_buy_trend" gorm:"size:64"`
	LastSalePrice         float64    `json:"last_sale_price" gorm:"not null;default:0"`
	LastSaleDate          *time.Time `json:"last_sale_date"`
	LastSaleTrend         string     `json:"last_sale_trend" gorm:"size:64"`
	LastHoldPrice         float64    `json:"last_hold_price" gorm:"not null;default:0"`
	LastHoldDate          *time.Time `json:"last_hold_date"`
	LastHoldTrend         string     `json:"last_hold_trend" gorm:"size:64"`
	SetBuyPrice           float64    `json:"set_buy_price" gorm:"not null;default:0"`
	SetProfitBookingPrice float64    `json:"set_profit_booking_price" gorm:"not null;default:0"`
	SetStopLossPrice      float64    `json:"set_stop_loss_price" gorm:"not null;default:0"`
	BSHClearDate          *time.Time `json:"bsh_clear_date"`
	Notes                 string     `json:"notes" gorm:"size:200"`
	CreatedAt             time.Time  `json:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
	Stock                 Stock      `json:"stock" gorm:"foreignKey:StockID"`
}

// UserWatchlist is a per-user curated catalog list (not a holding).
type UserWatchlist struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	UserID    uint      `json:"user_id" gorm:"not null;uniqueIndex:idx_user_watchlist"`
	StockID   uint      `json:"stock_id" gorm:"not null;uniqueIndex:idx_user_watchlist;index"`
	CreatedAt time.Time `json:"created_at"`
	Stock     Stock     `json:"stock" gorm:"foreignKey:StockID"`
}

// DefaultScreenerLabels are built-in label names for the stock screener.
var DefaultScreenerLabels = []string{"Hide", "Track", "Ignore"}

// ScreenerLabelUnlabeled is the filter sentinel for stocks with no labels.
const ScreenerLabelUnlabeled = "__unlabeled__"

// UserScreenerStockLabel is a per-user label on a catalog stock in the screener.
type UserScreenerStockLabel struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	UserID    uint      `json:"user_id" gorm:"not null;uniqueIndex:idx_user_screener_label"`
	StockID   uint      `json:"stock_id" gorm:"not null;uniqueIndex:idx_user_screener_label;index"`
	Label     string    `json:"label" gorm:"not null;size:64;uniqueIndex:idx_user_screener_label"`
	CreatedAt time.Time `json:"created_at"`
}

// UserStockTransaction is a buy/sell ledger entry.
// For buys, Quantity is remaining open lot size; OriginalQuantity is the size of this slice.
// A FIFO sell stamps SalePrice/SaleDate on the matched buy slice and splits the row
// when only part of the lot is sold. Sell rows stay in the ledger for history.
type UserStockTransaction struct {
	ID                 uint            `json:"id" gorm:"primaryKey"`
	UserID             uint            `json:"user_id" gorm:"not null;index;default:0"`
	StockID            uint            `json:"stock_id" gorm:"not null;index"`
	Source             string          `json:"source" gorm:"not null;index;size:64"`
	Type               TransactionType `json:"type" gorm:"not null;size:16"`
	Quantity           float64         `json:"quantity" gorm:"not null"`
	OriginalQuantity   float64         `json:"original_quantity" gorm:"not null;default:0"`
	Price              float64         `json:"price" gorm:"not null"`
	SalePrice          float64         `json:"sale_price" gorm:"not null;default:0"`
	SaleDate           *time.Time      `json:"sale_date"`
	TransactionDate    *time.Time      `json:"transaction_date"`
	Origin             string          `json:"origin" gorm:"size:32"`
	Brokerage          float64         `json:"brokerage" gorm:"not null;default:0"`
	TransactionCharges float64         `json:"transaction_charges" gorm:"not null;default:0"`
	StampDuty          float64         `json:"stamp_duty" gorm:"not null;default:0"`
	Segment            string          `json:"segment" gorm:"size:64"`
	STT                string          `json:"stt" gorm:"size:64"`
	Exchange           string          `json:"exchange" gorm:"size:32"`
	CreatedAt          time.Time       `json:"created_at"`
	Stock              Stock           `json:"stock" gorm:"foreignKey:StockID"`
}

// GlobalMutualFund is the shared MF catalog (ISIN unique).
type GlobalMutualFund struct {
	ID                 uint       `json:"id" gorm:"primaryKey"`
	ISIN               string     `json:"isin" gorm:"size:64;not null;uniqueIndex"`
	Symbol             string     `json:"symbol" gorm:"size:32;index"` // scheme code
	SchemeName         string     `json:"scheme_name"`
	Series             string     `json:"series" gorm:"size:16"`
	Type               string     `json:"type" gorm:"size:16"`
	Haircut            float64    `json:"haircut"`
	AcceptableQuantity float64    `json:"acceptable_quantity"`
	ApplicableHaircut  string     `json:"applicable_haircut" gorm:"size:128"`
	CurrentNAV         float64    `json:"current_nav"`
	LastNAVDate        *time.Time `json:"last_nav_date"`
	// NavFY2020…2025 are FY-end NAVs: FY N ends 31 Mar (N+1).
	NavFY2020          float64    `json:"nav_fy_2020" gorm:"column:nav_fy_2020"`
	NavFY2021          float64    `json:"nav_fy_2021" gorm:"column:nav_fy_2021"`
	NavFY2022          float64    `json:"nav_fy_2022" gorm:"column:nav_fy_2022"`
	NavFY2023          float64    `json:"nav_fy_2023" gorm:"column:nav_fy_2023"`
	NavFY2024          float64    `json:"nav_fy_2024" gorm:"column:nav_fy_2024"`
	NavFY2025          float64    `json:"nav_fy_2025" gorm:"column:nav_fy_2025"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
}

// GlobalIndex is a shared market-index catalog (symbol unique), e.g. NIFTY50.
type GlobalIndex struct {
	ID            uint       `json:"id" gorm:"primaryKey"`
	Symbol        string     `json:"symbol" gorm:"size:32;not null;uniqueIndex"`
	Name          string     `json:"name"`
	YahooSymbol   string     `json:"yahoo_symbol" gorm:"size:32"`
	CurrentValue  float64    `json:"current_value"`
	LastValueDate *time.Time `json:"last_value_date"`
	// FY2020…2025 are FY-end closes: FY N ends 31 Mar (N+1).
	FY2020        float64    `json:"fy_2020" gorm:"column:fy_2020"`
	FY2021        float64    `json:"fy_2021" gorm:"column:fy_2021"`
	FY2022        float64    `json:"fy_2022" gorm:"column:fy_2022"`
	FY2023        float64    `json:"fy_2023" gorm:"column:fy_2023"`
	FY2024        float64    `json:"fy_2024" gorm:"column:fy_2024"`
	FY2025        float64    `json:"fy_2025" gorm:"column:fy_2025"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
	// Return2021…2025 / ReturnYTD are FY YoY and YTD (not persisted).
	Return2021    *float64   `json:"return_2021,omitempty" gorm:"-"`
	Return2022    *float64   `json:"return_2022,omitempty" gorm:"-"`
	Return2023    *float64   `json:"return_2023,omitempty" gorm:"-"`
	Return2024    *float64   `json:"return_2024,omitempty" gorm:"-"`
	Return2025    *float64   `json:"return_2025,omitempty" gorm:"-"`
	ReturnYTD     *float64   `json:"return_ytd,omitempty" gorm:"-"`
}

type MutualFund struct {
	ID               uint      `json:"id" gorm:"primaryKey"`
	UserID           uint      `json:"user_id" gorm:"not null;index;default:0"`
	ISIN             string    `json:"isin" gorm:"size:64;index"`
	SchemeCode       string    `json:"scheme_code" gorm:"not null"`
	SchemeName       string    `json:"scheme_name"`
	SourceSchemeName string    `json:"source_scheme_name" gorm:"size:512;index"`
	FundHouse        string    `json:"fund_house"`
	Source           string    `json:"source" gorm:"not null;index;size:64;default:Manual Add"`
	Quantity         float64   `json:"quantity" gorm:"not null"`
	NAV              float64   `json:"nav" gorm:"not null"`
	CurrentNAV       float64   `json:"current_nav"`
	PurchaseDate     time.Time `json:"purchase_date"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
	// Computed FY YoY / YTD % returns from Global_MutualFunds FY-end NAVs (not persisted).
	Return2021 *float64 `json:"return_2021,omitempty" gorm:"-"`
	Return2022 *float64 `json:"return_2022,omitempty" gorm:"-"`
	Return2023 *float64 `json:"return_2023,omitempty" gorm:"-"`
	Return2024 *float64 `json:"return_2024,omitempty" gorm:"-"`
	Return2025 *float64 `json:"return_2025,omitempty" gorm:"-"`
	ReturnYTD  *float64 `json:"return_ytd,omitempty" gorm:"-"`
}

// UserMutualFundTransaction is a buy/sell ledger entry for mutual funds.
// For buys, Quantity is remaining open lot size; OriginalQuantity is the size of this slice.
// A FIFO sell stamps SalePrice/SaleDate on the matched buy slice and splits the row
// when only part of the lot is sold. Sell rows stay in the ledger for history.
// Snapshot holdings uploads omit TransactionDate (nil) when the file has no dates.
type UserMutualFundTransaction struct {
	ID                 uint            `json:"id" gorm:"primaryKey"`
	UserID             uint            `json:"user_id" gorm:"not null;index;default:0"`
	ISIN               string          `json:"isin" gorm:"size:64;index"`
	SourceSchemeName   string          `json:"source_scheme_name" gorm:"size:512;index"`
	Source             string          `json:"source" gorm:"not null;index;size:64"`
	Type               TransactionType `json:"type" gorm:"not null;size:16"`
	Quantity           float64         `json:"quantity" gorm:"not null"`
	OriginalQuantity   float64         `json:"original_quantity" gorm:"not null;default:0"`
	Price              float64         `json:"price" gorm:"not null"` // NAV
	SalePrice          float64         `json:"sale_price" gorm:"not null;default:0"`
	SaleDate           *time.Time      `json:"sale_date"`
	TransactionDate    *time.Time      `json:"transaction_date"`
	Origin             string          `json:"origin" gorm:"size:32"`
	CreatedAt          time.Time       `json:"created_at"`
}

// UserConfig stores per-user UI preferences.
type UserConfig struct {
	ID                      uint   `json:"id" gorm:"primaryKey"`
	UserID                  uint   `json:"user_id" gorm:"uniqueIndex;not null"`
	HiddenStockColumns      string `json:"hidden_stock_columns" gorm:"type:text"`
	HiddenMutualFundColumns string `json:"hidden_mutual_fund_columns" gorm:"type:text"`
	HiddenScreenerColumns   string `json:"hidden_screener_columns" gorm:"type:text"`
	UseAsStockWatchList     bool   `json:"use_as_stock_watch_list" gorm:"not null;default:false"`
	ShowXIRR                bool   `json:"show_xirr" gorm:"not null;default:true"`
	ShowZeroQuantityStocks  bool   `json:"show_zero_quantity_stocks" gorm:"not null;default:false"`
	// Deprecated: migrated into RecommendationRulesJSON named_values.fluctuation_pct.
	RecommendationFluctuationPct *float64 `json:"recommendation_fluctuation_pct"`
	// nil = inherit AppConfig default ruleset.
	RecommendationRulesJSON *string   `json:"recommendation_rules_json" gorm:"type:text"`
	StockReviewEmailEnabled      bool `json:"stock_review_email_enabled" gorm:"not null;default:true"`
	StockReviewEmailAdminEnabled bool `json:"stock_review_email_admin_enabled" gorm:"not null;default:false"`
	CreatedAt               time.Time `json:"created_at"`
	UpdatedAt               time.Time `json:"updated_at"`
}

// AppConfig is a singleton (id=1) for admin-managed app defaults.
type AppConfig struct {
	ID                                  uint      `json:"id" gorm:"primaryKey"`
	DefaultRecommendationFluctuationPct float64   `json:"default_recommendation_fluctuation_pct" gorm:"not null;default:5"`
	RecommendationRulesJSON             string    `json:"recommendation_rules_json" gorm:"type:text"`
	TrendRulesJSON                      string    `json:"trend_rules_json" gorm:"type:text"`
	CreatedAt                           time.Time `json:"created_at"`
	UpdatedAt                           time.Time `json:"updated_at"`
}

const (
	RoleAdmin = "admin"
	RoleUser  = "user"

	DefaultPortalMain    = "main"
	DefaultPortalLearner = "learner"
)

// User is an application account (platform admin or end-user).
type User struct {
	ID            uint       `json:"id" gorm:"primaryKey"`
	Username      *string    `json:"username,omitempty" gorm:"uniqueIndex;size:64"`
	Email         *string    `json:"email,omitempty" gorm:"uniqueIndex;size:255"`
	Mobile        *string    `json:"mobile,omitempty" gorm:"uniqueIndex;size:32"`
	PasswordHash  *string    `json:"-"`
	GoogleAuth    bool       `json:"google_auth" gorm:"not null;default:false"`
	GoogleSub     *string    `json:"-" gorm:"uniqueIndex;size:64"`
	Role          string     `json:"role" gorm:"not null;size:16;default:user"`
	Enabled       bool       `json:"enabled" gorm:"not null;default:true"`
	LastLoginAt   *time.Time `json:"last_login_at,omitempty"`
	LoginCount    uint       `json:"login_count" gorm:"not null;default:0"`
	DefaultPortal string     `json:"default_portal" gorm:"not null;size:16;default:main"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

func NormalizeDefaultPortal(raw string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "", DefaultPortalMain:
		return DefaultPortalMain, true
	case DefaultPortalLearner:
		return DefaultPortalLearner, true
	default:
		return "", false
	}
}

func (u User) EffectiveDefaultPortal() string {
	portal, ok := NormalizeDefaultPortal(u.DefaultPortal)
	if !ok {
		return DefaultPortalMain
	}
	return portal
}

// HasPassword is true when a bcrypt hash is stored (password accounts only).
func (u User) HasPassword() bool {
	return u.PasswordHash != nil && *u.PasswordHash != ""
}

const (
	OTPChannelEmail = "email"
	OTPChannelSMS   = "sms"
)

// RefreshToken stores a hashed opaque session renewal token per device/login.
type RefreshToken struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	UserID    uint      `json:"user_id" gorm:"not null;index"`
	TokenHash string    `json:"-" gorm:"not null;uniqueIndex;size:64"`
	ExpiresAt time.Time `json:"expires_at" gorm:"not null;index"`
	CreatedAt time.Time `json:"created_at"`
}

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
	YahooSymbol  string    `json:"yahoo_symbol" gorm:"size:64"`
	ISIN         string    `json:"isin" gorm:"size:12;index"`
	SourceFormat string    `json:"source_format" gorm:"index;size:64"` // e.g. ICICIDirect, NSE, Manual
	Ignore       string    `json:"ignore" gorm:"size:1;index"`         // Y/N; empty treated as N
	Notes        string    `json:"notes" gorm:"size:200"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// MFSchemeMapping maps broker scheme names that do not match Global_MutualFunds.scheme_name
// to a catalog ISIN. Empty MappedISIN means the row still needs admin attention.
type MFSchemeMapping struct {
	ID               uint      `json:"id" gorm:"primaryKey"`
	SourceSchemeName string    `json:"source_scheme_name" gorm:"not null;uniqueIndex;size:512"`
	MappedISIN       string    `json:"mapped_isin" gorm:"size:64;index"`
	SourceFormat     string    `json:"source_format" gorm:"index;size:64"`
	Ignore           string    `json:"ignore" gorm:"size:1;index"` // Y/N; empty treated as N
	Notes            string    `json:"notes" gorm:"size:200"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

const (
	SourceFormatICICIDirect = "ICICIDirect"
	SourceFormatNSE         = "NSE"
	SourceFormatManual      = "Manual"
)

// StockDailyClose is one trading-day close for a symbol (including SENSEX).
type StockDailyClose struct {
	ID           uint      `json:"id" gorm:"primaryKey"`
	TradeDate    time.Time `json:"trade_date" gorm:"type:date;not null;uniqueIndex:idx_daily_close_sym_date"`
	Symbol       string    `json:"symbol" gorm:"size:64;not null;uniqueIndex:idx_daily_close_sym_date;index"`
	ClosingPrice float64   `json:"closing_price"`
	IsLatest     bool      `json:"is_latest" gorm:"index"`
	MA7          float64   `json:"ma7"`
	MA20         float64   `json:"ma20"`
	MA50         float64   `json:"ma50"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// StockDailyCloseSync gates Yahoo history fetches to once per calendar day per symbol.
type StockDailyCloseSync struct {
	Symbol               string     `json:"symbol" gorm:"primaryKey;size:64"`
	LastYahooFetchedDate *time.Time `json:"last_yahoo_fetched_date"`
	UpdatedAt            time.Time  `json:"updated_at"`
}

const (
	ImportKindNSE       = "nse"
	ImportKindETF       = "etf"
	ImportKindCloses    = "closes"
	ImportKindBSEBhav   = "bse_bhav"
	ImportKindMFCatalog = "mf_catalog"
	ImportKindMFVar            = "mf_var"
	ImportKindStockReviewEmail = "review_email"

	ImportStatusSuccess = "success"
	ImportStatusFailure = "failure"

	ImportSourceManual = "manual"
	ImportSourceCron   = "cron"
)

// StockDataImportStatus tracks last attempt/success for Admin stock/MF data
// uploads and daily NSE crons.
type StockDataImportStatus struct {
	Kind            string     `json:"kind" gorm:"primaryKey;size:16"`
	LastAttemptAt   *time.Time `json:"last_attempt_at"`
	LastStatus      string     `json:"last_status" gorm:"size:16"`
	LastError       string     `json:"last_error" gorm:"size:1024"`
	LastSuccessAt   *time.Time `json:"last_success_at"`
	LastSource      string     `json:"last_source" gorm:"size:16"`
	LastSummaryJSON string     `json:"last_summary_json" gorm:"type:text"`
	UpdatedAt       time.Time  `json:"updated_at"`
}
