package handlers

import (
	"io"
	"log"
	"net/http"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"financetracker/mfimport"
	"financetracker/middleware"
	"financetracker/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// Longer IDCW phrases first so the more specific form wins.
var idcwPhraseReplacements = []string{
	"income distribution cum capital withdrawal option (idcw)",
	"income distribution cum capital withdrawal (idcw)",
	"income distribution cum capital withdrawal option",
	"income distribution cum capital withdrawal",
}

var nonAlnumRun = regexp.MustCompile(`[^a-z0-9]+`)

// GetAllMutualFundsAdmin returns a paginated Global_MutualFunds page for admins.
// Query: q, page (1-based), page_size (default 50, max 100).
func (h *Handler) GetAllMutualFundsAdmin(c *gin.Context) {
	page := 1
	if raw := strings.TrimSpace(c.Query("page")); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			page = n
		}
	}
	pageSize := 50
	if raw := strings.TrimSpace(c.Query("page_size")); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			pageSize = n
		}
	}
	if pageSize > 100 {
		pageSize = 100
	}

	q := h.DB.Model(&models.GlobalMutualFund{})
	if search := strings.TrimSpace(c.Query("q")); search != "" {
		like := "%" + search + "%"
		q = q.Where("isin ILIKE ? OR symbol ILIKE ? OR scheme_name ILIKE ?", like, like, like)
	}

	var total int64
	if err := q.Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var items []models.GlobalMutualFund
	offset := (page - 1) * pageSize
	if err := q.Order("scheme_name ASC").Offset(offset).Limit(pageSize).Find(&items).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"items":     items,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// ImportMutualFundsAdmin upserts Global_MutualFunds from catalog xlsx/csv or MF_VAR NAV csv.
func (h *Handler) ImportMutualFundsAdmin(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "file is required (multipart field name: file)"})
		return
	}
	f, err := file.Open()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not open uploaded file"})
		return
	}
	defer f.Close()

	data, err := io.ReadAll(f)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not read uploaded file"})
		return
	}

	filename := file.Filename
	if filename == "" {
		filename = "upload.csv"
	}
	_ = filepath.Ext(filename)

	result, err := mfimport.ImportBytes(h.DB, data, filename)
	kind := models.ImportKindMFCatalog
	switch {
	case result.Kind == "nav":
		kind = models.ImportKindMFVar
	case strings.Contains(strings.ToUpper(filename), "MF_VAR"):
		kind = models.ImportKindMFVar
	}
	summary := &ImportSummary{
		Created: result.Created,
		Updated: result.Updated,
		Skipped: result.Skipped,
		Errors:  result.Errors,
	}
	if err != nil {
		_ = RecordImportStatus(h.DB, kind, models.ImportSourceManual, err, summary)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	_ = RecordImportStatus(h.DB, kind, models.ImportSourceManual, nil, summary)
	c.JSON(http.StatusOK, result)
}

// LookupMutualFundByISIN returns a Global_MutualFunds row by ISIN.
func (h *Handler) LookupMutualFundByISIN(c *gin.Context) {
	isin := strings.ToUpper(strings.TrimSpace(c.Query("isin")))
	if isin == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "isin is required"})
		return
	}
	var mf models.GlobalMutualFund
	if err := h.DB.Where("UPPER(isin) = ?", isin).First(&mf).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "mutual fund not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"isin":        mf.ISIN,
		"symbol":      mf.Symbol,
		"scheme_name": mf.SchemeName,
		"current_nav": mf.CurrentNAV,
	})
}

// SearchMutualFunds returns Global_MutualFunds matches for Manual Add autocomplete.
func (h *Handler) SearchMutualFunds(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	if len(q) < 1 {
		c.JSON(http.StatusOK, []gin.H{})
		return
	}
	limit := 20
	if raw := strings.TrimSpace(c.Query("limit")); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 && n <= 50 {
			limit = n
		}
	}

	like := "%" + q + "%"
	var funds []models.GlobalMutualFund
	err := h.DB.
		Where("scheme_name ILIKE ? OR symbol ILIKE ? OR isin ILIKE ?", like, like, like).
		Order("scheme_name ASC").
		Limit(limit).
		Find(&funds).Error
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	out := make([]gin.H, 0, len(funds))
	for _, f := range funds {
		out = append(out, gin.H{
			"isin":        f.ISIN,
			"symbol":      f.Symbol,
			"scheme_name": f.SchemeName,
			"current_nav": f.CurrentNAV,
		})
	}
	c.JSON(http.StatusOK, out)
}

