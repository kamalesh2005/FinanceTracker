package handlers

import (
	"errors"
	"io"
	"net/http"
	"strings"

	"financetracker/casimport"
	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// ImportCAS accepts a password-protected NSDL e-CAS PDF and replaces stock/MF
// holdings per demat account (broker-named sources) and SOA MF folios.
// The password (PAN) is used only to decrypt in memory and is never stored.
func (h *Handler) ImportCAS(c *gin.Context) {
	password := strings.TrimSpace(c.PostForm("password"))
	if password == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "password is required (PAN in capital letters)"})
		return
	}

	fileHeader, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "PDF file is required"})
		return
	}
	if fileHeader.Size > 25<<20 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "PDF too large (max 25MB)"})
		return
	}
	f, err := fileHeader.Open()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not read uploaded file"})
		return
	}
	defer f.Close()

	pdfBytes, err := io.ReadAll(io.LimitReader(f, 25<<20+1))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not read uploaded file"})
		return
	}
	if len(pdfBytes) > 25<<20 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "PDF too large (max 25MB)"})
		return
	}

	parsed, err := casimport.ParsePDF(pdfBytes, password)
	// Drop references promptly; do not log password or PDF contents.
	pdfBytes = nil
	password = ""
	if err != nil {
		if errors.Is(err, casimport.ErrInvalidPassword) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid CAS password"})
			return
		}
		if errors.Is(err, casimport.ErrNotCAS) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "file does not look like an NSDL e-CAS"})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not parse CAS PDF"})
		return
	}

	userID := middleware.CurrentUserID(c)
	watchList := h.userUsesWatchList(userID)

	catalog, err := buildMFSchemeCatalogIndex(h.DB)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}

	type sourceSummary struct {
		Source       string `json:"source"`
		Stocks       int    `json:"stocks"`
		MutualFunds  int    `json:"mutual_funds"`
		StocksZeroed int    `json:"stocks_zeroed"`
		MFsZeroed    int    `json:"mfs_zeroed"`
	}
	summaries := make([]sourceSummary, 0, len(parsed.Accounts))
	warnings := make([]gin.H, 0)
	totalStocks := 0
	totalMFs := 0

	for _, acct := range parsed.Accounts {
		source := strings.TrimSpace(acct.Source)
		if source == "" || !models.IsReplaceableImportSource(source) {
			continue
		}
		sum := sourceSummary{Source: source}

		if source != models.SourceNSDLMFFolios && len(acct.Equities) > 0 {
			n, z, warns, err := h.applyCASEquities(tx, userID, source, acct.Equities, watchList)
			if err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			sum.Stocks = n
			sum.StocksZeroed = z
			totalStocks += n
			warnings = append(warnings, warns...)
		}

		if len(acct.MutualFunds) > 0 {
			n, z, warns, err := h.applyCASMutualFunds(tx, userID, source, acct.MutualFunds, watchList, catalog)
			if err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			sum.MutualFunds = n
			sum.MFsZeroed = z
			totalMFs += n
			warnings = append(warnings, warns...)
		}

		if sum.Stocks > 0 || sum.MutualFunds > 0 || sum.StocksZeroed > 0 || sum.MFsZeroed > 0 {
			summaries = append(summaries, sum)
		}
	}

	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"sources":      summaries,
		"stocks":       totalStocks,
		"mutual_funds": totalMFs,
		"warnings":     warnings,
		"message":      "CAS import applied to stocks and mutual funds",
	})
}

func (h *Handler) applyCASEquities(
	tx *gorm.DB,
	userID uint,
	source string,
	rows []casimport.EquityHolding,
	watchList bool,
) (applied, zeroed int, warnings []gin.H, err error) {
	touched := map[uint]struct{}{}

	for _, row := range rows {
		symbol := strings.TrimSpace(row.Symbol)
		if symbol == "" || row.Quantity <= 0 {
			continue
		}
		stock, ferr := h.findOrCreateStock(symbol, row.Name, row.ISIN)
		if ferr != nil {
			return 0, 0, nil, ferr
		}
		if needsYahooAnyData(&stock) && strings.TrimSpace(row.ISIN) != "" {
			if _, merr := EnsureSymbolMappingFromISIN(tx, symbol, row.ISIN, source); merr != nil {
				return 0, 0, nil, merr
			}
			h.applyYahooDataToStock(symbol, &stock)
			h.persistYahooStockFields(&stock)
		}

		avg := 0.0
		var existing models.UserStock
		if tx.Where("user_id = ? AND stock_id = ? AND source = ?", userID, stock.ID, source).
			First(&existing).Error == nil && existing.AvgBuyPrice > 0 {
			avg = existing.AvgBuyPrice
		}

		qty := row.Quantity
		if watchList && qty > 0 {
			qty = 1
		}
		currentPrice := stock.CurrentPrice
		if currentPrice <= 0 {
			currentPrice = yahooPriceForUpload(stock.Symbol)
		}
		pos, _, aerr := applyUploadPosition(tx, userID, stock.ID, stock.Symbol, source, qty, avg, nil, watchList, currentPrice)
		if aerr != nil {
			return 0, 0, nil, aerr
		}
		if pos.ID != 0 {
			touched[stock.ID] = struct{}{}
			applied++
		}
	}

	var stale []models.UserStock
	if err := tx.Where("user_id = ? AND source = ? AND quantity > 0", userID, source).Find(&stale).Error; err != nil {
		return 0, 0, nil, err
	}
	for _, t := range stale {
		if _, ok := touched[t.StockID]; ok {
			continue
		}
		var catalog models.Stock
		symbol := ""
		if tx.First(&catalog, t.StockID).Error == nil {
			symbol = catalog.Symbol
		}
		if _, _, zerr := applyUploadPosition(tx, userID, t.StockID, symbol, source, 0, t.AvgBuyPrice, nil, false, 0); zerr != nil {
			return 0, 0, nil, zerr
		}
		zeroed++
	}
	return applied, zeroed, warnings, nil
}

