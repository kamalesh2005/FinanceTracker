package auth

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const (
	turnstileSiteVerifyURL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"
	// Public Turnstile site key for this project's existing Cloudflare widget.
	TurnstileSiteKeyValue = "0x4AAAAAAEE_unN60Se7PnnB"
)

var turnstileHTTP = &http.Client{Timeout: 10 * time.Second}

// TurnstileSecret returns TURNSTILE_SECRET from the environment.
func TurnstileSecret() string {
	return strings.TrimSpace(os.Getenv("TURNSTILE_SECRET"))
}

// TurnstileSiteKey returns the public site key for the embedded widget.
func TurnstileSiteKey() string {
	return TurnstileSiteKeyValue
}

// TurnstileEnabled is true when TURNSTILE_SECRET is configured.
func TurnstileEnabled() bool {
	return TurnstileSecret() != ""
}

type turnstileVerifyResponse struct {
	Success    bool     `json:"success"`
	ErrorCodes []string `json:"error-codes"`
}

// VerifyTurnstile validates a client token via Cloudflare Siteverify.
// Fails closed on missing secret, missing token, network errors, or success != true.
func VerifyTurnstile(token, remoteIP string) error {
	secret := TurnstileSecret()
	if secret == "" {
		log.Printf("turnstile: TURNSTILE_SECRET is unset; rejecting registration")
		return fmt.Errorf("captcha verification unavailable")
	}

	token = strings.TrimSpace(token)
	if token == "" {
		log.Printf("turnstile: missing token")
		return fmt.Errorf("captcha token required")
	}

	form := url.Values{}
	form.Set("secret", secret)
	form.Set("response", token)
	if ip := strings.TrimSpace(remoteIP); ip != "" {
		form.Set("remoteip", ip)
	}

	resp, err := turnstileHTTP.PostForm(turnstileSiteVerifyURL, form)
	if err != nil {
		log.Printf("turnstile: siteverify request failed: %v", err)
		return fmt.Errorf("captcha verification unavailable")
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Printf("turnstile: siteverify HTTP %d", resp.StatusCode)
		return fmt.Errorf("captcha verification unavailable")
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		log.Printf("turnstile: siteverify read failed: %v", err)
		return fmt.Errorf("captcha verification unavailable")
	}

	var result turnstileVerifyResponse
	if err := json.Unmarshal(body, &result); err != nil {
		log.Printf("turnstile: siteverify decode failed: %v", err)
		return fmt.Errorf("captcha verification unavailable")
	}
	if !result.Success {
		log.Printf("turnstile: siteverify success=false codes=%v", result.ErrorCodes)
		return fmt.Errorf("captcha verification failed")
	}
	return nil
}
