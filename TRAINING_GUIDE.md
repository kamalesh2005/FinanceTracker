# FinanceTracker Development Training Guide

## Table of Contents
1. [Introduction](#introduction)
2. [Project Overview](#project-overview)
3. [Prerequisites and Setup](#prerequisites-and-setup)
4. [Go Fundamentals](#go-fundamentals)
5. [Backend Development with Go](#backend-development-with-go)
6. [Flutter Fundamentals](#flutter-fundamentals)
7. [Frontend Development with Flutter](#frontend-development-with-flutter)
8. [Database Design and Integration](#database-design-and-integration)
9. [API Development and Integration](#api-development-and-integration)
10. [State Management in Flutter](#state-management-in-flutter)
11. [Building the User Interface](#building-the-user-interface)
12. [Testing and Debugging](#testing-and-debugging)
13. [Deployment and Best Practices](#deployment-and-best-practices)
14. [Advanced Topics](#advanced-topics)

---

## Introduction

### Welcome to the FinanceTracker Project
This training guide will walk you through building a complete finance tracking application from scratch. You'll learn Go for backend development and Flutter for creating a cross-platform frontend application.

### What You'll Build
A personal finance tracking application that allows users to:
- Track stock investments with buy/sell transactions
- Monitor mutual fund investments
- View portfolio summaries with real-time profit/loss calculations
- Visualize stock trends and historical data
- Import/export investment data

### Learning Outcomes
By the end of this guide, you will:
- Understand Go programming fundamentals and web development
- Master Flutter framework and cross-platform app development
- Learn RESTful API design and implementation
- Understand database design with PostgreSQL
- Implement state management patterns
- Build responsive and interactive user interfaces

---

## Project Overview

### Architecture Overview
```
FinanceTracker/
├── backend/          # Go backend API server
│   ├── main.go       # Application entry point
│   ├── models/       # Data models
│   ├── handlers/     # API request handlers
│   └── go.mod        # Go dependencies
├── frontend/         # Flutter mobile/web app
│   ├── lib/
│   │   ├── main.dart         # App entry point
│   │   ├── models/           # Data models
│   │   ├── services/         # API communication
│   │   ├── providers/        # State management
│   │   └── screens/          # UI screens
│   └── pubspec.yaml          # Flutter dependencies
└── scripts/          # Utility scripts
```

### Technology Stack

#### Backend
- **Go 1.25+**: A modern, statically typed programming language
- **Gin Framework**: High-performance HTTP web framework
- **GORM**: Object-Relational Mapping library for database operations
- **PostgreSQL**: Relational database for data persistence

#### Frontend
- **Flutter 3.0+**: Google's UI toolkit for building natively compiled applications
- **Provider**: State management solution
- **HTTP**: Package for making API requests
- **FL Chart**: Charting library for data visualization

### Key Features
1. **Stock Management**: Add, edit, delete stocks with transaction tracking
2. **Mutual Fund Tracking**: Monitor mutual fund investments
3. **Real-time Data**: Fetch current prices from Yahoo Finance API
4. **Portfolio Analytics**: Calculate profit/loss with percentage changes
5. **Data Visualization**: Interactive charts for stock trends
6. **Bulk Operations**: Import multiple stocks at once

---

## Prerequisites and Setup

### System Requirements
- **Operating System**: macOS, Windows, or Linux
- **RAM**: Minimum 8GB (16GB recommended)
- **Disk Space**: 5GB free space
- **Internet Connection**: Required for downloading dependencies and API calls

### Software Installation

#### 1. Installing Go

**What is Go?**
Go (also known as Golang) is a statically typed, compiled programming language designed at Google. It's known for its simplicity, efficiency, and excellent support for concurrent programming.

**Installation Steps:**

**macOS:**
```bash
# Using Homebrew (recommended)
brew install go

# Verify installation
go version
```

**Windows:**
1. Download the installer from https://go.dev/dl/
2. Run the installer and follow the prompts
3. Restart your terminal/command prompt
4. Verify: `go version`

**Linux:**
```bash
# Download and extract
wget https://go.dev/dl/go1.25.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.25.0.linux-amd64.tar.gz

# Add to PATH (add to ~/.bashrc or ~/.zshrc)
export PATH=$PATH:/usr/local/go/bin

# Verify installation
go version
```

**Go Environment Variables:**
```bash
# Set GOPATH (where Go packages are installed)
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

# Verify setup
go env
```

#### 2. Installing Flutter

**What is Flutter?**
Flutter is Google's UI toolkit for building beautiful, natively compiled applications for mobile, web, and desktop from a single codebase.

**Installation Steps:**

**macOS:**
```bash
# Using Homebrew
brew install --cask flutter

# Verify installation
flutter doctor
```

**Windows:**
1. Download Flutter SDK from https://flutter.dev/docs/get-started/install/windows
2. Extract the zip file to a location (e.g., C:\src\flutter)
3. Add Flutter to your PATH:
   - Search for "Environment Variables" in Windows
   - Add `C:\src\flutter\bin` to your PATH
4. Run: `flutter doctor`

**Linux:**
```bash
# Download and extract
cd ~
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"

# Verify installation
flutter doctor
```

**Flutter Doctor:**
```bash
flutter doctor
```
This command checks your environment and displays a report of the status of your Flutter installation. Follow the instructions to fix any issues.

#### 3. Installing PostgreSQL

**What is PostgreSQL?**
PostgreSQL is a powerful, open-source object-relational database system with over 30 years of active development.

**Installation Steps:**

**macOS:**
```bash
# Using Homebrew
brew install postgresql@15
brew services start postgresql@15

# Create database
createdb financetracker
```

**Windows:**
1. Download from https://www.postgresql.org/download/windows/
2. Run the installer and follow the prompts
3. Set a password for the postgres user
4. Use pgAdmin to create databases

**Linux (Ubuntu):**
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql

# Create database and user
sudo -u postgres psql
CREATE DATABASE financetracker;
CREATE USER finance WITH PASSWORD 'finance';
GRANT ALL PRIVILEGES ON DATABASE financetracker TO finance;
\q
```

#### 4. Installing Development Tools

**VS Code (Recommended IDE):**
```bash
# Install VS Code
# Then install extensions:
# - Go extension for VS Code
# - Flutter extension for VS Code
```

**Postman (for API testing):**
Download from https://www.postman.com/downloads/

### Project Setup

#### 1. Clone/Create Project Structure
```bash
# Create project directory
mkdir FinanceTracker
cd FinanceTracker

# Create directory structure
mkdir backend frontend scripts
cd backend
mkdir models handlers
cd ../frontend
mkdir lib/models lib/services lib/providers lib/screens
```

#### 2. Initialize Go Backend
```bash
cd backend
go mod init financetracker
```

#### 3. Initialize Flutter Frontend
```bash
cd frontend
flutter create .
```

---

## Go Fundamentals

### 1. Go Language Basics

#### Hello World
```go
package main

import "fmt"

func main() {
    fmt.Println("Hello, World!")
}
```

**Explanation:**
- `package main`: Every Go program starts with a package declaration
- `import "fmt"`: Imports the formatted I/O package
- `func main()`: The entry point of the program
- `fmt.Println()`: Prints to console with a newline

#### Variables and Data Types
```go
package main

import "fmt"

func main() {
    // Variable declaration with type
    var name string = "John"
    var age int = 25
    var salary float64 = 50000.50
    var isEmployed bool = true

    // Short declaration (type inferred)
    city := "New York"
    score := 95

    // Multiple variables
    var (
        firstName string = "John"
        lastName  string = "Doe"
    )

    // Constants
    const pi = 3.14159
    const maxUsers = 100

    fmt.Printf("Name: %s, Age: %d, City: %s\n", name, age, city)
    fmt.Printf("Salary: %.2f, Employed: %t\n", salary, isEmployed)
}
```

#### Functions
```go
package main

import "fmt"

// Basic function
func greet(name string) {
    fmt.Printf("Hello, %s!\n", name)
}

// Function with return value
func add(a, b int) int {
    return a + b
}

// Function with multiple return values
func divide(a, b float64) (float64, error) {
    if b == 0 {
        return 0, fmt.Errorf("cannot divide by zero")
    }
    return a / b, nil
}

// Named return values
func calculateRectangle(length, width float64) (area, perimeter float64) {
    area = length * width
    perimeter = 2 * (length + width)
    return // naked return
}

func main() {
    greet("Alice")
    
    sum := add(5, 3)
    fmt.Printf("Sum: %d\n", sum)

    result, err := divide(10, 2)
    if err != nil {
        fmt.Println("Error:", err)
    } else {
        fmt.Printf("Division result: %.2f\n", result)
    }

    area, perimeter := calculateRectangle(5, 3)
    fmt.Printf("Area: %.2f, Perimeter: %.2f\n", area, perimeter)
}
```

#### Control Structures
```go
package main

import "fmt"

func main() {
    // If-else
    age := 18
    if age >= 18 {
        fmt.Println("You are an adult")
    } else {
        fmt.Println("You are a minor")
    }

    // If with initialization
    if score := 85; score >= 90 {
        fmt.Println("Grade: A")
    } else if score >= 80 {
        fmt.Println("Grade: B")
    } else {
        fmt.Println("Grade: C")
    }

    // For loop (Go only has for loops)
    // Traditional for loop
    for i := 0; i < 5; i++ {
        fmt.Printf("Iteration %d\n", i)
    }

    // While-style loop
    count := 0
    for count < 3 {
        fmt.Printf("Count: %d\n", count)
        count++
    }

    // Infinite loop with break
    for {
        fmt.Println("This will run once")
        break
    }

    // Range over slice
    numbers := []int{10, 20, 30, 40, 50}
    for index, value := range numbers {
        fmt.Printf("Index: %d, Value: %d\n", index, value)
    }

    // Switch statement
    day := "Monday"
    switch day {
    case "Monday":
        fmt.Println("Start of the week")
    case "Friday":
        fmt.Println("End of the week")
    default:
        fmt.Println("Midweek")
    }
}
```

#### Arrays and Slices
```go
package main

import "fmt"

func main() {
    // Array (fixed size)
    var arr [5]int
    arr[0] = 10
    arr[1] = 20
    fmt.Println("Array:", arr)

    // Array literal
    numbers := [3]int{1, 2, 3}
    fmt.Println("Numbers:", numbers)

    // Slice (dynamic size)
    var slice []int
    slice = append(slice, 1)
    slice = append(slice, 2, 3)
    fmt.Println("Slice:", slice)

    // Slice literal
    fruits := []string{"apple", "banana", "orange"}
    fmt.Println("Fruits:", fruits)

    // Slice operations
    fmt.Println("First fruit:", fruits[0])
    fmt.Println("Last two fruits:", fruits[1:])

    // Slicing
    numbers := []int{0, 1, 2, 3, 4, 5}
    subset := numbers[1:4] // [1, 2, 3]
    fmt.Println("Subset:", subset)

    // Length and capacity
    fmt.Printf("Length: %d, Capacity: %d\n", len(slice), cap(slice))

    // Make slice with capacity
    dynamic := make([]int, 0, 10)
    dynamic = append(dynamic, 1, 2, 3)
    fmt.Println("Dynamic slice:", dynamic)
}
```

#### Maps
```go
package main

import "fmt"

func main() {
    // Map declaration
    var person map[string]string
    person = make(map[string]string)

    // Adding elements
    person["name"] = "John"
    person["city"] = "New York"
    fmt.Println("Person:", person)

    // Map literal
    user := map[string]int{
        "age":    25,
        "score":  95,
        "level":  5,
    }
    fmt.Println("User:", user)

    // Accessing elements
    name := person["name"]
    fmt.Println("Name:", name)

    // Checking if key exists
    if age, exists := user["age"]; exists {
        fmt.Println("Age exists:", age)
    }

    // Deleting elements
    delete(user, "level")
    fmt.Println("User after deletion:", user)

    // Iterating over map
    for key, value := range person {
        fmt.Printf("%s: %s\n", key, value)
    }
}
```

#### Structs
```go
package main

import "fmt"

// Define a struct
type Person struct {
    Name    string
    Age     int
    Email   string
}

// Method on struct
func (p Person) Greet() string {
    return fmt.Sprintf("Hello, my name is %s", p.Name)
}

// Pointer method (can modify struct)
func (p *Person) HaveBirthday() {
    p.Age++
}

func main() {
    // Create struct
    person := Person{
        Name:  "John Doe",
        Age:   25,
        Email: "john@example.com",
    }
    fmt.Println("Person:", person)

    // Access fields
    fmt.Println("Name:", person.Name)
    fmt.Println("Age:", person.Age)

    // Call method
    fmt.Println(person.Greet())

    // Modify using pointer method
    person.HaveBirthday()
    fmt.Println("Age after birthday:", person.Age)

    // Struct with tags (used for JSON serialization)
    type Stock struct {
        Symbol  string  `json:"symbol"`
        Name    string  `json:"name"`
        Price   float64 `json:"price"`
    }

    stock := Stock{
        Symbol: "AAPL",
        Name:   "Apple Inc.",
        Price:  150.50,
    }
    fmt.Printf("Stock: %+v\n", stock)
}
```

#### Pointers
```go
package main

import "fmt"

func main() {
    // Basic pointer usage
    x := 42
    p := &x // p is a pointer to x

    fmt.Println("Value of x:", x)
    fmt.Println("Address of x:", p)
    fmt.Println("Value through pointer:", *p)

    // Modifying through pointer
    *p = 100
    fmt.Println("New value of x:", x)

    // Pointers with functions
    a := 10
    increment(&a)
    fmt.Println("After increment:", a)
}

func increment(x *int) {
    *x++
}
```

#### Interfaces
```go
package main

import "fmt"

// Define an interface
type Shape interface {
    Area() float64
    Perimeter() float64
}

// Implement interface
type Rectangle struct {
    Length, Width float64
}

func (r Rectangle) Area() float64 {
    return r.Length * r.Width
}

func (r Rectangle) Perimeter() float64 {
    return 2 * (r.Length + r.Width)
}

type Circle struct {
    Radius float64
}

func (c Circle) Area() float64 {
    return 3.14159 * c.Radius * c.Radius
}

func (c Circle) Perimeter() float64 {
    return 2 * 3.14159 * c.Radius
}

func main() {
    var shapes []Shape

    shapes = append(shapes, Rectangle{Length: 5, Width: 3})
    shapes = append(shapes, Circle{Radius: 7})

    for _, shape := range shapes {
        fmt.Printf("Area: %.2f, Perimeter: %.2f\n", 
            shape.Area(), shape.Perimeter())
    }
}
```

#### Error Handling
```go
package main

import (
    "errors"
    "fmt"
)

func divide(a, b float64) (float64, error) {
    if b == 0 {
        return 0, errors.New("cannot divide by zero")
    }
    return a / b, nil
}

func main() {
    result, err := divide(10, 0)
    if err != nil {
        fmt.Println("Error:", err)
        return
    }
    fmt.Println("Result:", result)

    // Custom error with formatting
    result, err = divide(10, 2)
    if err != nil {
        fmt.Printf("Error: %v\n", err)
    } else {
        fmt.Printf("Result: %.2f\n", result)
    }
}
```

#### Goroutines and Channels (Concurrency Basics)
```go
package main

import (
    "fmt"
    "time"
)

func sayHello(name string) {
    for i := 0; i < 3; i++ {
        fmt.Printf("Hello %s!\n", name)
        time.Sleep(100 * time.Millisecond)
    }
}

func main() {
    // Running function concurrently
    go sayHello("Alice")
    go sayHello("Bob")

    // Wait for goroutines to finish
    time.Sleep(500 * time.Millisecond)

    // Channels for communication
    messages := make(chan string)

    go func() {
        messages <- "Hello from goroutine!"
    }()

    msg := <-messages
    fmt.Println("Received:", msg)
}
```

### 2. Go Packages and Modules

#### Creating a Package
```go
// In file: mathutils/mathutils.go
package mathutils

func Add(a, b int) int {
    return a + b
}

func Multiply(a, b int) int {
    return a * b
}
```

#### Using Packages
```go
package main

import (
    "fmt"
    "financetracker/mathutils" // Import local package
)

func main() {
    sum := mathutils.Add(5, 3)
    product := mathutils.Multiply(4, 6)
    
    fmt.Printf("Sum: %d, Product: %d\n", sum, product)
}
```

#### Go Modules
```bash
# Initialize a new module
go mod init financetracker

# This creates go.mod file:
# module financetracker
# go 1.25.0
```

#### Adding Dependencies
```bash
# Add a dependency
go get github.com/gin-gonic/gin

# This automatically updates go.mod and go.sum
```

---

## Backend Development with Go

### 1. Setting Up the Go Backend

#### Project Structure
```
backend/
├── main.go              # Application entry point
├── go.mod               # Go module file
├── go.sum               # Dependency checksums
├── models/
│   └── models.go        # Data models
└── handlers/
    └── handlers.go      # API handlers
```

#### Initialize Go Module
```bash
cd backend
go mod init financetracker
```

### 2. Installing Dependencies

#### Install Required Packages
```bash
# Gin framework for web server
go get github.com/gin-gonic/gin

# GORM for database operations
go get gorm.io/gorm
go get gorm.io/driver/postgres

# CORS middleware
go get github.com/gin-contrib/cors
```

#### Updated go.mod
```go
module financetracker

go 1.25.0

require (
    github.com/gin-contrib/cors v1.7.7
    github.com/gin-gonic/gin v1.12.0
    gorm.io/driver/postgres v1.5.4
    gorm.io/gorm v1.25.5
)
```

### 3. Creating Data Models

#### Understanding Models
Models represent your database tables and the structure of your data. In Go, we use structs to define models.

#### Create models/models.go
```go
package models

import "time"

// Stock represents a stock in the portfolio
type Stock struct {
    ID                uint          `json:"id" gorm:"primaryKey"`
    Symbol            string        `json:"symbol" gorm:"not null;uniqueIndex"`
    Name              string        `json:"name"`
    Sector            string        `json:"sector"`
    CurrentPrice      float64       `json:"current_price"`
    SixthHighestPrice float64       `json:"sixth_highest_price"`
    SixthLowestPrice  float64       `json:"sixth_lowest_price"`
    LastFetchedDate   *time.Time    `json:"last_fetched_date"`
    CreatedAt         time.Time     `json:"created_at"`
    UpdatedAt         time.Time     `json:"updated_at"`
    Transactions      []Transaction `json:"transactions" gorm:"foreignKey:StockID"`
}

// TransactionType represents buy or sell transaction
type TransactionType string

const (
    TransactionTypeBuy  TransactionType = "buy"
    TransactionTypeSell TransactionType = "sell"
)

// Transaction represents a buy/sell transaction
type Transaction struct {
    ID                uint            `json:"id" gorm:"primaryKey"`
    StockID           uint            `json:"stock_id" gorm:"not null;index"`
    Type              TransactionType `json:"type" gorm:"not null"`
    Quantity          float64         `json:"quantity" gorm:"not null"`
    Price             float64         `json:"price" gorm:"not null"`
    RemainingQuantity float64         `json:"remaining_quantity" gorm:"not null"`
    TransactionDate   time.Time       `json:"transaction_date" gorm:"not null"`
    CreatedAt         time.Time       `json:"created_at"`
    UpdatedAt         time.Time       `json:"updated_at"`
    Stock             Stock           `json:"stock" gorm:"foreignKey:StockID"`
}

// MutualFund represents a mutual fund investment
type MutualFund struct {
    ID           uint      `json:"id" gorm:"primaryKey"`
    SchemeCode   string    `json:"scheme_code" gorm:"not null"`
    SchemeName   string    `json:"scheme_name"`
    FundHouse    string    `json:"fund_house"`
    Quantity     float64   `json:"quantity" gorm:"not null"`
    NAV          float64   `json:"nav" gorm:"not null"`
    CurrentNAV   float64   `json:"current_nav"`
    PurchaseDate time.Time `json:"purchase_date"`
    CreatedAt    time.Time `json:"created_at"`
    UpdatedAt    time.Time `json:"updated_at"`
}

// Portfolio represents a portfolio summary
type Portfolio struct {
    ID             uint      `json:"id" gorm:"primaryKey"`
    Name           string    `json:"name" gorm:"not null"`
    TotalValue     float64   `json:"total_value"`
    InvestedAmount float64   `json:"invested_amount"`
    ProfitLoss     float64   `json:"profit_loss"`
    CreatedAt      time.Time `json:"created_at"`
    UpdatedAt      time.Time `json:"updated_at"`
}
```

**Explanation of GORM Tags:**
- `gorm:"primaryKey"`: Marks field as primary key
- `gorm:"not null"`: Field cannot be null
- `gorm:"uniqueIndex"`: Creates a unique index
- `gorm:"foreignKey:StockID"`: Defines foreign key relationship
- `json:"field_name"`: JSON serialization tag

### 4. Database Connection and Migration

#### Database Setup in main.go
```go
package main

import (
    "financetracker/handlers"
    "financetracker/models"
    "log"

    "github.com/gin-contrib/cors"
    "github.com/gin-gonic/gin"
    "gorm.io/driver/postgres"
    "gorm.io/gorm"
)

func main() {
    // Database connection string
    dsn := "host=localhost user=finance password=finance dbname=financetracker port=5432 sslmode=disable"
    
    // Connect to database
    db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
    if err != nil {
        log.Fatal("Failed to connect to database:", err)
    }

    log.Println("Database connected successfully")

    // Auto-migrate models (creates tables)
    err = db.AutoMigrate(&models.Stock{}, &models.MutualFund{}, &models.Portfolio{}, &models.Transaction{})
    if err != nil {
        log.Fatal("Failed to migrate database:", err)
    }

    log.Println("Database migration completed")

    // Initialize Gin router
    r := gin.Default()

    // Add CORS middleware
    r.Use(cors.New(cors.Config{
        AllowOrigins:     []string{"*"},
        AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
        AllowHeaders:     []string{"Origin", "Content-Type", "Accept"},
        AllowCredentials: true,
    }))

    // Initialize handlers with database
    h := handlers.NewHandler(db)

    // Start server
    log.Println("Server starting on :8080")
    r.Run(":8080")
}
```

**Understanding the Code:**
1. **Database Connection**: We use GORM to connect to PostgreSQL
2. **Auto Migration**: GORM automatically creates tables based on our models
3. **CORS Middleware**: Allows frontend to communicate with backend
4. **Gin Router**: Sets up the web server

### 5. Creating API Handlers

#### Basic Handler Structure
```go
package handlers

import (
    "financetracker/models"
    "github.com/gin-gonic/gin"
    "gorm.io/gorm"
)

type Handler struct {
    DB *gorm.DB
}

func NewHandler(db *gorm.DB) *Handler {
    return &Handler{DB: db}
}
```

#### Stock CRUD Operations

**Get All Stocks:**
```go
func (h *Handler) GetStocks(c *gin.Context) {
    var stocks []models.Stock
    if err := h.DB.Find(&stocks).Error; err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }
    c.JSON(200, stocks)
}
```

**Create Stock:**
```go
func (h *Handler) CreateStock(c *gin.Context) {
    var stock models.Stock
    if err := c.ShouldBindJSON(&stock); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    if err := h.DB.Create(&stock).Error; err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }
    c.JSON(201, stock)
}
```

**Get Single Stock:**
```go
func (h *Handler) GetStock(c *gin.Context) {
    id := c.Param("id")
    var stock models.Stock
    if err := h.DB.First(&stock, id).Error; err != nil {
        c.JSON(404, gin.H{"error": "Stock not found"})
        return
    }
    c.JSON(200, stock)
}
```

**Update Stock:**
```go
func (h *Handler) UpdateStock(c *gin.Context) {
    id := c.Param("id")
    var stock models.Stock
    if err := h.DB.First(&stock, id).Error; err != nil {
        c.JSON(404, gin.H{"error": "Stock not found"})
        return
    }
    if err := c.ShouldBindJSON(&stock); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }
    if err := h.DB.Save(&stock).Error; err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }
    c.JSON(200, stock)
}
```

**Delete Stock:**
```go
func (h *Handler) DeleteStock(c *gin.Context) {
    id := c.Param("id")
    if err := h.DB.Delete(&models.Stock{}, id).Error; err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }
    c.JSON(200, gin.H{"message": "Stock deleted"})
}
```

### 6. Setting Up Routes

#### Add Routes to main.go
```go
func main() {
    // ... previous code ...

    // API routes
    api := r.Group("/api/v1")
    {
        // Stock routes
        api.GET("/stocks", h.GetStocks)
        api.POST("/stocks", h.CreateStock)
        api.GET("/stocks/:id", h.GetStock)
        api.PUT("/stocks/:id", h.UpdateStock)
        api.DELETE("/stocks/:id", h.DeleteStock)

        // Mutual Fund routes
        api.GET("/mutualfunds", h.GetMutualFunds)
        api.POST("/mutualfunds", h.CreateMutualFund)
        api.GET("/mutualfunds/:id", h.GetMutualFund)
        api.PUT("/mutualfunds/:id", h.UpdateMutualFund)
        api.DELETE("/mutualfunds/:id", h.DeleteMutualFund)

        // Portfolio routes
        api.GET("/portfolio", h.GetPortfolio)
        api.GET("/portfolio/summary", h.GetPortfolioSummary)
    }

    r.Run(":8080")
}
```

### 7. Testing the Backend

#### Run the Server
```bash
cd backend
go run main.go
```

#### Test with curl
```bash
# Get all stocks
curl http://localhost:8080/api/v1/stocks

# Create a stock
curl -X POST http://localhost:8080/api/v1/stocks \
  -H "Content-Type: application/json" \
  -d '{"symbol":"AAPL","name":"Apple Inc.","current_price":150.50}'

# Get specific stock
curl http://localhost:8080/api/v1/stocks/1
```

---

## Flutter Fundamentals

### 1. Flutter Basics

#### What is Flutter?
Flutter is Google's UI toolkit for building beautiful, natively compiled applications for mobile, web, and desktop from a single codebase.

#### Key Concepts
- **Widgets**: Everything in Flutter is a widget
- **Widget Tree**: UI is built as a tree of widgets
- **Stateless vs Stateful**: Widgets that don't change vs widgets that can change
- **Hot Reload**: See changes instantly without restarting

#### Hello World in Flutter
```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hello Flutter',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Hello Flutter'),
        ),
        body: const Center(
          child: Text('Hello, World!'),
        ),
      ),
    );
  }
}
```

### 2. Dart Language Basics

#### Variables and Types
```dart
void main() {
  // Type inference
  var name = 'John';
  var age = 25;
  
  // Explicit types
  String city = 'New York';
  int score = 95;
  double price = 99.99;
  bool isActive = true;
  
  // Final and const
  final String country = 'USA'; // runtime constant
  const pi = 3.14159; // compile-time constant
  
  // String interpolation
  print('Name: $name, Age: $age');
  print('Price: \$${price.toStringAsFixed(2)}');
}
```

#### Functions
```dart
void main() {
  greet('Alice');
  
  var sum = add(5, 3);
  print('Sum: $sum');
  
  var result = divide(10, 2);
  print('Division: $result');
}

void greet(String name) {
  print('Hello, $name!');
}

int add(int a, int b) {
  return a + b;
}

double divide(double a, double b) {
  if (b == 0) {
    throw Exception('Cannot divide by zero');
  }
  return a / b;
}

// Arrow function (single expression)
int multiply(int a, int b) => a * b;
```

#### Classes and Objects
```dart
class Person {
  String name;
  int age;
  
  Person(this.name, this.age);
  
  // Named constructor
  Person.guest() : name = 'Guest', age = 0;
  
  void introduce() {
    print('My name is $name and I am $age years old');
  }
}

void main() {
  var person = Person('John', 25);
  person.introduce();
  
  var guest = Person.guest();
  guest.introduce();
}
```

#### Collections
```dart
void main() {
  // Lists
  var fruits = ['apple', 'banana', 'orange'];
  fruits.add('grape');
  print(fruits);
  print('First fruit: ${fruits[0]}');
  
  // Maps
  var user = {
    'name': 'John',
    'age': 25,
    'city': 'New York'
  };
  print(user['name']);
  
  // Sets
  var uniqueNumbers = {1, 2, 3, 3, 4};
  print(uniqueNumbers); // {1, 2, 3, 4}
}
```

#### Async Programming
```dart
void main() async {
  // Future
  var result = await fetchData();
  print('Data: $result');
  
  // Stream
  await for (var value in countStream()) {
    print('Count: $value');
  }
}

Future<String> fetchData() async {
  await Future.delayed(Duration(seconds: 1));
  return 'Sample Data';
}

Stream<int> countStream() async* {
  for (int i = 1; i <= 5; i++) {
    await Future.delayed(Duration(seconds: 1));
    yield i;
  }
}
```

### 3. Flutter Widgets

#### Common Widgets

**Container:**
```dart
Container(
  width: 100,
  height: 100,
  color: Colors.blue,
  child: const Center(
    child: Text('Hello'),
  ),
)
```

**Row and Column:**
```dart
Column(
  children: [
    Text('First'),
    Text('Second'),
    Row(
      children: [
        Text('A'),
        Text('B'),
      ],
    ),
  ],
)
```

**ListView:**
```dart
ListView(
  children: [
    ListTile(title: Text('Item 1')),
    ListTile(title: Text('Item 2')),
    ListTile(title: Text('Item 3')),
  ],
)
```

**Card:**
```dart
Card(
  child: Padding(
    padding: EdgeInsets.all(16.0),
    child: Text('Card Content'),
  ),
)
```

### 4. Stateless vs Stateful Widgets

**StatelessWidget:**
```dart
class CounterDisplay extends StatelessWidget {
  final int count;
  
  const CounterDisplay({super.key, required this.count});
  
  @override
  Widget build(BuildContext context) {
    return Text('Count: $count');
  }
}
```

**StatefulWidget:**
```dart
class Counter extends StatefulWidget {
  const Counter({super.key});
  
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;
  
  void _increment() {
    setState(() {
      _count++;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Count: $_count'),
        ElevatedButton(
          onPressed: _increment,
          child: Text('Increment'),
        ),
      ],
    );
  }
}
```

### 5. Navigation

**Basic Navigation:**
```dart
// Navigate to new screen
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => SecondScreen()),
);

// Go back
Navigator.pop(context);
```

**Named Routes:**
```dart
// Define routes
MaterialApp(
  routes: {
    '/': (context) => HomeScreen(),
    '/details': (context) => DetailsScreen(),
  },
);

// Navigate using named route
Navigator.pushNamed(context, '/details');
```

---

## Frontend Development with Flutter

### 1. Project Structure Setup

```
frontend/lib/
├── main.dart                    # App entry point
├── models/
│   ├── stock.dart              # Stock model
│   ├── mutual_fund.dart        # Mutual fund model
│   └── stock_trend.dart        # Stock trend model
├── services/
│   └── api_service.dart        # API communication
├── providers/
│   └── finance_provider.dart   # State management
└── screens/
    ├── home_screen.dart        # Home screen
    ├── stocks_screen.dart       # Stocks list
    ├── add_stock_screen.dart    # Add stock form
    ├── mutual_funds_screen.dart # Mutual funds list
    └── stock_chart_screen.dart  # Stock chart
```

### 2. Creating Data Models

#### Stock Model (models/stock.dart)
```dart
class Stock {
  final int id;
  final String symbol;
  final String name;
  final String sector;
  final double quantity;
  final double buyPrice;
  final double currentPrice;
  final double sixthHighestPrice;
  final double sixthLowestPrice;
  final DateTime? lastFetchedDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  Stock({
    required this.id,
    required this.symbol,
    required this.name,
    this.sector = '',
    required this.quantity,
    required this.buyPrice,
    required this.currentPrice,
    this.sixthHighestPrice = 0.0,
    this.sixthLowestPrice = 0.0,
    this.lastFetchedDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Stock.fromJson(Map<String, dynamic> json) {
    return Stock(
      id: json['id'],
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      sector: json['sector'] ?? '',
      quantity: json['quantity']?.toDouble() ?? 0.0,
      buyPrice: json['average_buy_price']?.toDouble() ?? 
                json['buy_price']?.toDouble() ?? 0.0,
      currentPrice: json['current_price']?.toDouble() ?? 0.0,
      sixthHighestPrice: json['sixth_highest_price']?.toDouble() ?? 0.0,
      sixthLowestPrice: json['sixth_lowest_price']?.toDouble() ?? 0.0,
      lastFetchedDate: json['last_fetched_date'] != null 
          ? DateTime.parse(json['last_fetched_date']) 
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'name': name,
      'quantity': quantity,
      'buy_price': buyPrice,
      'current_price': currentPrice,
    };
  }
}
```

#### Mutual Fund Model (models/mutual_fund.dart)
```dart
class MutualFund {
  final int id;
  final String schemeCode;
  final String schemeName;
  final String fundHouse;
  final double quantity;
  final double nav;
  final double currentNav;
  final DateTime purchaseDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  MutualFund({
    required this.id,
    required this.schemeCode,
    required this.schemeName,
    required this.fundHouse,
    required this.quantity,
    required this.nav,
    required this.currentNav,
    required this.purchaseDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MutualFund.fromJson(Map<String, dynamic> json) {
    return MutualFund(
      id: json['id'],
      schemeCode: json['scheme_code'] ?? '',
      schemeName: json['scheme_name'] ?? '',
      fundHouse: json['fund_house'] ?? '',
      quantity: json['quantity']?.toDouble() ?? 0.0,
      nav: json['nav']?.toDouble() ?? 0.0,
      currentNav: json['current_nav']?.toDouble() ?? 0.0,
      purchaseDate: json['purchase_date'] != null 
          ? DateTime.parse(json['purchase_date']) 
          : DateTime.now(),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scheme_code': schemeCode,
      'scheme_name': schemeName,
      'fund_house': fundHouse,
      'quantity': quantity,
      'nav': nav,
      'current_nav': currentNav,
      'purchase_date': purchaseDate.toIso8601String(),
    };
  }
}
```

### 3. API Service

#### Create API Service (services/api_service.dart)
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/stock.dart';
import '../models/mutual_fund.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8080/api/v1';

  // Stock APIs
  static Future<List<Stock>> getStocks() async {
    final response = await http.get(Uri.parse('$baseUrl/stocks'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => Stock.fromJson(json)).toList();
    }
    throw Exception('Failed to load stocks');
  }

  static Future<Stock> createStock(Stock stock) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stocks'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(stock.toJson()),
    );
    if (response.statusCode == 201) {
      return Stock.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to create stock');
  }

  static Future<Stock> updateStock(int id, Stock stock) async {
    final response = await http.put(
      Uri.parse('$baseUrl/stocks/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(stock.toJson()),
    );
    if (response.statusCode == 200) {
      return Stock.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to update stock');
  }

  static Future<void> deleteStock(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/stocks/$id'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete stock');
    }
  }

  // Mutual Fund APIs
  static Future<List<MutualFund>> getMutualFunds() async {
    final response = await http.get(Uri.parse('$baseUrl/mutualfunds'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => MutualFund.fromJson(json)).toList();
    }
    throw Exception('Failed to load mutual funds');
  }

  static Future<MutualFund> createMutualFund(MutualFund mf) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mutualfunds'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(mf.toJson()),
    );
    if (response.statusCode == 201) {
      return MutualFund.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to create mutual fund');
  }

  // Portfolio API
  static Future<Map<String, dynamic>> getPortfolioSummary() async {
    final response = await http.get(Uri.parse('$baseUrl/portfolio/summary'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load portfolio summary');
  }
}
```

### 4. State Management with Provider

#### What is Provider?
Provider is Flutter's recommended state management solution. It makes it easy to manage and share state across your app.

#### Add Provider Dependency
```yaml
# In pubspec.yaml
dependencies:
  provider: ^6.1.1
```

#### Create Finance Provider (providers/finance_provider.dart)
```dart
import 'package:flutter/foundation.dart';
import '../models/stock.dart';
import '../models/mutual_fund.dart';
import '../services/api_service.dart';

class FinanceProvider with ChangeNotifier {
  List<Stock> _stocks = [];
  List<MutualFund> _mutualFunds = [];
  Map<String, dynamic> _portfolioSummary = {};
  bool _isLoading = false;
  String? _error;

  List<Stock> get stocks => _stocks;
  List<MutualFund> get mutualFunds => _mutualFunds;
  Map<String, dynamic> get portfolioSummary => _portfolioSummary;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadStocks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _stocks = await ApiService.getStocks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMutualFunds() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _mutualFunds = await ApiService.getMutualFunds();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPortfolioSummary() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _portfolioSummary = await ApiService.getPortfolioSummary();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addStock(Stock stock) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.createStock(stock);
      await loadStocks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteStock(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.deleteStock(id);
      await loadStocks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

### 5. Building Screens

#### Home Screen (screens/home_screen.dart)
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import 'stocks_screen.dart';
import 'mutual_funds_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FinanceProvider>().loadPortfolioSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Tracker'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<FinanceProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final summary = provider.portfolioSummary;
          final totalInvested = (summary['total_invested'] ?? 0.0).toDouble();
          final currentValue = (summary['current_value'] ?? 0.0).toDouble();
          final profitLoss = (summary['profit_loss'] ?? 0.0).toDouble();
          final profitLossPercentage = (summary['profit_loss_percentage'] ?? 0.0).toDouble();

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Portfolio Summary',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryRow('Total Invested', '₹${totalInvested.toStringAsFixed(2)}'),
                        const SizedBox(height: 8),
                        _buildSummaryRow('Current Value', '₹${currentValue.toStringAsFixed(2)}'),
                        const SizedBox(height: 8),
                        _buildSummaryRow(
                          'Profit/Loss',
                          '₹${profitLoss.toStringAsFixed(2)}',
                          profitLoss >= 0 ? Colors.green : Colors.red,
                        ),
                        const SizedBox(height: 8),
                        _buildSummaryRow(
                          'Profit/Loss %',
                          '${profitLossPercentage.toStringAsFixed(2)}%',
                          profitLoss >= 0 ? Colors.green : Colors.red,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Manage Your Investments',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildNavigationCard(
                        context,
                        'Stocks',
                        Icons.show_chart,
                        Colors.blue,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const StocksScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildNavigationCard(
                        context,
                        'Mutual Funds',
                        Icons.account_balance,
                        Colors.purple,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const MutualFundsScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, [Color? valueColor]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

#### Stocks Screen (screens/stocks_screen.dart)
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import '../models/stock.dart';
import 'add_stock_screen.dart';

class StocksScreen extends StatefulWidget {
  const StocksScreen({super.key});

  @override
  State<StocksScreen> createState() => _StocksScreenState();
}

class _StocksScreenState extends State<StocksScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FinanceProvider>().loadStocks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stocks'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddStockScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<FinanceProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.stocks.isEmpty) {
            return const Center(child: Text('No stocks found'));
          }

          return ListView.builder(
            itemCount: provider.stocks.length,
            itemBuilder: (context, index) {
              final stock = provider.stocks[index];
              return _buildStockCard(stock, provider);
            },
          );
        },
      ),
    );
  }

  Widget _buildStockCard(Stock stock, FinanceProvider provider) {
    final profitLoss = (stock.currentPrice - stock.buyPrice) * stock.quantity;
    final profitLossPercentage = ((stock.currentPrice - stock.buyPrice) / stock.buyPrice) * 100;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        title: Text(
          stock.symbol,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(stock.name),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${stock.currentPrice.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${profitLossPercentage.toStringAsFixed(2)}%',
              style: TextStyle(
                color: profitLoss >= 0 ? Colors.green : Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
        onTap: () {
          // Navigate to stock details
        },
      ),
    );
  }
}
```

### 6. Main App Setup

#### Update main.dart
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/finance_provider.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => FinanceProvider(),
      child: MaterialApp(
        title: 'Finance Tracker',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
```

---

## Database Design and Integration

### 1. Database Schema Design

#### Understanding Relational Databases
A relational database organizes data into tables with relationships between them. For our finance tracker, we need:

**Tables:**
1. **stocks**: Stock information
2. **transactions**: Buy/sell transactions
3. **mutual_funds**: Mutual fund investments
4. **portfolios**: Portfolio summaries

#### ER Diagram
```
stocks (1) ----< (many) transactions
mutual_funds (standalone)
portfolios (standalone)
```

### 2. Advanced Database Operations

#### Relationships in GORM
```go
// One-to-Many: Stock has many Transactions
type Stock struct {
    ID           uint          `json:"id" gorm:"primaryKey"`
    Symbol       string        `json:"symbol"`
    Transactions []Transaction `json:"transactions" gorm:"foreignKey:StockID"`
}

type Transaction struct {
    ID     uint   `json:"id" gorm:"primaryKey"`
    StockID uint   `json:"stock_id" gorm:"not null;index"`
    Stock  Stock  `json:"stock" gorm:"foreignKey:StockID"`
}
```

#### Querying with Relationships
```go
// Get stock with transactions
var stock models.Stock
db.Preload("Transactions").First(&stock, 1)

// Get all stocks with their transactions
var stocks []models.Stock
db.Preload("Transactions").Find(&stocks)
```

#### Complex Queries
```go
// Join query
var results []struct {
    Symbol string
    TotalQuantity float64
}
db.Model(&models.Transaction{}).
    Select("stocks.symbol, SUM(transactions.quantity) as total_quantity").
    Joins("JOIN stocks ON stocks.id = transactions.stock_id").
    Group("stocks.symbol").
    Scan(&results)
```

### 3. Database Migrations

#### Manual Migration
```go
func migrateDatabase(db *gorm.DB) error {
    // Create tables
    if err := db.AutoMigrate(&models.Stock{}); err != nil {
        return err
    }
    
    // Add indexes
    if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_stocks_symbol ON stocks(symbol)").Error; err != nil {
        return err
    }
    
    return nil
}
```

#### Seed Data
```go
func seedDatabase(db *gorm.DB) error {
    // Check if data already exists
    var count int64
    db.Model(&models.Stock{}).Count(&count)
    if count > 0 {
        return nil
    }
    
    // Add sample data
    stocks := []models.Stock{
        {Symbol: "AAPL", Name: "Apple Inc.", CurrentPrice: 150.50},
        {Symbol: "GOOGL", Name: "Alphabet Inc.", CurrentPrice: 2800.00},
    }
    
    return db.Create(&stocks).Error
}
```

---

## API Development and Integration

### 1. RESTful API Design

#### REST Principles
- **Resource-based**: URLs represent resources
- **HTTP Methods**: GET (read), POST (create), PUT (update), DELETE (remove)
- **Stateless**: Each request contains all needed information
- **JSON Format**: Standard data exchange format

#### API Endpoints Design
```
GET    /api/v1/stocks           - Get all stocks
POST   /api/v1/stocks           - Create stock
GET    /api/v1/stocks/:id       - Get specific stock
PUT    /api/v1/stocks/:id       - Update stock
DELETE /api/v1/stocks/:id       - Delete stock

POST   /api/v1/transactions/buy - Create buy transaction
POST   /api/v1/transactions/sell - Create sell transaction

GET    /api/v1/portfolio/summary - Get portfolio summary
```

### 2. Advanced API Features

#### Pagination
```go
func (h *Handler) GetStocks(c *gin.Context) {
    page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
    pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "10"))
    
    offset := (page - 1) * pageSize
    
    var stocks []models.Stock
    h.DB.Offset(offset).Limit(pageSize).Find(&stocks)
    
    c.JSON(200, gin.H{
        "data": stocks,
        "page": page,
        "page_size": pageSize,
    })
}
```

#### Filtering and Sorting
```go
func (h *Handler) GetStocks(c *gin.Context) {
    query := h.DB.Model(&models.Stock{})
    
    // Filter by sector
    if sector := c.Query("sector"); sector != "" {
        query = query.Where("sector = ?", sector)
    }
    
    // Sort
    sortBy := c.DefaultQuery("sort_by", "created_at")
    sortOrder := c.DefaultQuery("sort_order", "desc")
    query = query.Order(sortBy + " " + sortOrder)
    
    var stocks []models.Stock
    query.Find(&stocks)
    
    c.JSON(200, stocks)
}
```

#### Validation
```go
type CreateStockRequest struct {
    Symbol string `json:"symbol" binding:"required,min=1,max=10"`
    Name   string `json:"name" binding:"required"`
    Price  float64 `json:"price" binding:"required,gt=0"`
}

func (h *Handler) CreateStock(c *gin.Context) {
    var req CreateStockRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }
    // ... rest of the code
}
```

### 3. External API Integration

#### Yahoo Finance API Integration
```go
func fetchYahooFinancePrice(symbol string) (float64, error) {
    suffixes := []string{"", ".NS", ".BO"}
    client := &http.Client{Timeout: 8 * time.Second}

    for _, suffix := range suffixes {
        url := fmt.Sprintf("https://query1.finance.yahoo.com/v8/finance/chart/%s%s?interval=1d&range=1d", symbol, suffix)
        req, err := http.NewRequest("GET", url, nil)
        if err != nil {
            continue
        }
        req.Header.Set("User-Agent", "Mozilla/5.0")

        resp, err := client.Do(req)
        if err != nil || resp.StatusCode != http.StatusOK {
            if resp != nil {
                resp.Body.Close()
            }
            continue
        }
        defer resp.Body.Close()

        var result struct {
            Chart struct {
                Result []struct {
                    Meta struct {
                        RegularMarketPrice float64 `json:"regularMarketPrice"`
                    } `json:"meta"`
                } `json:"result"`
                Error interface{} `json:"error"`
            } `json:"chart"`
        }

        if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
            continue
        }
        if result.Chart.Error != nil {
            continue
        }
        if len(result.Chart.Result) > 0 && result.Chart.Result[0].Meta.RegularMarketPrice > 0 {
            return result.Chart.Result[0].Meta.RegularMarketPrice, nil
        }
    }
    return 0, fmt.Errorf("price not found for %s", symbol)
}
```

---

## State Management in Flutter

### 1. Understanding State Management

State management is about how you handle and share data across your app. Flutter provides several approaches:

- **setState**: Simple, local state
- **InheritedWidget**: Built-in state sharing
- **Provider**: Recommended solution, built on InheritedWidget
- **Riverpod**: Modern alternative to Provider
- **Bloc**: More complex, event-driven state management

### 2. Provider Deep Dive

#### ChangeNotifier
The core of Provider is ChangeNotifier, which notifies listeners when data changes.

```dart
class Counter with ChangeNotifier {
  int _count = 0;
  
  int get count => _count;
  
  void increment() {
    _count++;
    notifyListeners(); // Important: Notify listeners
  }
}
```

#### Provider Setup
```dart
void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => Counter(),
      child: MyApp(),
    ),
  );
}
```

#### Consuming Provider
```dart
// Using Consumer
Consumer<Counter>(
  builder: (context, counter, child) {
    return Text('Count: ${counter.count}');
  },
)

