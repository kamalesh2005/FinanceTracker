import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/currency_format.dart';
import '../widgets/auth_app_bar_actions.dart';
import 'stocks_screen.dart';
import 'mutual_funds_screen.dart';
import 'admin_screen.dart';
import 'configure_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AuthProvider>().loadPreferences();
      if (!mounted) return;
      await context.read<FinanceProvider>().loadPortfolioSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final watchList = auth.useAsStockWatchList;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Tracker'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  auth.user?.displayName ?? '',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Configure',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConfigureScreen()),
                );
                if (!context.mounted) return;
                await context.read<FinanceProvider>().loadPortfolioSummary();
              },
            ),
          ],
        ),
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
          final profitLossPercentage =
              (summary['profit_loss_percentage'] ?? 0.0).toDouble();
          final stockCount = (summary['stock_count'] as num?)?.toInt() ?? 0;
          final bySource = (summary['by_source'] as List<dynamic>?) ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  watchList ? 'Watch List Summary' : 'Portfolio Summary',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: watchList
                          ? [
                              _buildSummaryRow(
                                'Number of Stocks',
                                stockCount.toString(),
                              ),
                            ]
                          : [
                              _buildSummaryRow(
                                'Total Invested',
                                formatInr(totalInvested),
                              ),
                              const SizedBox(height: 8),
                              _buildSummaryRow(
                                'Current Value',
                                formatInr(currentValue),
                              ),
                              const SizedBox(height: 8),
                              _buildSummaryRow(
                                'Profit/Loss',
                                formatInr(profitLoss),
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
                if (!watchList) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'By source',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Stock holdings only (mutual funds included in totals above).',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  if (bySource.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No stock holdings by source'),
                      ),
                    )
                  else
                    Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Source')),
                            DataColumn(label: Text('Invested')),
                            DataColumn(label: Text('Current')),
                            DataColumn(label: Text('P/L')),
                            DataColumn(label: Text('P/L %')),
                          ],
                          rows: bySource.map((row) {
                            final map = row as Map<String, dynamic>;
                            final source = map['source'] as String? ?? '-';
                            final invested =
                                (map['total_invested'] ?? 0.0).toDouble();
                            final current =
                                (map['current_value'] ?? 0.0).toDouble();
                            final pl = (map['profit_loss'] ?? 0.0).toDouble();
                            final plPct =
                                (map['profit_loss_percentage'] ?? 0.0).toDouble();
                            final plColor = pl >= 0 ? Colors.green : Colors.red;

                            return DataRow(
                              cells: [
                                DataCell(Text(
                                  source,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                )),
                                DataCell(Text(formatInr(invested))),
                                DataCell(Text(formatInr(current))),
                                DataCell(Text(
                                  formatInr(pl),
                                  style: TextStyle(color: plColor),
                                )),
                                DataCell(Text(
                                  '${plPct.toStringAsFixed(2)}%',
                                  style: TextStyle(color: plColor),
                                )),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                ],
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
                          MaterialPageRoute(
                            builder: (context) => const StocksScreen(),
                          ),
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
                          MaterialPageRoute(
                            builder: (context) => const MutualFundsScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (auth.isAdmin) ...[
                  const SizedBox(height: 16),
                  _buildNavigationCard(
                    context,
                    'Admin',
                    Icons.admin_panel_settings,
                    Colors.teal,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AdminScreen(),
                      ),
                    ),
                  ),
                ],
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
