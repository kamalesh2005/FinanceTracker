package auth

import (
	"context"
	"testing"
)

func TestGoogleEnabled(t *testing.T) {
	t.Setenv("GOOGLE_CLIENT_ID", "")
	if GoogleEnabled() {
		t.Fatal("expected disabled when client id is empty")
	}
	if GoogleClientID() != "" {
		t.Fatalf("got %q", GoogleClientID())
	}

	t.Setenv("GOOGLE_CLIENT_ID", "  web-client.apps.googleusercontent.com  ")
	if !GoogleEnabled() {
		t.Fatal("expected enabled")
	}
	if got := GoogleClientID(); got != "web-client.apps.googleusercontent.com" {
		t.Fatalf("got %q", got)
	}
}

func TestDefaultVerifierRequiresConfigAndToken(t *testing.T) {
	t.Setenv("GOOGLE_CLIENT_ID", "")
	v := DefaultGoogleVerifier()
	if _, err := v.VerifyIDToken(context.Background(), "tok"); err == nil {
		t.Fatal("expected error when unconfigured")
	}

	t.Setenv("GOOGLE_CLIENT_ID", "web-client.apps.googleusercontent.com")
	if _, err := v.VerifyIDToken(context.Background(), "   "); err == nil {
		t.Fatal("expected error for empty token")
	}
}
