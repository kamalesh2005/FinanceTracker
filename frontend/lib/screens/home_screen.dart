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
        Text(
          label,
          style: const TextStyle(fontSize: 16),
        ),
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
