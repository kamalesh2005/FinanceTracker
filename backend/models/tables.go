package models

func (Stock) TableName() string                { return "Global_Stocks" }
func (SymbolMapping) TableName() string        { return "Global_SymbolMappings" }
func (User) TableName() string                 { return "Global_Users" }
func (UserStock) TableName() string            { return "User_Stocks" }
func (UserStockTransaction) TableName() string { return "User_Stock_Transactions" }
func (UserConfig) TableName() string           { return "User_Config" }
func (AppConfig) TableName() string            { return "App_Config" }
func (MutualFund) TableName() string           { return "User_MutualFunds" }
func (PasswordResetOTP) TableName() string     { return "User_PasswordResetOTPs" }
func (Portfolio) TableName() string            { return "User_Portfolios" }
