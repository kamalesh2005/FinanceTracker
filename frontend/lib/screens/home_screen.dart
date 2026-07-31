import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
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
  /// Below this width, stack summary metrics in one card to save space.
  static const double _summaryCardsBreakpoint = 600;

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
        title: const AppBrandTitle('Dhan Shanti'),
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
            if (auth.isAdmin)
              IconButton(
                tooltip: 'Admin',
                icon: const Icon(Icons.admin_panel_settings),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminScreen()),
                  );
                },
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
          final byMfSource = (summary['by_mf_source'] as List<dynamic>?) ?? [];

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
                if (watchList)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryRow(
                            'Number of Stocks',
                            stockCount.toString(),
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'Number of Mutual Funds',
                            'Coming soon',
                            Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  _buildPortfolioSummary(
                    totalInvested: totalInvested,
                    currentValue: currentValue,
                    profitLoss: profitLoss,
                    profitLossPercentage: profitLossPercentage,
                  ),
                const SizedBox(height: 24),
                _buildStocksPortfolioCard(
                  watchList: watchList,
                  stockCount: stockCount,
                  bySource: bySource,
                ),
                const SizedBox(height: 16),
                _buildMutualFundsCard(
                  watchList: watchList,
                  byMfSource: byMfSource,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStocksPortfolioCard({
    required bool watchList,
    required int stockCount,
    required List<dynamic> bySource,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.show_chart,
              iconColor: Colors.blue,
              title: 'Stocks',
              onManage: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StocksScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            if (watchList)
              _buildSummaryRow('Number of Stocks', stockCount.toString())
            else if (bySource.isEmpty)
              const Text('No stock holdings by account')
            else
              _buildByAccountTable(bySource),
          ],
        ),
      ),
    );
  }

  Widget _buildMutualFundsCard({
    required bool watchList,
    required List<dynamic> byMfSource,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.account_balance,
              iconColor: Colors.purple,
              title: 'Mutual Funds',
              onManage: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MutualFundsScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            if (watchList)
              Text(
                'Coming soon',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              )
            else if (byMfSource.isEmpty)
              const Text('No mutual fund holdings by account')
            else
              _buildByAccountTable(byMfSource),
          ],
        ),
      ),
    );
  }

  Widget _buildByAccountTable(List<dynamic> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Account')),
          DataColumn(label: Text('Invested')),
          DataColumn(label: Text('Current')),
          DataColumn(label: Text('P/L')),
          DataColumn(label: Text('P/L %')),
        ],
        rows: rows.map((row) {
          final map = row as Map<String, dynamic>;
          final source = map['source'] as String? ?? '-';
          final invested = (map['total_invested'] ?? 0.0).toDouble();
          final current = (map['current_value'] ?? 0.0).toDouble();
          final pl = (map['profit_loss'] ?? 0.0).toDouble();
          final plPct = (map['profit_loss_percentage'] ?? 0.0).toDouble();
          final plColor = pl >= 0 ? Colors.green : Colors.red;

          return DataRow(
            cells: [
              DataCell(Text(
                source,
                style: const TextStyle(fontWeight: FontWeight.bold),
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
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onManage,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(
          onPressed: onManage,
          child: const Text('Manage'),
        ),
      ],
    );
  }

  Widget _buildPortfolioSummary({
    required double totalInvested,
    required double currentValue,
    required double profitLoss,
    required double profitLossPercentage,
  }) {
    final plColor = profitLoss >= 0 ? Colors.green : Colors.red;
    final metrics = <({String label, String value, Color? color})>[
      (label: 'Total Invested', value: formatInr(totalInvested), color: null),
      (label: 'Current Value', value: formatInr(currentValue), color: null),
      (label: 'Profit/Loss', value: formatInr(profitLoss), color: plColor),
      (
        label: 'Profit/Loss %',
        value: '${profitLossPercentage.toStringAsFixed(2)}%',
        color: plColor,
      ),
    ];

    final isCompact =
        MediaQuery.sizeOf(context).width < _summaryCardsBreakpoint;

    if (isCompact) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _buildSummaryRow(
                  metrics[i].label,
                  metrics[i].value,
                  metrics[i].color,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: _buildSummaryMetricCard(
              metrics[i].label,
              metrics[i].value,
              metrics[i].color,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryMetricCard(
    String label,
    String value, [
    Color? valueColor,
  ]) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
          ],
        ),
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
}
