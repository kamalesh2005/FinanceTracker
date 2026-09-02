package models

func (Stock) TableName() string                { return "Global_Stocks" }
func (SymbolMapping) TableName() string        { return "Global_SymbolMappings" }
func (MFSchemeMapping) TableName() string      { return "Global_MF_SchemeMapping" }
func (User) TableName() string                 { return "Global_Users" }
func (UserStock) TableName() string            { return "User_Stocks" }
func (UserWatchlist) TableName() string             { return "User_Watchlist" }
func (UserScreenerStockLabel) TableName() string   { return "User_Screener_Stock_Labels" }
func (UserStockTransaction) TableName() string { return "User_Stock_Transactions" }
func (UserConfig) TableName() string           { return "User_Config" }
func (AppConfig) TableName() string            { return "App_Config" }
func (GlobalMutualFund) TableName() string     { return "Global_MutualFunds" }
func (GlobalIndex) TableName() string          { return "Global_Indices" }
func (MutualFund) TableName() string                    { return "User_MutualFunds" }
func (UserMutualFundTransaction) TableName() string     { return "User_MutualFund_Transactions" }
func (PasswordResetOTP) TableName() string     { return "User_PasswordResetOTPs" }
func (RefreshToken) TableName() string        { return "User_RefreshTokens" }
func (Portfolio) TableName() string            { return "User_Portfolios" }
func (StockDailyClose) TableName() string      { return "Global_Stock_Daily_Closes" }
func (StockDailyCloseSync) TableName() string  { return "Global_Stock_Daily_Close_Sync" }
func (StockDataImportStatus) TableName() string {
	return "Global_Stock_Data_Import_Status"
}
func (InvChChallenge) TableName() string   { return "Inv_Ch_Challenges" }
func (InvChMember) TableName() string      { return "Inv_Ch_Members" }
func (InvChHolding) TableName() string     { return "Inv_Ch_Holdings" }
func (InvChTransaction) TableName() string { return "Inv_Ch_Transactions" }
func (FFAsset) TableName() string          { return "User_FF_Assets" }
func (FFJobIncome) TableName() string      { return "User_FF_Job_Income" }
func (FFExpense) TableName() string        { return "User_FF_Expenses" }
func (FFOneTimeExpense) TableName() string { return "User_FF_OneTime_Expenses" }
func (Feedback) TableName() string        { return "User_Feedback" }
