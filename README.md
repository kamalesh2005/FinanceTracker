# Finance Tracker

A personal finance tracking web application built with Go backend and Flutter frontend. Track your stocks and mutual fund investments with ease.

## Features

- **Stock Management**: Add, edit, and delete stock holdings
- **Mutual Fund Management**: Track your mutual fund investments
- **Portfolio Summary**: View total invested amount, current value, and profit/loss
- **Real-time P/L Calculation**: Automatic calculation of profit/loss and percentages

## Tech Stack

### Backend
- **Go 1.21+**: Backend language
- **Gin Framework**: Web framework
- **GORM**: ORM for database operations
- **PostgreSQL**: Database

### Frontend
- **Flutter**: Cross-platform mobile app framework
- **Provider**: State management
- **HTTP**: API communication

## Project Structure

```
FinanceTracker/
├── backend/
│   ├── main.go              # Application entry point
│   ├── go.mod               # Go module dependencies
│   ├── models/              # Data models
│   │   └── models.go
│   └── handlers/            # API handlers
│       └── handlers.go
└── frontend/
    ├── pubspec.yaml         # Flutter dependencies
    └── lib/
        ├── main.dart        # App entry point
        ├── models/          # Data models
        │   ├── stock.dart
        │   └── mutual_fund.dart
        ├── services/        # API services
        │   └── api_service.dart
        ├── providers/       # State management
        │   └── finance_provider.dart
        └── screens/         # UI screens
            ├── home_screen.dart
            ├── stocks_screen.dart
            ├── add_stock_screen.dart
            ├── mutual_funds_screen.dart
            └── add_mutual_fund_screen.dart
```

## Setup Instructions

### Prerequisites

- Go 1.21 or higher
- Flutter SDK
- PostgreSQL
- Android Studio / Xcode (for mobile development)

### Backend Setup

1. Navigate to the backend directory:
```bash
cd backend
```

2. Install dependencies:
```bash
go mod download
```

3. Set up PostgreSQL database:
```sql
CREATE DATABASE financetracker;
CREATE USER finance WITH PASSWORD 'finance';
GRANT ALL PRIVILEGES ON DATABASE financetracker TO finance;
```

4. Update database connection in `main.go` if needed:
```go
dsn := "host=localhost user=finance password=finance dbname=financetracker port=5432 sslmode=disable"
```

5. Run the server:
```bash
go run main.go
```

The API will be available at `http://localhost:8080`

### Frontend Setup

1. Navigate to the frontend directory:
```bash
cd frontend
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## API Endpoints

### Stocks
- `GET /api/v1/stocks` - Get all stocks
- `POST /api/v1/stocks` - Create a new stock
- `GET /api/v1/stocks/:id` - Get a specific stock
- `PUT /api/v1/stocks/:id` - Update a stock
- `DELETE /api/v1/stocks/:id` - Delete a stock

### Mutual Funds
- `GET /api/v1/mutualfunds` - Get all mutual funds
- `POST /api/v1/mutualfunds` - Create a new mutual fund
- `GET /api/v1/mutualfunds/:id` - Get a specific mutual fund
- `PUT /api/v1/mutualfunds/:id` - Update a mutual fund
- `DELETE /api/v1/mutualfunds/:id` - Delete a mutual fund

### Portfolio
- `GET /api/v1/portfolio` - Get full portfolio
- `GET /api/v1/portfolio/summary` - Get portfolio summary

## Data Models

### Stock
```json
{
  "id": 1,
  "symbol": "RELIANCE",
  "name": "Reliance Industries",
  "quantity": 10,
  "buy_price": 2500.50,
  "current_price": 2600.75,
  "purchase_date": "2024-01-15T00:00:00Z"
}
```

### Mutual Fund
```json
{
  "id": 1,
  "scheme_code": "120503",
  "scheme_name": "HDFC Small Cap Fund",
  "fund_house": "HDFC Mutual Fund",
  "quantity": 100,
  "nav": 50.25,
  "current_nav": 55.75,
  "purchase_date": "2024-01-15T00:00:00Z"
}
```

## Future Enhancements

- User authentication
- Real-time stock price updates
- Chart visualization
- Export portfolio data
- Transaction history
- Tax reports
- Multiple portfolio support

## License

MIT License