// Using context.read (for callbacks)
ElevatedButton(
  onPressed: () => context.read<Counter>().increment(),
  child: Text('Increment'),
)

// Using context.watch (for building)
Text('Count: ${context.watch<Counter>().count}')
```

### 3. Advanced State Management

#### Multiple Providers
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => FinanceProvider()),
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
  ],
  child: MyApp(),
)
```

#### Async State Management
```dart
class DataProvider with ChangeNotifier {
  List<Item> _items = [];
  bool _isLoading = false;
  String? _error;
  
  List<Item> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  Future<void> loadItems() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _items = await apiService.fetchItems();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

---

## Building the User Interface

### 1. Material Design Principles

Flutter uses Material Design, Google's design system. Key concepts:

- **Widgets**: Building blocks of UI
- **Themes**: Material Design themes
- **Responsive Design**: Adapting to different screen sizes
- **Accessibility**: Making apps usable by everyone

### 2. Common UI Patterns

#### Forms
```dart
class AddStockForm extends StatefulWidget {
  @override
  State<AddStockForm> createState() => _AddStockFormState();
}

class _AddStockFormState extends State<AddStockForm> {
  final _formKey = GlobalKey<FormState>();
  final _symbolController = TextEditingController();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _symbolController,
            decoration: InputDecoration(labelText: 'Symbol'),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a symbol';
              }
              return null;
            },
          ),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(labelText: 'Name'),
          ),
          TextFormField(
            controller: _priceController,
            decoration: InputDecoration(labelText: 'Price'),
            keyboardType: TextInputType.number,
          ),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                // Submit form
              }
            },
            child: Text('Submit'),
          ),
        ],
      ),
    );
  }
}
```

#### Lists with Cards
```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(Icons.star),
        title: Text(items[index].title),
        subtitle: Text(items[index].subtitle),
        trailing: IconButton(
          icon: Icon(Icons.delete),
          onPressed: () {
            // Delete item
          },
        ),
      ),
    );
  },
)
```

#### Dialogs
```dart
ElevatedButton(
  onPressed: () {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Delete'),
        content: Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Delete item
            },
            child: Text('Delete'),
          ),
        ],
      ),
    );
  },
  child: Text('Delete'),
)
```

### 3. Responsive Design

#### Using LayoutBuilder
```dart
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth > 600) {
      return _buildWideLayout();
    } else {
      return _buildNarrowLayout();
    }
  },
)
```

#### Using MediaQuery
```dart
final screenWidth = MediaQuery.of(context).size.width;
final screenHeight = MediaQuery.of(context).size.height;

