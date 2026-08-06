import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import '../models/mutual_fund.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import 'add_mutual_fund_screen.dart';

class MutualFundsScreen extends StatefulWidget {
  const MutualFundsScreen({super.key});

  @override
  State<MutualFundsScreen> createState() => _MutualFundsScreenState();
}

class _MutualFundsScreenState extends State<MutualFundsScreen> {
  bool _isTableView = true;

  String? _selectedScheme;
  String? _selectedAccount;

  static const String _manualAddAccount = 'Manual Add';
  /// Below this width, prefer card view (table is too dense for phones).
  static const double _cardViewBreakpoint = 700;
  /// Below this width, slim the AppBar (icon Add).
  static const double _narrowAppBarBreakpoint = 600;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FinanceProvider>().loadMutualFunds();
    });
  }

  void _openAddFund() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddMutualFundScreen()),
    ).then((_) => context.read<FinanceProvider>().loadMutualFunds());
  }

  bool get _hasActiveFilters =>
      _selectedScheme != null || _selectedAccount != null;

  void _clearFilters() {
    setState(() {
      _selectedScheme = null;
      _selectedAccount = null;
    });
  }

  String _schemeKey(MutualFund mf) => mf.displayName;

  String _accountKey(MutualFund mf) {
    final source = mf.source.trim();
    return source.isEmpty ? _manualAddAccount : source;
  }

  List<String> _schemeOptions(List<MutualFund> funds) {
    final schemes = funds.map(_schemeKey).where((s) => s.isNotEmpty).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return schemes;
  }

  List<String> _accountOptions(List<MutualFund> funds) {
    final accounts = funds.map(_accountKey).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return accounts;
  }

  List<MutualFund> _filteredFunds(FinanceProvider provider) {
    return provider.mutualFunds.where((mf) {
      if (_selectedScheme != null && _schemeKey(mf) != _selectedScheme) {
        return false;
      }
      if (_selectedAccount != null && _accountKey(mf) != _selectedAccount) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final narrowAppBar = screenWidth < _narrowAppBarBreakpoint;
    final showTableView = screenWidth >= _cardViewBreakpoint && _isTableView;
    final canToggleView = screenWidth >= _cardViewBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Mutual Funds'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            if (narrowAppBar)
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Fund',
                onPressed: _openAddFund,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: OutlinedButton.icon(
                  onPressed: _openAddFund,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Fund'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            if (canToggleView)
              IconButton(
                icon: Icon(showTableView ? Icons.view_module : Icons.table_rows),
                onPressed: () {
                  setState(() {
                    _isTableView = !_isTableView;
                  });
                },
                tooltip: showTableView ? 'Card view' : 'Table view',
              ),
          ],
        ),
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

          final funds = _filteredFunds(provider);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFilterBar(provider),
              Expanded(
                child: funds.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('No mutual funds match filters'),
                            if (_hasActiveFilters) ...[
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _clearFilters,
                                child: const Text('Clear filters'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : showTableView
                        ? _buildMutualFundTable(provider, funds)
                        : ListView.builder(
                            itemCount: funds.length,
                            itemBuilder: (context, index) {
                              final mf = funds[index];
                              return _buildMutualFundCard(context, mf, provider);
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar(FinanceProvider provider) {
    final schemeOptions = _schemeOptions(provider.mutualFunds);
    final accountOptions = _accountOptions(provider.mutualFunds);
    final narrow = MediaQuery.sizeOf(context).width < _cardViewBreakpoint;
    final activeCount = [
      _selectedScheme,
      _selectedAccount,
    ].whereType<String>().length;

    final schemeMenu = _buildFilterMenu(
      label: 'Scheme',
      selected: _selectedScheme,
      options: schemeOptions,
      onChanged: (next) => setState(() => _selectedScheme = next),
    );
    final accountMenu = _buildFilterMenu(
      label: 'Account',
      selected: _selectedAccount,
      options: accountOptions,
      onChanged: (next) => setState(() => _selectedAccount = next),
    );
    final clearButton = _hasActiveFilters
        ? TextButton(
            onPressed: _clearFilters,
            child: const Text('Clear'),
          )
        : null;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: narrow
            ? Row(
                children: [
                  _buildCollapsedFiltersButton(
                    activeCount: activeCount,
                    onPressed: () => _showCollapsedFiltersSheet(
                      schemeOptions: schemeOptions,
                      accountOptions: accountOptions,
                    ),
                  ),
                  const Spacer(),
                  if (clearButton != null) clearButton,
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  schemeMenu,
                  accountMenu,
                  if (clearButton != null) clearButton,
                ],
              ),
      ),
    );
  }

  Widget _buildCollapsedFiltersButton({
    required int activeCount,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = activeCount > 0;
    return IconButton(
      tooltip: active ? 'Filters ($activeCount)' : 'Filters',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: active ? colorScheme.primary : colorScheme.onSurface,
        side: BorderSide(
          color: active ? colorScheme.primary : colorScheme.outline,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      icon: Badge(
        isLabelVisible: active,
        label: Text('$activeCount'),
        child: const Icon(Icons.filter_list),
      ),
    );
  }

  Future<void> _showCollapsedFiltersSheet({
    required List<String> schemeOptions,
    required List<String> accountOptions,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void apply(VoidCallback update) {
              setState(update);
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Filters',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _buildFilterMenu(
                        label: 'Scheme',
                        selected: _selectedScheme,
                        options: schemeOptions,
                        onChanged: (next) =>
                            apply(() => _selectedScheme = next),
                      ),
                      const SizedBox(height: 8),
                      _buildFilterMenu(
                        label: 'Account',
                        selected: _selectedAccount,
                        options: accountOptions,
                        onChanged: (next) =>
                            apply(() => _selectedAccount = next),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterMenu({
    required String label,
    required String? selected,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final active = selected != null;
    final buttonLabel = active ? '$label: $selected' : label;
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Filter by $label',
      onSelected: (value) {
        onChanged(selected == value ? null : value);
      },
      itemBuilder: (context) {
        if (options.isEmpty) {
          return [
            const PopupMenuItem<String>(
              enabled: false,
              child: Text('No options'),
            ),
          ];
        }
        return options
            .map(
              (option) => CheckedPopupMenuItem<String>(
                value: option,
                checked: selected == option,
                child: Text(option),
              ),
            )
            .toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? colorScheme.primary : colorScheme.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list,
              size: 16,
              color: active ? colorScheme.primary : colorScheme.onSurface,
            ),
            const SizedBox(width: 6),
            Text(
              buttonLabel,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: active ? colorScheme.primary : colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMutualFundCard(
      BuildContext context, MutualFund mf, FinanceProvider provider) {
    final invested = mf.nav * mf.quantity;
    final current = mf.currentNav * mf.quantity;
    final profitLoss = current - invested;
    final profitLossPercentage = invested > 0 ? (profitLoss / invested) * 100 : 0.0;

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
                    mf.displayName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
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
                            builder: (context) =>
                                AddMutualFundScreen(mutualFund: mf),
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
              'Account: ${_accountKey(mf)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
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

  Widget _buildMutualFundTable(
      FinanceProvider provider, List<MutualFund> funds) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Scheme')),
            DataColumn(label: Text('Account')),
            DataColumn(label: Text('Code')),
            DataColumn(label: Text('Units')),
            DataColumn(label: Text('NAV')),
            DataColumn(label: Text('Current NAV')),
            DataColumn(label: Text('P/L')),
            DataColumn(label: Text('P/L %')),
            DataColumn(label: Text('Actions')),
          ],
          rows: funds.map((mf) {
            final invested = mf.nav * mf.quantity;
            final current = mf.currentNav * mf.quantity;
            final profitLoss = current - invested;
            final profitLossPercentage =
                invested > 0 ? (profitLoss / invested) * 100 : 0.0;
            final account = _accountKey(mf);

            return DataRow(
              cells: [
                DataCell(Text(
                  mf.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )),
                DataCell(Text(account)),
                DataCell(Text(mf.schemeCode)),
                DataCell(Text(mf.quantity.toStringAsFixed(2))),
                DataCell(Text(formatInr(mf.nav))),
                DataCell(Text(formatInr(mf.currentNav))),
                DataCell(Text(
                  formatInr(profitLoss),
                  style: TextStyle(
                      color: profitLoss >= 0 ? Colors.green : Colors.red),
                )),
                DataCell(Text(
                  '${profitLossPercentage.toStringAsFixed(2)}%',
                  style: TextStyle(
                      color: profitLoss >= 0 ? Colors.green : Colors.red),
                )),
                DataCell(Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                AddMutualFundScreen(mutualFund: mf),
                          ),
                        ).then((_) => provider.loadMutualFunds());
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      onPressed: () =>
                          _showDeleteDialog(context, mf.id, provider),
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

  void _showDeleteDialog(
      BuildContext context, int id, FinanceProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Mutual Fund'),
        content:
            const Text('Are you sure you want to delete this mutual fund?'),
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
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
