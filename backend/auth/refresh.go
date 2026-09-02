package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

const defaultRefreshTokenTTL = 30 * 24 * time.Hour

// RefreshTokenTTL returns how long opaque refresh tokens remain valid.
func RefreshTokenTTL() time.Duration {
	raw := os.Getenv("REFRESH_TOKEN_TTL_DAYS")
	if raw == "" {
		return defaultRefreshTokenTTL
	}
	days, err := strconv.Atoi(raw)
	if err != nil || days < 1 {
		return defaultRefreshTokenTTL
	}
	return time.Duration(days) * 24 * time.Hour
}

// NewRefreshToken returns a cryptographically random opaque token (hex-encoded).
func NewRefreshToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// HashRefreshToken returns a stable SHA-256 hex digest for DB storage.
func HashRefreshToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func trimToken(token string) string {
	return strings.TrimSpace(token)
}

// ValidateRefreshTokenFormat rejects empty or malformed opaque tokens.
func ValidateRefreshTokenFormat(token string) error {
	token = trimToken(token)
	if len(token) != 64 {
		return fmt.Errorf("invalid refresh token")
	}
	if _, err := hex.DecodeString(token); err != nil {
		return fmt.Errorf("invalid refresh token")
	}
	return nil
}