if (screenWidth > 600) {
  // Tablet or desktop layout
} else {
  // Mobile layout
}
```

---

## Testing and Debugging

### 1. Go Testing

#### Unit Tests
```go
// handlers_test.go
package handlers

import (
    "testing"
    "github.com/stretchr/testify/assert"
)

func TestCalculateProfitLoss(t *testing.T) {
    buyPrice := 100.0
    currentPrice := 150.0
    quantity := 10.0
    
    profitLoss := (currentPrice - buyPrice) * quantity
    expected := 500.0
    
    assert.Equal(t, expected, profitLoss)
}
```

#### Running Tests
```bash
go test ./...
go test -v ./handlers
```

### 2. Flutter Testing

#### Widget Tests
```dart
testWidgets('HomeScreen displays portfolio summary', (WidgetTester tester) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => FinanceProvider(),
      child: MaterialApp(home: HomeScreen()),
    ),
  );

  expect(find.text('Portfolio Summary'), findsOneWidget);
});
```

#### Running Tests
```bash
flutter test
flutter test test/home_screen_test.dart
```

### 3. Debugging Techniques

#### Go Debugging
```bash
# Using delve debugger
dlv debug main.go

# Set breakpoints
# Step through code
# Inspect variables
```

#### Flutter Debugging
```bash
# Run in debug mode
flutter run