func (h *Handler) applyCASMutualFunds(
	tx *gorm.DB,
	userID uint,
	source string,
	rows []casimport.MFHolding,
	watchList bool,
	catalog *mfSchemeCatalogIndex,
) (applied, zeroed int, warnings []gin.H, err error) {
	touchedISIN := map[string]struct{}{}
	touchedSource := map[string]struct{}{}

	for _, row := range rows {
		if row.Units <= 0 {
			continue
		}
		sourceName := strings.TrimSpace(row.Name)
		g, rerr := catalog.resolveImport(sourceName, row.ISIN)
		if rerr != nil {
			if rerr == gorm.ErrRecordNotFound {
				if sourceName == "" {
					warnings = append(warnings, gin.H{
						"scheme_name": row.Name,
						"isin":        row.ISIN,
						"reason":      "scheme_name is required when not in catalog",
					})
					continue
				}
				if _, uerr := upsertUnmappedMFScheme(tx, sourceName, source); uerr != nil {
					return 0, 0, nil, uerr
				}
				avg := row.AvgCost
				var existing models.MutualFund
				if findUserMutualFund(tx, userID, source, "", sourceName, &existing) == nil && avg <= 0 && existing.NAV > 0 {
					avg = existing.NAV
				}
				qty := row.Units
				if watchList && qty > 0 {
					qty = 1
				}
				pos, _, aerr := applyUploadMFPosition(
					tx, userID, "", "", "", sourceName, source,
					qty, avg, row.CurrentNAV, nil,
				)
				if aerr != nil {
					return 0, 0, nil, aerr
				}
				if pos.ID != 0 {
					touchedSource[strings.ToLower(sourceName)] = struct{}{}
					applied++
				}
				warnings = append(warnings, gin.H{
					"scheme_name": sourceName,
					"isin":        row.ISIN,
					"reason":      "pending catalog link",
				})
				continue
			}
			return 0, 0, nil, rerr
		}

		isin := strings.ToUpper(strings.TrimSpace(g.ISIN))
		avg := row.AvgCost
		var existing models.MutualFund
		if findUserMutualFund(tx, userID, source, isin, sourceName, &existing) == nil && avg <= 0 && existing.NAV > 0 {
			avg = existing.NAV
		}
		qty := row.Units
		if watchList && qty > 0 {
			qty = 1
		}
		currentNAV := g.CurrentNAV
		if currentNAV <= 0 {
			currentNAV = row.CurrentNAV
		}
		pos, _, aerr := applyUploadMFPosition(
			tx, userID,
			g.ISIN, g.Symbol, g.SchemeName, sourceName, source,
			qty, avg, currentNAV, nil,
		)
		if aerr != nil {
			return 0, 0, nil, aerr
		}
		if pos.ID != 0 {
			touchedISIN[isin] = struct{}{}
			applied++
		}
	}

	var stale []models.MutualFund
	if err := tx.Where("user_id = ? AND source = ? AND quantity > 0", userID, source).Find(&stale).Error; err != nil {
		return 0, 0, nil, err
	}
	for _, row := range stale {
		isin := strings.ToUpper(strings.TrimSpace(row.ISIN))
		if isin != "" {
			if _, ok := touchedISIN[isin]; ok {
				continue
			}
		} else {
			srcKey := strings.ToLower(strings.TrimSpace(row.SourceSchemeName))
			if _, ok := touchedSource[srcKey]; ok {
				continue
			}
		}
		if _, _, zerr := applyUploadMFPosition(
			tx, userID,
			row.ISIN, row.SchemeCode, row.SchemeName, row.SourceSchemeName, source,
			0, row.NAV, row.CurrentNAV, nil,
		); zerr != nil {
			return 0, 0, nil, zerr
		}
		zeroed++
	}
	return applied, zeroed, warnings, nil
}
