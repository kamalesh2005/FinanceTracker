package notify

import (
	"fmt"
	"log"
	"net/http"
	"net/smtp"
	"net/url"
	"os"
	"strings"
	"time"
)

// SendEmailOTP delivers a password-reset code by SMTP when configured; otherwise logs to console.
func SendEmailOTP(to, code string) error {
	host := os.Getenv("SMTP_HOST")
	port := os.Getenv("SMTP_PORT")
	user := os.Getenv("SMTP_USER")
	pass := os.Getenv("SMTP_PASS")
	from := os.Getenv("SMTP_FROM")
	if from == "" {
		from = user
	}

	if host == "" || port == "" || from == "" {
		log.Printf("[OTP DEV] email to=%s code=%s (SMTP not configured)", to, code)
		return nil
	}

	addr := host + ":" + port
	subject := "Finance Tracker password reset code"
	body := fmt.Sprintf("Your password reset code is %s. It expires in 10 minutes.\r\n", code)
	msg := []byte("To: " + to + "\r\n" +
		"From: " + from + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"MIME-Version: 1.0\r\n" +
		"Content-Type: text/plain; charset=UTF-8\r\n" +
		"\r\n" + body)

	var auth smtp.Auth
	if user != "" {
		auth = smtp.PlainAuth("", user, pass, host)
	}
	if err := smtp.SendMail(addr, auth, from, []string{to}, msg); err != nil {
		log.Printf("[OTP] SMTP failed for %s: %v — logging code to console", to, err)
		log.Printf("[OTP DEV] email to=%s code=%s", to, code)
		return nil
	}
	return nil
}

// SendSMSOTP delivers a password-reset code via Twilio when configured; otherwise logs to console.
func SendSMSOTP(to, code string) error {
	sid := os.Getenv("TWILIO_ACCOUNT_SID")
	token := os.Getenv("TWILIO_AUTH_TOKEN")
	from := os.Getenv("TWILIO_FROM_NUMBER")

	if sid == "" || token == "" || from == "" {
		log.Printf("[OTP DEV] sms to=%s code=%s (Twilio not configured)", to, code)
		return nil
	}

	endpoint := fmt.Sprintf("https://api.twilio.com/2010-04-01/Accounts/%s/Messages.json", sid)
	form := url.Values{}
	form.Set("To", to)
	form.Set("From", from)
	form.Set("Body", fmt.Sprintf("Your Finance Tracker password reset code is %s. It expires in 10 minutes.", code))

	req, err := http.NewRequest(http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		log.Printf("[OTP DEV] sms to=%s code=%s (request build failed: %v)", to, code, err)
		return nil
	}
	req.SetBasicAuth(sid, token)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		log.Printf("[OTP] Twilio failed for %s: %v — logging code to console", to, err)
		log.Printf("[OTP DEV] sms to=%s code=%s", to, code)
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Printf("[OTP] Twilio status %d for %s — logging code to console", resp.StatusCode, to)
		log.Printf("[OTP DEV] sms to=%s code=%s", to, code)
		return nil
	}
	return nil
}