# Open DevTools
flutter pub global activate devtools
flutter pub global run devtools
```

#### Logging
```go
// Go logging
log.Printf("Processing stock: %s", stock.Symbol)
log.Printf("Error: %v", err)
```

```dart
// Flutter logging
print('Debug message');
debugPrint('Detailed debug info');
```

---

## Deployment and Best Practices

### 1. Go Deployment

#### Building for Production
```bash
# Build executable
go build -o financetracker main.go

# Run executable
./financetracker
```

#### Docker Deployment
```dockerfile
# Dockerfile
FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY . .
RUN go mod download
RUN go build -o main main.go

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/main .
EXPOSE 8080
CMD ["./main"]
```

### 2. Flutter Deployment

#### Building for Different Platforms
```bash
# Android
flutter build apk

# iOS
flutter build ios

# Web
flutter build web
```

#### Web Deployment
```bash
# Build web version
flutter build web

# Deploy to any web server
# The build/web folder contains the static files
```

### 3. Best Practices

#### Go Best Practices
- Use meaningful variable names
- Handle errors properly
- Write unit tests
- Use goroutines for concurrent operations
- Keep functions small and focused

#### Flutter Best Practices
- Use const constructors where possible
- Split widgets into smaller components
- Use provider for state management
- Handle loading and error states
- Write widget tests

#### Security Best Practices
- Never hardcode credentials
- Use environment variables
- Validate input on both client and server
- Use HTTPS in production
- Implement authentication

---

## Advanced Topics

### 1. Real-time Updates with WebSockets

#### Go WebSocket Implementation
```go
import (
    "github.com/gin-gonic/gin"
    "github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
    CheckOrigin: func(r *http.Request) bool {
        return true
    },
}

