package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"financetracker/handlers"
	"financetracker/models"
	"financetracker/nseimport"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func databaseDSN() string {
	if dsn := strings.TrimSpace(os.Getenv("DATABASE_URL")); dsn != "" {
		return dsn
	}
	return "host=localhost user=finance password=finance dbname=financetracker port=5432 sslmode=disable"
}

func loadDotEnv(path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq := strings.IndexByte(line, '=')
		if eq <= 0 {
			continue
		}
		key := strings.TrimSpace(line[:eq])
		val := strings.TrimSpace(line[eq+1:])
		if len(val) >= 2 {
			if (val[0] == '"' && val[len(val)-1] == '"') || (val[0] == '\'' && val[len(val)-1] == '\'') {
				val = val[1 : len(val)-1]
			}
		}
		if key == "" {
			continue
		}
		if _, exists := os.LookupEnv(key); exists {
			continue
		}
		_ = os.Setenv(key, val)
	}
}

func main() {
	csvPath := flag.String("csv", "", "path to NSE_All CSV")
	flag.Parse()
	if strings.TrimSpace(*csvPath) == "" {
		log.Fatal("usage: import-nse -csv path/to/NSE_All.csv")
	}

	loadDotEnv(".env")
	loadDotEnv("../.env")

	db, err := gorm.Open(postgres.Open(databaseDSN()), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Warn),
	})
	if err != nil {
		log.Fatalf("db connect: %v", err)
	}
	if err := db.AutoMigrate(&models.Stock{}); err != nil {
		log.Fatalf("migrate: %v", err)
	}

	f, err := os.Open(*csvPath)
	if err != nil {
		log.Fatalf("open csv: %v", err)
	}
	defer f.Close()

	result, err := nseimport.ImportCSV(db, f)
	if err != nil {
		log.Fatalf("import: %v", err)
	}
	if err := handlers.BackfillPullDataFromHoldings(db); err != nil {
		log.Printf("backfill pull_data: %v", err)
	}
	fmt.Printf("NSE import done: created=%d updated=%d skipped=%d errors=%d\n",
		result.Created, result.Updated, result.Skipped, result.Errors)
}
