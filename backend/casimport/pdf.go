package casimport

import (
	"bytes"
	"errors"
	"io"
	"strings"

	"github.com/ledongthuc/pdf"
)

// ExtractText decrypts a PDF with the given open password and returns plain text.
// The password is used only for decryption and is not retained.
func ExtractText(pdfBytes []byte, password string) (string, error) {
	password = strings.TrimSpace(password)
	if len(pdfBytes) == 0 {
		return "", errors.New("empty PDF")
	}
	if password == "" {
		return "", ErrInvalidPassword
	}

	ra := bytes.NewReader(pdfBytes)
	triedEmpty := false
	r, err := pdf.NewReaderEncrypted(ra, int64(len(pdfBytes)), func() string {
		if !triedEmpty {
			// First callback may be an empty probe on some files; always return user pw.
			triedEmpty = true
		}
		return password
	})
	if err != nil {
		if errors.Is(err, pdf.ErrInvalidPassword) ||
			strings.Contains(strings.ToLower(err.Error()), "password") {
			return "", ErrInvalidPassword
		}
		return "", err
	}

	plain, err := r.GetPlainText()
	if err != nil {
		return "", err
	}
	var buf bytes.Buffer
	if _, err := io.Copy(&buf, plain); err != nil {
		return "", err
	}
	text := buf.String()
	if strings.TrimSpace(text) == "" {
		// Fallback: page-by-page extraction.
		var b strings.Builder
		for i := 1; i <= r.NumPage(); i++ {
			p := r.Page(i)
			if p.V.IsNull() {
				continue
			}
			content, err := p.GetPlainText(nil)
			if err != nil {
				continue
			}
			b.WriteString(content)
			b.WriteByte('\n')
		}
		text = b.String()
	}
	if strings.TrimSpace(text) == "" {
		return "", errors.New("could not extract text from PDF")
	}
	return text, nil
}

// ParsePDF decrypts and parses an NSDL e-CAS PDF.
func ParsePDF(pdfBytes []byte, password string) (Result, error) {
	text, err := ExtractText(pdfBytes, password)
	if err != nil {
		return Result{}, err
	}
	return ParseNSDLText(text)
}