func findGlobalMutualFundByISIN(db *gorm.DB, isin string) (*models.GlobalMutualFund, error) {
	isin = strings.ToUpper(strings.TrimSpace(isin))
	if isin == "" {
		return nil, gorm.ErrRecordNotFound
	}
	var mf models.GlobalMutualFund
	if err := db.Where("UPPER(isin) = ?", isin).First(&mf).Error; err != nil {
		return nil, err
	}
	return &mf, nil
}

// normalizeSchemeName collapses broker/catalog naming differences for matching:
// IDCW long forms → "idcw", punctuation/hyphens → spaces, case/whitespace normalized.
func normalizeSchemeName(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" {
		return ""
	}
	for _, phrase := range idcwPhraseReplacements {
		s = strings.ReplaceAll(s, phrase, "idcw")
	}
	s = nonAlnumRun.ReplaceAllString(s, " ")
	return strings.Join(strings.Fields(s), " ")
}

// mfSchemeCatalogIndex maps normalizeSchemeName(scheme_name) → catalog row.
type mfSchemeCatalogIndex struct {
	byNorm    map[string]*models.GlobalMutualFund
	byISIN    map[string]*models.GlobalMutualFund
	byMapNorm map[string]*models.GlobalMutualFund // broker source name → catalog via mapping
	byMapRaw  map[string]*models.GlobalMutualFund // lower(trim) source name → catalog
	rows      []models.GlobalMutualFund
}

func buildMFSchemeCatalogIndex(db *gorm.DB) (*mfSchemeCatalogIndex, error) {
	var rows []models.GlobalMutualFund
	if err := db.Select("id, isin, symbol, scheme_name, current_nav").Find(&rows).Error; err != nil {
		return nil, err
	}
	idx := &mfSchemeCatalogIndex{
		byNorm:    make(map[string]*models.GlobalMutualFund, len(rows)),
		byISIN:    make(map[string]*models.GlobalMutualFund, len(rows)),
		byMapNorm: make(map[string]*models.GlobalMutualFund),
		byMapRaw:  make(map[string]*models.GlobalMutualFund),
		rows:      rows,
	}
	for i := range rows {
		row := &idx.rows[i]
		isin := strings.ToUpper(strings.TrimSpace(row.ISIN))
		if isin != "" {
			if _, ok := idx.byISIN[isin]; !ok {
				idx.byISIN[isin] = row
			}
		}
		norm := normalizeSchemeName(row.SchemeName)
		if norm == "" {
			continue
		}
		if existing, ok := idx.byNorm[norm]; ok {
			log.Printf(
				"mf scheme norm collision: %q and %q both normalize to %q; keeping first",
				existing.SchemeName, row.SchemeName, norm,
			)
			continue
		}
		idx.byNorm[norm] = row
	}

	var mappings []models.MFSchemeMapping
	if err := db.Where("mapped_isin IS NOT NULL AND TRIM(mapped_isin) <> ''").Find(&mappings).Error; err != nil {
		return nil, err
	}
	for _, m := range mappings {
		isin := strings.ToUpper(strings.TrimSpace(m.MappedISIN))
		g, ok := idx.byISIN[isin]
		if !ok {
			continue
		}
		raw := strings.ToLower(strings.TrimSpace(m.SourceSchemeName))
		if raw != "" {
			idx.byMapRaw[raw] = g
		}
		norm := normalizeSchemeName(m.SourceSchemeName)
		if norm != "" {
			idx.byMapNorm[norm] = g
		}
	}
	return idx, nil
}

func (idx *mfSchemeCatalogIndex) findBySchemeName(name string) (*models.GlobalMutualFund, error) {
	norm := normalizeSchemeName(name)
	if norm == "" {
		return nil, gorm.ErrRecordNotFound
	}
	if g, ok := idx.byNorm[norm]; ok {
		return g, nil
	}
	// Prefer an exact case-insensitive raw-name hit among collisions / near misses.
	want := strings.ToLower(strings.TrimSpace(name))
	for i := range idx.rows {
		if strings.ToLower(strings.TrimSpace(idx.rows[i].SchemeName)) == want {
			return &idx.rows[i], nil
		}
	}
	return nil, gorm.ErrRecordNotFound
}

