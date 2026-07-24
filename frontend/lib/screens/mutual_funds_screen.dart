import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import '../models/mutual_fund.dart';
import '../utils/currency_format.dart';
import '../widgets/auth_app_bar_actions.dart';
import 'add_mutual_fund_screen.dart';

class MutualFundsScreen extends StatefulWidget {
  const MutualFundsScreen({super.key});

  @override
  State<MutualFundsScreen> createState() => _MutualFundsScreenState();
}

class _MutualFundsScreenState extends State<MutualFundsScreen> {
  bool _isTableView = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FinanceProvider>().loadMutualFunds();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mutual Funds'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            IconButton(
              icon: Icon(_isTableView ? Icons.view_module : Icons.table_rows),
              onPressed: () {
                setState(() {
                  _isTableView = !_isTableView;
                });
              },
              tooltip: _isTableView ? 'Card view' : 'Table view',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddMutualFundScreen()),
          ).then((_) => context.read<FinanceProvider>().loadMutualFunds());
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Fund'),
      ),
      body: Consumer<FinanceProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(child: Text('Error: ${provider.error}'));
          }

          if (provider.mutualFunds.isEmpty) {
            return const Center(child: Text('No mutual funds added yet'));
          }

          return _isTableView
              ? _buildMutualFundTable(provider)
              : ListView.builder(
                  itemCount: provider.mutualFunds.length,
                  itemBuilder: (context, index) {
                    final mf = provider.mutualFunds[index];
                    return _buildMutualFundCard(context, mf, provider);
                  },
                );
        },
      ),
    );
  }

  Widget _buildMutualFundCard(BuildContext context, MutualFund mf, FinanceProvider provider) {
    final invested = mf.nav * mf.quantity;
    final current = mf.currentNav * mf.quantity;
    final profitLoss = current - invested;
    final profitLossPercentage = (profitLoss / invested) * 100;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    mf.schemeName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddMutualFundScreen(mutualFund: mf),
                          ),
                        ).then((_) => provider.loadMutualFunds());
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                      onPressed: () {
                        _showDeleteDialog(context, mf.id, provider);
                      },
                    ),
                  ],
                ),
              ],
            ),
            if (mf.fundHouse.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                mf.fundHouse,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Scheme Code: ${mf.schemeCode}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoColumn('Units', mf.quantity.toStringAsFixed(2)),
                _buildInfoColumn('NAV', formatInr(mf.nav)),
                _buildInfoColumn('Current NAV', formatInr(mf.currentNav)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoColumn('Invested', formatInr(invested)),
                _buildInfoColumn(
                  'P/L',
                  formatInr(profitLoss),
                  profitLoss >= 0 ? Colors.green : Colors.red,
                ),
                _buildInfoColumn(
                  'P/L %',
                  '${profitLossPercentage.toStringAsFixed(2)}%',
                  profitLoss >= 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMutualFundTable(FinanceProvider provider) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Scheme')),
            DataColumn(label: Text('Code')),
            DataColumn(label: Text('Units')),
            DataColumn(label: Text('NAV')),
            DataColumn(label: Text('Current NAV')),
            DataColumn(label: Text('P/L')),
            DataColumn(label: Text('P/L %')),
            DataColumn(label: Text('Actions')),
          ],
          rows: provider.mutualFunds.map((mf) {
            final invested = mf.nav * mf.quantity;
            final current = mf.currentNav * mf.quantity;
            final profitLoss = current - invested;
            final profitLossPercentage = invested > 0 ? (profitLoss / invested) * 100 : 0.0;

            return DataRow(
              cells: [
                DataCell(Text(
                  mf.schemeName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )),
                DataCell(Text(mf.schemeCode)),
                DataCell(Text(mf.quantity.toStringAsFixed(2))),
                DataCell(Text(formatInr(mf.nav))),
                DataCell(Text(formatInr(mf.currentNav))),
                DataCell(Text(
                  formatInr(profitLoss),
                  style: TextStyle(color: profitLoss >= 0 ? Colors.green : Colors.red),
                )),
                DataCell(Text(
                  '${profitLossPercentage.toStringAsFixed(2)}%',
                  style: TextStyle(color: profitLoss >= 0 ? Colors.green : Colors.red),
                )),
                DataCell(Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => AddMutualFundScreen(mutualFund: mf)),
                        ).then((_) => provider.loadMutualFunds());
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      onPressed: () => _showDeleteDialog(context, mf.id, provider),
                    ),
                  ],
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, [Color? valueColor]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  void _showDeleteDialog(BuildContext context, int id, FinanceProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Mutual Fund'),
        content: const Text('Are you sure you want to delete this mutual fund?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await provider.deleteMutualFund(id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
