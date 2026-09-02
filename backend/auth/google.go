package auth

import (
	"context"
	"fmt"
	"os"
	"strings"

	"google.golang.org/api/idtoken"
)

// GoogleIdentity is the verified Google account used to find or create a user.
type GoogleIdentity struct {
	Sub   string
	Email string
}

// GoogleTokenVerifier checks a Google ID token. Tests inject a fake.
type GoogleTokenVerifier interface {
	VerifyIDToken(ctx context.Context, idToken string) (GoogleIdentity, error)
}

// GoogleClientID returns GOOGLE_CLIENT_ID from the environment.
func GoogleClientID() string {
	return strings.TrimSpace(os.Getenv("GOOGLE_CLIENT_ID"))
}

// GoogleEnabled is true when a Google OAuth web client ID is configured.
func GoogleEnabled() bool {
	return GoogleClientID() != ""
}

type googleIDTokenVerifier struct{}

// DefaultGoogleVerifier validates ID tokens against GOOGLE_CLIENT_ID.
func DefaultGoogleVerifier() GoogleTokenVerifier {
	return googleIDTokenVerifier{}
}

func (googleIDTokenVerifier) VerifyIDToken(ctx context.Context, raw string) (GoogleIdentity, error) {
	clientID := GoogleClientID()
	if clientID == "" {
		return GoogleIdentity{}, fmt.Errorf("google sign-in is not configured")
	}
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return GoogleIdentity{}, fmt.Errorf("id token is required")
	}

	payload, err := idtoken.Validate(ctx, raw, clientID)
	if err != nil {
		return GoogleIdentity{}, fmt.Errorf("invalid google token")
	}

	email, _ := payload.Claims["email"].(string)
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return GoogleIdentity{}, fmt.Errorf("google account has no email")
	}
	if !claimBool(payload.Claims["email_verified"]) {
		return GoogleIdentity{}, fmt.Errorf("google email is not verified")
	}
	sub := strings.TrimSpace(payload.Subject)
	if sub == "" {
		return GoogleIdentity{}, fmt.Errorf("google account has no subject")
	}
	return GoogleIdentity{Sub: sub, Email: email}, nil
}

func claimBool(v any) bool {
	switch t := v.(type) {
	case bool:
		return t
	case string:
		return strings.EqualFold(t, "true")
	default:
		return false
	}
}