func (idx *mfSchemeCatalogIndex) findByMappedSchemeName(name string) (*models.GlobalMutualFund, error) {
	raw := strings.ToLower(strings.TrimSpace(name))
	if raw != "" {
		if g, ok := idx.byMapRaw[raw]; ok {
			return g, nil
		}
	}
	norm := normalizeSchemeName(name)
	if norm != "" {
		if g, ok := idx.byMapNorm[norm]; ok {
			return g, nil
		}
	}
	return nil, gorm.ErrRecordNotFound
}

func (idx *mfSchemeCatalogIndex) findByISIN(isin string) (*models.GlobalMutualFund, error) {
	isin = strings.ToUpper(strings.TrimSpace(isin))
	if isin == "" {
		return nil, gorm.ErrRecordNotFound
	}
	if g, ok := idx.byISIN[isin]; ok {
		return g, nil
	}
	return nil, gorm.ErrRecordNotFound
}

// resolveImport matches catalog by scheme_name, then admin mapping, then optional ISIN.
func (idx *mfSchemeCatalogIndex) resolveImport(schemeName, isin string) (*models.GlobalMutualFund, error) {
	if strings.TrimSpace(schemeName) != "" {
		g, err := idx.findBySchemeName(schemeName)
		if err == nil {
			return g, nil
		}
		if err != gorm.ErrRecordNotFound {
			return nil, err
		}
		g, err = idx.findByMappedSchemeName(schemeName)
		if err == nil {
			return g, nil
		}
		if err != gorm.ErrRecordNotFound {
			return nil, err
		}
	}
	if strings.TrimSpace(isin) != "" {
		return idx.findByISIN(isin)
	}
	return nil, gorm.ErrRecordNotFound
}

func upsertUnmappedMFScheme(db *gorm.DB, schemeName, sourceFormat string) (created bool, err error) {
	name := strings.TrimSpace(schemeName)
	if name == "" {
		return false, nil
	}
	var existing models.MFSchemeMapping
	err = db.Where("LOWER(TRIM(source_scheme_name)) = ?", strings.ToLower(name)).First(&existing).Error
	if err == nil {
		updates := map[string]interface{}{}
		if sf := strings.TrimSpace(sourceFormat); sf != "" && existing.SourceFormat != sf {
			updates["source_format"] = sf
		}
		if len(updates) > 0 {
			if uerr := db.Model(&existing).Updates(updates).Error; uerr != nil {
				return false, uerr
			}
		}
		return false, nil
	}
	if err != gorm.ErrRecordNotFound {
		return false, err
	}
	row := models.MFSchemeMapping{
		SourceSchemeName: name,
		MappedISIN:       "",
		SourceFormat:     strings.TrimSpace(sourceFormat),
	}
	if err := db.Create(&row).Error; err != nil {
		return false, err
	}
	return true, nil
}

func findGlobalMutualFundBySchemeName(db *gorm.DB, name string) (*models.GlobalMutualFund, error) {
	idx, err := buildMFSchemeCatalogIndex(db)
	if err != nil {
		return nil, err
	}
	return idx.findBySchemeName(name)
}

// resolveImportGlobalMF matches catalog by scheme_name, mapping, then optional ISIN.
func resolveImportGlobalMF(db *gorm.DB, schemeName, isin string) (*models.GlobalMutualFund, error) {
	idx, err := buildMFSchemeCatalogIndex(db)
	if err != nil {
		return nil, err
	}
	return idx.resolveImport(schemeName, isin)
}