func handleWebSocket(c *gin.Context) {
    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        return
    }
    defer conn.Close()

    for {
        // Handle messages
    }
}
```

### 2. Authentication and Authorization

#### JWT Authentication
```go
import (
    "github.com/dgrijalva/jwt-go"
)

func generateToken(userID uint) (string, error) {
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
        "user_id": userID,
        "exp":     time.Now().Add(time.Hour * 24).Unix(),
    })
    
    return token.SignedString([]byte("secret"))
}
```

### 3. Data Visualization

#### Using FL Chart in Flutter
```dart
import 'package:fl_chart/fl_chart.dart';

LineChart(
  LineChartData(
    lineBarsData: [
      LineChartBarData(
        spots: [
          FlSpot(0, 1),
          FlSpot(1, 3),
          FlSpot(2, 2),
          FlSpot(3, 5),
        ],
      ),
    ],
  ),
)
```

### 4. Performance Optimization

#### Go Performance
- Use connection pooling for database
- Implement caching
- Use goroutines for concurrent operations
- Profile with pprof

#### Flutter Performance
- Use const widgets
- Avoid rebuilding unnecessary widgets
- Use ListView.builder for long lists
- Implement lazy loading

---

## Conclusion

### What You've Learned
- Go programming fundamentals and web development
- Flutter framework and cross-platform development
- RESTful API design and implementation
- Database design with PostgreSQL and GORM
- State management with Provider
- Building responsive user interfaces
- Testing and debugging techniques
- Deployment strategies

### Next Steps
1. **Expand Features**: Add user authentication, more charts, export functionality
2. **Improve UI**: Add animations, better layouts, dark mode
3. **Performance**: Implement caching, optimize database queries
4. **Testing**: Add more comprehensive tests
5. **Deployment**: Deploy to cloud platforms (AWS, GCP, Heroku)

### Resources
- [Go Documentation](https://golang.org/doc/)
- [Flutter Documentation](https://flutter.dev/docs)
- [GORM Documentation](https://gorm.io/docs/)
- [Provider Package](https://pub.dev/packages/provider)

### Practice Projects
1. Build a todo app with Flutter and Go
2. Create a weather app with API integration
3. Develop a chat application with WebSockets
4. Build an e-commerce app with payment integration

---

## Troubleshooting Guide

### Common Go Issues

#### Import Path Issues
```bash
# If you get import errors, run:
go mod tidy
go mod download
```

#### Database Connection Issues
```bash
# Check PostgreSQL is running:
brew services list  # macOS
sudo systemctl status postgresql  # Linux

