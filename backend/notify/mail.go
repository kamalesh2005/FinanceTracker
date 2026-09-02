package notify

import (
	"crypto/tls"
	"fmt"
	"html"
	"log"
	"net"
	"net/smtp"
	"os"
	"strings"
	"time"
)

// ReviewEmailRow is one stock line in the review email table.
type ReviewEmailRow struct {
	Symbol        string
	Name          string
	Signal        string
	CurrentPrice  float64
	MA7           float64
	MA20          float64
	MA50          float64
	WeekHigh52    float64
	WeekLow52     float64
}

type smtpConfig struct {
	host string
	port string
	user string
	pass string
	from string
}

func loadSMTPConfig() smtpConfig {
	pass := os.Getenv("SMTP_PASS")
	if len(pass) >= 2 {
		if (pass[0] == '\'' && pass[len(pass)-1] == '\'') || (pass[0] == '"' && pass[len(pass)-1] == '"') {
			pass = pass[1 : len(pass)-1]
		}
	}
	return smtpConfig{
		host: strings.TrimSpace(os.Getenv("SMTP_HOST")),
		port: strings.TrimSpace(os.Getenv("SMTP_PORT")),
		user: strings.TrimSpace(os.Getenv("SMTP_USER")),
		pass: pass,
		from: strings.TrimSpace(os.Getenv("SMTP_FROM")),
	}
}

func smtpConfigured(cfg smtpConfig) bool {
	return cfg.host != "" && cfg.port != "" && cfg.from != ""
}

// SendHTMLMail delivers an HTML email via SMTP when configured; otherwise logs to console.
func SendHTMLMail(to, subject, htmlBody string) error {
	cfg := loadSMTPConfig()
	if !smtpConfigured(cfg) {
		log.Printf("[EMAIL DEV] to=%s subject=%q (SMTP not configured)\n%s", to, subject, htmlBody)
		return nil
	}
	if err := sendMailSTARTTLS(cfg.host, cfg.port, cfg.user, cfg.pass, cfg.from, to, subject, htmlBody, "text/html; charset=UTF-8"); err != nil {
		log.Printf("[EMAIL] SMTP failed for %s: %v — logging body to console", to, err)
		log.Printf("[EMAIL DEV] to=%s subject=%q\n%s", to, subject, htmlBody)
		return nil
	}
	log.Printf("[EMAIL] SMTP accepted for %s subject=%q from=%s", to, subject, cfg.from)
	return nil
}

// SendStockReviewEmail sends the weekday stocks-to-review table.
func SendStockReviewEmail(to string, rows []ReviewEmailRow) error {
	if len(rows) == 0 {
		return nil
	}
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		ist = time.FixedZone("IST", 5*60*60+30*60)
	}
	dateLabel := time.Now().In(ist).Format("02 Jan 2006")
	subject := fmt.Sprintf("Stocks to Review — %s", dateLabel)
	body := buildReviewEmailHTML(rows)
	return SendHTMLMail(to, subject, body)
}

func buildReviewEmailHTML(rows []ReviewEmailRow) string {
	var b strings.Builder
	b.WriteString(`<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;font-size:14px;">`)
	b.WriteString(`<h2 style="margin:0 0 12px;">Stocks to Review</h2>`)
	b.WriteString(`<p style="color:#555;margin:0 0 16px;">Holdings with Buy, Sell, or Book Profit signals.</p>`)
	b.WriteString(`<table border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;width:100%;max-width:960px;">`)
	b.WriteString(`<thead><tr style="background:#f5f5f5;">`)
	headers := []string{"Stock", "Signal", "Current", "MA7", "MA20", "MA50", "52W High", "52W Low"}
	for _, h := range headers {
		b.WriteString("<th align=\"left\">")
		b.WriteString(html.EscapeString(h))
		b.WriteString("</th>")
	}
	b.WriteString("</tr></thead><tbody>")
	for _, r := range rows {
		label := r.Symbol
		if strings.TrimSpace(r.Name) != "" && r.Name != r.Symbol {
			label = r.Symbol + " — " + r.Name
		}
		b.WriteString("<tr>")
		cells := []string{
			label,
			r.Signal,
			formatPrice(r.CurrentPrice),
			formatPrice(r.MA7),
			formatPrice(r.MA20),
			formatPrice(r.MA50),
			formatPrice(r.WeekHigh52),
			formatPrice(r.WeekLow52),
		}
		for _, c := range cells {
			b.WriteString("<td>")
			b.WriteString(html.EscapeString(c))
			b.WriteString("</td>")
		}
		b.WriteString("</tr>")
	}
	b.WriteString("</tbody></table>")
	b.WriteString(`<p style="color:#888;margin-top:16px;font-size:12px;">Dhanshanti Finance Tracker</p>`)
	b.WriteString("</body></html>")
	return b.String()
}

func formatPrice(v float64) string {
	if v <= 0 {
		return "—"
	}
	return fmt.Sprintf("%.2f", v)
}

func sendMailSTARTTLS(host, port, user, pass, from, to, subject, body, contentType string) error {
	addr := net.JoinHostPort(host, port)
	fromDomain := from
	if at := strings.LastIndex(from, "@"); at >= 0 && at < len(from)-1 {
		fromDomain = from[at+1:]
	}
	msgID := fmt.Sprintf("<%d.%d@%s>", time.Now().UnixNano(), time.Now().Unix(), fromDomain)
	msg := []byte("To: " + to + "\r\n" +
		"From: " + from + "\r\n" +
		"Date: " + time.Now().UTC().Format(time.RFC1123Z) + "\r\n" +
		"Message-ID: " + msgID + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"MIME-Version: 1.0\r\n" +
		"Content-Type: " + contentType + "\r\n" +
		"\r\n" + body)

	conn, err := net.DialTimeout("tcp", addr, 15*time.Second)
	if err != nil {
		return fmt.Errorf("failed to dial SMTP server: %w", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(20 * time.Second))

	c, err := smtp.NewClient(conn, host)
	if err != nil {
		return fmt.Errorf("failed to create SMTP client: %w", err)
	}
	defer func() { _ = c.Quit() }()

	tlsconfig := &tls.Config{ServerName: host}
	if err = c.StartTLS(tlsconfig); err != nil {
		return fmt.Errorf("failed to establish STARTTLS: %w", err)
	}

	if user != "" {
		auth := smtp.PlainAuth("", user, pass, host)
		if err = c.Auth(auth); err != nil {
			return fmt.Errorf("SMTP authentication failed: %w", err)
		}
	}

	if err = c.Mail(from); err != nil {
		return fmt.Errorf("SMTP mail-from failed: %w", err)
	}
	if err = c.Rcpt(to); err != nil {
		return fmt.Errorf("SMTP rcpt-to failed: %w", err)
	}

	w, err := c.Data()
	if err != nil {
		return fmt.Errorf("SMTP data initialization failed: %w", err)
	}
	if _, err = w.Write(msg); err != nil {
		_ = w.Close()
		return fmt.Errorf("SMTP data write failed: %w", err)
	}
	if err = w.Close(); err != nil {
		return fmt.Errorf("SMTP data close failed: %w", err)
	}
	return nil
}
