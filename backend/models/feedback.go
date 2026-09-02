package models

import "time"

const (
	FeedbackStatusOpen   = "open"
	FeedbackStatusClosed = "closed"
)

type Feedback struct {
	ID            uint       `json:"id" gorm:"primaryKey"`
	UserID        uint       `json:"user_id" gorm:"not null;index"`
	ScreenName    string     `json:"screen_name" gorm:"size:128;not null;default:'';index"`
	Message       string     `json:"message" gorm:"not null;type:text"`
	Status        string     `json:"status" gorm:"size:16;not null;default:open;index"`
	AdminResponse string     `json:"admin_response" gorm:"type:text"`
	RespondedAt   *time.Time `json:"responded_at"`
	RespondedBy   *uint      `json:"responded_by"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}
