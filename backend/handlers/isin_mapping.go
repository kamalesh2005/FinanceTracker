package handlers

import (
	"financetracker/models"
	"log"
	"regexp"
	"strings"

	"gorm.io/gorm"
)

// Indian ISINs are 12 chars: IN + 9 alphanumerics + check digit (INE equity, INF funds, etc.).
var indianISINPattern = regexp.MustCompile(`^IN[A-Z0-9]{9}[0-9]$`)
var indianISINExtract = regexp.MustCompile(`IN[A-Z0-9]{9}[0-9]`)

func normalizeISIN(s string) string {
	s = strings.ToUpper(strings.TrimSpace(s))
	s = strings.ReplaceAll(s, " ", "")
	s = strings.ReplaceAll(s, "-", "")
	s = strings.Trim(s, "'\"")
	if indianISINPattern.MatchString(s) {
		return s
	}
	if m := indianISINExtract.FindString(s); m != "" {
		return m
	}
	return ""
}

// EnsureSymbolMappingFromISIN creates SymbolMapping when ISIN resolves to a validated NSE ticker.
// Existing mappings are not overwritten; ISIN is only backfilled when empty.
func EnsureSymbolMappingFromISIN(db *gorm.DB, sourceSymbol, isin, sourceFormat string) (created bool, err error) {
	sourceSymbol = strings.ToUpper(strings.TrimSpace(sourceSymbol))
	isin = normalizeISIN(isin)
	if sourceSymbol == "" || isin == "" {
		return false, nil
	}
	if sourceFormat == "" {
		sourceFormat = models.SourceFormatICICIDirect
	}

	var existing models.SymbolMapping
	findErr := db.Where("UPPER(source_symbol) = ?", sourceSymbol).First(&existing).Error
	if findErr == nil {
		if existing.ISIN == "" && isin != "" {
			if err := db.Model(&existing).Update("isin", isin).Error; err != nil {
				return false, err
			}
		}
		return false, nil
	}
	if findErr != gorm.ErrRecordNotFound {
		return false, findErr
	}

	nseSymbol, via, err := resolveNSESymbolFromISIN(isin)
	if err != nil {
		log.Printf("ISIN auto-map skipped for %s (%s): %v", sourceSymbol, isin, err)
		return false, nil
	}

	mapping := models.SymbolMapping{
		SourceSymbol: sourceSymbol,
		YahooSymbol:  nseSymbol,
		ISIN:         isin,
		SourceFormat: sourceFormat,
		Notes:        "auto-mapped from ISIN via " + via,
	}
	if err := db.Create(&mapping).Error; err != nil {
		return false, err
	}
	setSymbolCacheEntry(sourceSymbol, nseSymbol)
	if err := ReloadSymbolCache(db); err != nil {
		return true, err
	}
	log.Printf("ISIN auto-map: %s → %s (ISIN %s, %s)", sourceSymbol, nseSymbol, isin, via)
	return true, nil
}

// EnsureSymbolMappingFromName creates SymbolMapping when Yahoo name search returns exactly one India quote.
// Existing mappings are not overwritten.
func EnsureSymbolMappingFromName(db *gorm.DB, sourceSymbol, name, isin, sourceFormat string) (created bool, err error) {
	sourceSymbol = strings.ToUpper(strings.TrimSpace(sourceSymbol))
	name = strings.TrimSpace(name)
	isin = normalizeISIN(isin)
	if sourceSymbol == "" || name == "" {
		return false, nil
	}
	if sourceFormat == "" {
		sourceFormat = models.SourceFormatManual
	}

	var existing models.SymbolMapping
	findErr := db.Where("UPPER(source_symbol) = ?", sourceSymbol).First(&existing).Error
	if findErr == nil {
		return false, nil
	}
	if findErr != gorm.ErrRecordNotFound {
		return false, findErr
	}

	nseSymbol, err := yahooSearchUniqueNSESymbolByName(name)
	if err != nil {
		log.Printf("name auto-map skipped for %s (%q): %v", sourceSymbol, name, err)
		return false, nil
	}

	mapping := models.SymbolMapping{
		SourceSymbol: sourceSymbol,
		YahooSymbol:  nseSymbol,
		ISIN:         isin,
		SourceFormat: sourceFormat,
		Notes:        "auto-mapped from name",
	}
	if err := db.Create(&mapping).Error; err != nil {
		return false, err
	}
	setSymbolCacheEntry(sourceSymbol, nseSymbol)
	if err := ReloadSymbolCache(db); err != nil {
		return true, err
	}
	log.Printf("name auto-map: %s → %s (name %q)", sourceSymbol, nseSymbol, name)
	return true, nil
}
