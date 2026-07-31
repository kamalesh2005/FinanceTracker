# Finance Tracker

A personal finance tracking web application built with Go backend and Flutter frontend. Track your stocks and mutual fund investments with ease.

## Features

- **Multi-user auth**: Register / login with email or mobile; JWT sessions
- **Admin role**: Global symbol mappings, stock metadata, user enable/disable
- **Stock Management**: Add, edit, and track stock holdings (per user)
- **Mutual Fund Management**: Track mutual fund investments (per user)
- **Portfolio Summary**: View total invested amount, current value, and profit/loss
- **Real-time P/L Calculation**: Automatic calculation of profit/loss and percentages
- **Forgot password**: OTP via SMTP/SMS (falls back to server console when not configured)
- **Intraday price cron**: While the backend is running, Yahoo current prices for all `Global_Stocks` are updated every 15 minutes on weekdays 09:00–15:30 IST
- **Daily Yahoo refresh cron**: At 06:00 IST each day, prices, historical highs/lows, and trends are refreshed for all `Global_Stocks`
- **Manual refresh**: Stocks screen AppBar refresh icon (and pull-to-refresh) calls `POST /stocks/refresh-prices`

## Default admin

On first startup the backend seeds:

- Username: `admin`
- Password: `Khanak`

## Auth environment variables

| Variable | Purpose |
|----------|---------|
| `JWT_SECRET` | JWT signing secret (defaults to a dev secret) |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | Email OTP delivery |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER` | SMS OTP via Twilio |

If SMTP/Twilio are not set, OTPs are logged to the backend console as `[OTP DEV]`.

## Tech Stack

### Backend
- **Go 1.21+**: Backend language
- **Gin Framework**: Web framework
- **GORM**: ORM for database operations
- **PostgreSQL**: Database
- **JWT + bcrypt**: Authentication

### Frontend
- **Flutter**: Cross-platform mobile app framework
- **Provider**: State management
- **HTTP**: API communication
- **flutter_secure_storage**: JWT persistence

## Project Structure

```
FinanceTracker/
├── backend/
│   ├── main.go              # Application entry point
│   ├── go.mod               # Go module dependencies
│   ├── auth/                # JWT + password helpers
│   ├── middleware/          # Auth / admin middleware
│   ├── notify/              # SMTP / SMS / console OTP
│   ├── jobs/                # Background schedulers (intraday + daily Yahoo)
│   ├── models/              # Data models
│   │   └── models.go
│   └── handlers/            # API handlers
│       └── handlers.go
└── frontend/
    ├── pubspec.yaml         # Flutter dependencies
    └── lib/
        ├── main.dart        # App entry point (auth gate)
        ├── models/          # Data models
        ├── services/        # API services
        ├── providers/       # State management
        └── screens/         # UI screens (login, home, admin, …)
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

On startup, GORM creates prefixed tables (`Global_Stocks`, `User_Stocks`, `User_Stock_Transactions`, etc.). Existing databases with legacy names (`stocks`, `transactions`, `User_Transactions`, …) are renamed automatically once. Lot-shaped `User_Stocks` rows are migrated into `User_Stock_Transactions` and rebuilt as one position per user+source+stock.

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

All routes except auth register/login/forgot/reset require `Authorization: Bearer <token>`.

### Auth
- `POST /api/v1/auth/register` - Self-register (email and/or mobile + password)
- `POST /api/v1/auth/login` - Login (identifier + password)
- `POST /api/v1/auth/forgot-password` - Send OTP
- `POST /api/v1/auth/reset-password` - Reset with OTP
- `GET /api/v1/auth/me` - Current user

### Stocks
- `GET /api/v1/stocks` - Get stocks (user holdings; admin sees full catalog)
- `POST /api/v1/stocks` - Create a new stock
- `GET /api/v1/stocks/:id` - Get a specific stock
- `PUT /api/v1/stocks/:id` - Update a stock
- `DELETE /api/v1/stocks/:id` - Delete a stock (admin)
- `PUT /api/v1/stocks/:id/admin` - Update admin stock fields (admin)

### Admin users
- `GET /api/v1/admin/users` - List users
- `POST /api/v1/admin/users` - Create user
- `PUT /api/v1/admin/users/:id/enabled` - Enable/disable user

### Mutual Funds
- `GET /api/v1/mutualfunds` - Get current user's mutual funds
- `POST /api/v1/mutualfunds` - Create a new mutual fund
- `GET /api/v1/mutualfunds/:id` - Get a specific mutual fund
- `PUT /api/v1/mutualfunds/:id` - Update a mutual fund
- `DELETE /api/v1/mutualfunds/:id` - Delete a mutual fund

### Portfolio
- `GET /api/v1/portfolio` - Get current user's portfolio
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

- Export portfolio data
- Tax reports
- Multiple portfolio / org tenancy
- Email verification on register

## License

MIT License
# FinanceTracker