# Test connection:
psql -U finance -d financetracker
```

### Common Flutter Issues

#### Dependency Issues
```bash
# Clean and reinstall dependencies
flutter clean
flutter pub get
```

#### Build Issues
```bash
# Update Flutter
flutter upgrade

# Doctor to check issues
flutter doctor
```

#### iOS Build Issues (macOS only)
```bash
# Install CocoaPods
sudo gem install cocoapods

# Update pods
cd ios
pod install
cd ..
```

---

## Final Project Checklist

### Backend
- [ ] Database connection working
- [ ] All CRUD operations implemented
- [ ] API endpoints tested
- [ ] Error handling implemented
- [ ] External API integration working
- [ ] CORS configured
- [ ] Input validation added

### Frontend
- [ ] All screens implemented
- [ ] State management working
- [ ] API integration complete
- [ ] Forms with validation
- [ ] Loading states handled
- [ ] Error states handled
- [ ] Navigation working
- [ ] Responsive design

### Testing
- [ ] Unit tests written
- [ ] Integration tests written
- [ ] Widget tests written
- [ ] Manual testing completed

### Deployment
- [ ] Production build tested
- [ ] Environment variables configured
- [ ] Database migrations tested
- [ ] Security measures implemented

---

Congratulations! You've completed the FinanceTracker development training guide. You now have the skills to build full-stack applications using Go and Flutter. Keep practicing and building to reinforce your learning!
