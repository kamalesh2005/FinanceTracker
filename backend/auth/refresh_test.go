package auth

import (
	"testing"
)

func TestNewRefreshToken_Format(t *testing.T) {
	tok, err := NewRefreshToken()
	if err != nil {
		t.Fatal(err)
	}
	if err := ValidateRefreshTokenFormat(tok); err != nil {
		t.Fatalf("expected valid token: %v", err)
	}
}

func TestHashRefreshToken_Deterministic(t *testing.T) {
	a := HashRefreshToken("abc")
	b := HashRefreshToken("abc")
	if a != b || len(a) != 64 {
		t.Fatalf("hash=%q len=%d", a, len(a))
	}
}

func TestValidateRefreshTokenFormat(t *testing.T) {
	if err := ValidateRefreshTokenFormat(""); err == nil {
		t.Fatal("expected error for empty token")
	}
	if err := ValidateRefreshTokenFormat("not-hex"); err == nil {
		t.Fatal("expected error for short token")
	}
}
