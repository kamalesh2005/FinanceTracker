package models

import "time"

const (
	InvChMemberPending = "pending"
	InvChMemberActive  = "active"

	InvChTransactionFee = 20.0
)

// InvChChallenge is a paper-trading investment challenge.
// InitialNetworth is a per-member starting cash template, not a shared pool.
type InvChChallenge struct {
	ID              uint      `json:"id" gorm:"primaryKey"`
	CreatorUserID   uint      `json:"creator_user_id" gorm:"not null;index"`
	Name            string    `json:"name" gorm:"not null;size:128"`
	InitialNetworth float64   `json:"initial_networth" gorm:"not null"`
	DurationDays    int       `json:"duration_days" gorm:"not null"`
	StartsAt        time.Time `json:"starts_at" gorm:"not null"`
	EndsAt          time.Time `json:"ends_at" gorm:"not null;index"`
	InviteCode      string    `json:"invite_code" gorm:"not null;uniqueIndex;size:16"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// InvChMember is one roster slot. Each active member owns an independent cash_balance.
type InvChMember struct {
	ID            uint       `json:"id" gorm:"primaryKey"`
	ChallengeID   uint       `json:"challenge_id" gorm:"not null;uniqueIndex:idx_inv_ch_member_user;index"`
	UserID        *uint      `json:"user_id,omitempty" gorm:"uniqueIndex:idx_inv_ch_member_user;index"`
	Status        string     `json:"status" gorm:"not null;size:16;index"`
	DisplayName   string     `json:"display_name" gorm:"size:128"`
	InvitedEmail  string     `json:"invited_email,omitempty" gorm:"size:255"`
	InvitedMobile string     `json:"invited_mobile,omitempty" gorm:"size:32"`
	CashBalance   float64    `json:"cash_balance" gorm:"not null;default:0"`
	JoinedAt      *time.Time `json:"joined_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

// InvChHolding is a paper position for one member in one challenge (no broker source).
type InvChHolding struct {
	ID                    uint       `json:"id" gorm:"primaryKey"`
	ChallengeID           uint       `json:"challenge_id" gorm:"not null;uniqueIndex:idx_inv_ch_holding;index"`
	UserID                uint       `json:"user_id" gorm:"not null;uniqueIndex:idx_inv_ch_holding;index"`
	StockID               uint       `json:"stock_id" gorm:"not null;uniqueIndex:idx_inv_ch_holding;index"`
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
	BSHClearDate          *time.Time `json:"bsh_clear_date"`
	Notes                 string     `json:"notes" gorm:"size:200"`
	CreatedAt             time.Time  `json:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
	Stock                 Stock      `json:"stock,omitempty" gorm:"foreignKey:StockID"`
}

// InvChTransaction is the FIFO paper-trading ledger for a challenge member.
type InvChTransaction struct {
	ID               uint            `json:"id" gorm:"primaryKey"`
	ChallengeID      uint            `json:"challenge_id" gorm:"not null;index"`
	UserID           uint            `json:"user_id" gorm:"not null;index"`
	StockID          uint            `json:"stock_id" gorm:"not null;index"`
	Type             TransactionType `json:"type" gorm:"not null;size:16"`
	Quantity         float64         `json:"quantity" gorm:"not null"`
	OriginalQuantity float64         `json:"original_quantity" gorm:"not null;default:0"`
	Price            float64         `json:"price" gorm:"not null"`
	Fee              float64         `json:"fee" gorm:"not null;default:0"`
	CashDelta        float64         `json:"cash_delta" gorm:"not null;default:0"`
	SalePrice        float64         `json:"sale_price" gorm:"not null;default:0"`
	SaleDate         *time.Time      `json:"sale_date"`
	TransactionDate  time.Time       `json:"transaction_date" gorm:"not null"`
	CreatedAt        time.Time       `json:"created_at"`
	Stock            Stock           `json:"stock,omitempty" gorm:"foreignKey:StockID"`
}