// ReplaceSourceMutualFunds replaces the user's mutual fund holdings for a bulk/broker source.
// Matched items upsert by user+source+isin. Unmatched items are still inserted using
// source_scheme_name (pending admin mapping) and queued in Global_MF_SchemeMapping.
// Qty changes write delta buy/sell rows to User_MutualFund_Transactions (no transaction
// date when the holdings file has none). Stale holdings for the source are sold to zero.
func (h *Handler) ReplaceSourceMutualFunds(c *gin.Context) {
	var req struct {
		Source string `json:"source" binding:"required"`
		Items  []struct {
			SchemeName string  `json:"scheme_name"`
			ISIN       string  `json:"isin"`
			Quantity   float64 `json:"quantity" binding:"required"`
			NAV        float64 `json:"nav" binding:"required"`
			CurrentNAV float64 `json:"current_nav"`
		} `json:"items" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	source := strings.TrimSpace(req.Source)
	if !models.IsReplaceableImportSource(source) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "source must be a bulk import source, not Manual Add"})
		return
	}

	userID := middleware.CurrentUserID(c)
	watchList := h.userUsesWatchList(userID)

	catalog, err := buildMFSchemeCatalogIndex(h.DB)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	type matchedAgg struct {
		global        *models.GlobalMutualFund
		sourceScheme  string
		quantity      float64
		cost          float64
		brokerCurrent float64
	}
	type unmatchedAgg struct {
		sourceScheme  string
		quantity      float64
		cost          float64
		brokerCurrent float64
	}

	byISIN := map[string]*matchedAgg{}
	bySourceName := map[string]*unmatchedAgg{}
	pendingNames := make([]gin.H, 0)
	queuedMappings := 0

	for _, item := range req.Items {
		if item.Quantity <= 0 || item.NAV <= 0 {
			pendingNames = append(pendingNames, gin.H{
				"scheme_name": item.SchemeName,
				"isin":        item.ISIN,
				"reason":      "quantity and nav must be greater than 0",
			})
			continue
		}
		sourceName := strings.TrimSpace(item.SchemeName)
		g, err := catalog.resolveImport(item.SchemeName, item.ISIN)
		if err != nil {
			if err == gorm.ErrRecordNotFound {
				if sourceName == "" {
					pendingNames = append(pendingNames, gin.H{
						"scheme_name": item.SchemeName,
						"isin":        item.ISIN,
						"reason":      "scheme_name is required when not in catalog",
					})
					continue
				}
				created, uerr := upsertUnmappedMFScheme(h.DB, sourceName, source)
				if uerr != nil {
					c.JSON(http.StatusInternalServerError, gin.H{"error": uerr.Error()})
					return
				}
				if created {
					queuedMappings++
				}
				key := strings.ToLower(sourceName)
				if existing, ok := bySourceName[key]; ok {
					existing.cost += item.Quantity * item.NAV
					existing.quantity += item.Quantity
					if item.CurrentNAV > 0 {
						existing.brokerCurrent = item.CurrentNAV
					}
				} else {
					bySourceName[key] = &unmatchedAgg{
						sourceScheme:  sourceName,
						quantity:      item.Quantity,
						cost:          item.Quantity * item.NAV,
						brokerCurrent: item.CurrentNAV,
					}
				}
				pendingNames = append(pendingNames, gin.H{
					"scheme_name": sourceName,
					"isin":        item.ISIN,
					"reason":      "pending catalog link",
				})
				continue
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		key := strings.ToUpper(strings.TrimSpace(g.ISIN))
		if key == "" {
			pendingNames = append(pendingNames, gin.H{
				"scheme_name": item.SchemeName,
				"isin":        item.ISIN,
				"reason":      "catalog row missing ISIN",
			})
			continue
		}
		if existing, ok := byISIN[key]; ok {
			existing.cost += item.Quantity * item.NAV
			existing.quantity += item.Quantity
			if sourceName != "" {
				existing.sourceScheme = sourceName
			}
			if item.CurrentNAV > 0 {
				existing.brokerCurrent = item.CurrentNAV
			}
		} else {
			byISIN[key] = &matchedAgg{
				global:        g,
				sourceScheme:  sourceName,
				quantity:      item.Quantity,
				cost:          item.Quantity * item.NAV,
				brokerCurrent: item.CurrentNAV,
			}
		}
	}

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": tx.Error.Error()})
		return
	}

	touchedISIN := map[string]struct{}{}
	touchedSource := map[string]struct{}{}
	result := make([]models.MutualFund, 0, len(byISIN)+len(bySourceName))
	deltas := make([]models.UserMutualFundTransaction, 0)
	created, updated := 0, 0

	for isin, a := range byISIN {
		avgNAV := a.cost / a.quantity
		qty := a.quantity
		if watchList && qty > 0 {
			qty = 1
		}
		touchedISIN[isin] = struct{}{}
		currentNAV := a.global.CurrentNAV
		if currentNAV <= 0 {
			currentNAV = a.brokerCurrent
		}

		var before models.MutualFund
		existed := findUserMutualFund(tx, userID, source, isin, a.sourceScheme, &before) == nil

		pos, delta, err := applyUploadMFPosition(
			tx, userID,
			a.global.ISIN, a.global.Symbol, a.global.SchemeName, a.sourceScheme, source,
			qty, avgNAV, currentNAV, nil,
		)
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if pos.ID != 0 {
			result = append(result, pos)
			if existed {
				updated++
			} else {
				created++
			}
		}
		if delta != nil {
			deltas = append(deltas, *delta)
		}
	}

	for key, a := range bySourceName {
		avgNAV := a.cost / a.quantity
		qty := a.quantity
		if watchList && qty > 0 {
			qty = 1
		}
		touchedSource[key] = struct{}{}

		var before models.MutualFund
		existed := findUserMutualFund(tx, userID, source, "", a.sourceScheme, &before) == nil

		pos, delta, err := applyUploadMFPosition(
			tx, userID,
			"", "", "", a.sourceScheme, source,
			qty, avgNAV, a.brokerCurrent, nil,
		)
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if pos.ID != 0 {
			result = append(result, pos)
			if existed {
				updated++
			} else {
				created++
			}
		}
		if delta != nil {
			deltas = append(deltas, *delta)
		}
	}

	var stale []models.MutualFund
	if err := tx.Where("user_id = ? AND source = ? AND quantity > 0", userID, source).Find(&stale).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	zeroed := 0
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
		pos, delta, err := applyUploadMFPosition(
			tx, userID,
			row.ISIN, row.SchemeCode, row.SchemeName, row.SourceSchemeName, source,
			0, row.NAV, row.CurrentNAV, nil,
		)
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if pos.ID != 0 {
			result = append(result, pos)
		}
		if delta != nil {
			deltas = append(deltas, *delta)
		}
		zeroed++
	}

	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	enrichUserMutualFundsNAV(h.DB, result)
	c.JSON(http.StatusCreated, gin.H{
		"count":           len(result),
		"created":         created,
		"updated":         updated,
		"deleted":         zeroed, // kept for API compat; holdings are zeroed, not deleted
		"zeroed":          zeroed,
		"unmatched":       pendingNames,
		"queued_mappings": queuedMappings,
		"items":           result,
		"transactions":    deltas,
	})
}

func enrichUserMutualFundsNAV(db *gorm.DB, mfs []models.MutualFund) {
	isins := make([]string, 0, len(mfs))
	seen := map[string]struct{}{}
	for _, mf := range mfs {
		isin := strings.ToUpper(strings.TrimSpace(mf.ISIN))
		if isin == "" {
			continue
		}
		if _, ok := seen[isin]; ok {
			continue
		}
		seen[isin] = struct{}{}
		isins = append(isins, isin)
	}
	if len(isins) == 0 {
		return
	}
	var globals []models.GlobalMutualFund
	if err := db.Where("UPPER(isin) IN ?", isins).Find(&globals).Error; err != nil {
		return
	}
	byISIN := make(map[string]models.GlobalMutualFund, len(globals))
	for _, g := range globals {
		byISIN[strings.ToUpper(g.ISIN)] = g
	}
	for i := range mfs {
		isin := strings.ToUpper(strings.TrimSpace(mfs[i].ISIN))
		g, ok := byISIN[isin]
		if !ok {
			continue
		}
		if g.CurrentNAV > 0 {
			mfs[i].CurrentNAV = g.CurrentNAV
		}
		if mfs[i].SchemeName == "" {
			mfs[i].SchemeName = g.SchemeName
		}
		if mfs[i].SchemeCode == "" {
			mfs[i].SchemeCode = g.Symbol
		}
		applyGlobalReturns(&mfs[i], g)
	}
}

func resolveMFCurrentNAV(db *gorm.DB, mf models.MutualFund, cache map[string]float64) float64 {
	isin := strings.ToUpper(strings.TrimSpace(mf.ISIN))
	if isin != "" {
		if nav, ok := cache[isin]; ok {
			if nav > 0 {
				return nav
			}
			return mf.CurrentNAV
		}
		var g models.GlobalMutualFund
		if err := db.Where("UPPER(isin) = ?", isin).First(&g).Error; err == nil {
			cache[isin] = g.CurrentNAV
			if g.CurrentNAV > 0 {
				return g.CurrentNAV
			}
		} else {
			cache[isin] = 0
		}
	}
	return mf.CurrentNAV
}
