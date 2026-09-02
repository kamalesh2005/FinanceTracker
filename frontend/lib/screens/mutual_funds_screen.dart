import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import '../models/mutual_fund.dart';
import '../models/global_index.dart';
import '../services/api_service.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import 'add_mutual_fund_screen.dart';

enum _MFSortField {
  scheme,
  return2021,
  return2022,
  return2023,
  return2024,
  return2025,
  returnYtd,
}

class MutualFundsScreen extends StatefulWidget {
  const MutualFundsScreen({super.key});

  @override
  State<MutualFundsScreen> createState() => _MutualFundsScreenState();
}

class _MutualFundsScreenState extends State<MutualFundsScreen> {
  bool _isTableView = true;

  String? _selectedScheme;
  String? _selectedAccount;
  _MFSortField _sortField = _MFSortField.scheme;
  bool _sortAsc = true;

  static const String _manualAddAccount = 'Manual Add';
  static const double _cardViewBreakpoint = 700;
  static const double _narrowAppBarBreakpoint = 600;
  static const List<int> _returnYears = [2021, 2022, 2023, 2024, 2025];
  static const double _headerHeight = 58;
  static const double _rowHeight = 48;
  static const List<String> _allColumns = [
    'Scheme',
    'Code',
    'Units',
    'NAV',
    'Current NAV',
    'P/L',
    'P/L %',
    'FY21',
    'FY22',
    'FY23',
    'FY24',
    'FY25',
    'FY26 YTD',
    'Actions',
  ];
  static const List<String> _frozenColumnNames = ['Scheme'];

  /// Maps legacy calendar-year column keys to FY labels.
  static const Map<String, String> _legacyColumnRemap = {
    '2021': 'FY21',
    '2022': 'FY22',
    '2023': 'FY23',
    '2024': 'FY24',
    '2025': 'FY25',
    'YTD': 'FY26 YTD',
  };

  static String _fyColumnLabel(int year) => 'FY${year % 100}';

  static int? _yearFromColumn(String column) {
    if (column.startsWith('FY') && column.length >= 3) {
      final two = int.tryParse(column.substring(2));
      if (two != null) return 2000 + two;
    }
    return int.tryParse(column);
  }

  final Set<String> _selectedColumns = {..._allColumns};

  late final ScrollController _horizontalHeaderController;
  late final ScrollController _horizontalBodyController;
  late final ScrollController _verticalFrozenController;
  late final ScrollController _verticalBodyController;
  bool _syncingHorizontal = false;
  bool _syncingVertical = false;

  @override
  void initState() {
    super.initState();
    _horizontalHeaderController = ScrollController();
    _horizontalBodyController = ScrollController();
    _verticalFrozenController = ScrollController();
    _verticalBodyController = ScrollController();
    _horizontalHeaderController.addListener(_syncHorizontalFromHeader);
    _horizontalBodyController.addListener(_syncHorizontalFromBody);
    _verticalFrozenController.addListener(_syncVerticalFromFrozen);
    _verticalBodyController.addListener(_syncVerticalFromBody);
    _loadColumnPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FinanceProvider>().loadMutualFunds();
    });
  }

  @override
  void dispose() {
    _horizontalHeaderController.removeListener(_syncHorizontalFromHeader);
    _horizontalBodyController.removeListener(_syncHorizontalFromBody);
    _verticalFrozenController.removeListener(_syncVerticalFromFrozen);
    _verticalBodyController.removeListener(_syncVerticalFromBody);
    _horizontalHeaderController.dispose();
    _horizontalBodyController.dispose();
    _verticalFrozenController.dispose();
    _verticalBodyController.dispose();
    super.dispose();
  }

  void _syncHorizontalFromHeader() {
    if (_syncingHorizontal) return;
    _syncingHorizontal = true;
    if (_horizontalBodyController.hasClients) {
      _horizontalBodyController.jumpTo(_horizontalHeaderController.offset);
    }
    _syncingHorizontal = false;
  }

  void _syncHorizontalFromBody() {
    if (_syncingHorizontal) return;
    _syncingHorizontal = true;
    if (_horizontalHeaderController.hasClients) {
      _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
    }
    _syncingHorizontal = false;
  }

  void _syncVerticalFromFrozen() {
    if (_syncingVertical) return;
    _syncingVertical = true;
    if (_verticalBodyController.hasClients) {
      _verticalBodyController.jumpTo(_verticalFrozenController.offset);
    }
    _syncingVertical = false;
  }

  void _syncVerticalFromBody() {
    if (_syncingVertical) return;
    _syncingVertical = true;
    if (_verticalFrozenController.hasClients) {
      _verticalFrozenController.jumpTo(_verticalBodyController.offset);
    }
    _syncingVertical = false;
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
    final schemes =
        funds.map(_schemeKey).where((s) => s.isNotEmpty).toSet().toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return schemes;
  }

  List<String> _accountOptions(List<MutualFund> funds) {
    final accounts = funds.map(_accountKey).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return accounts;
  }

  double? _sortValue(MutualFund mf) {
    switch (_sortField) {
      case _MFSortField.scheme:
        return null;
      case _MFSortField.return2021:
        return mf.return2021;
      case _MFSortField.return2022:
        return mf.return2022;
      case _MFSortField.return2023:
        return mf.return2023;
      case _MFSortField.return2024:
        return mf.return2024;
      case _MFSortField.return2025:
        return mf.return2025;
      case _MFSortField.returnYtd:
        return mf.returnYtd;
    }
  }

  List<MutualFund> _filteredFunds(FinanceProvider provider) {
    final list = provider.mutualFunds.where((mf) {
      if (_selectedScheme != null && _schemeKey(mf) != _selectedScheme) {
        return false;
      }
      if (_selectedAccount != null && _accountKey(mf) != _selectedAccount) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == _MFSortField.scheme) {
        cmp = _schemeKey(a)
            .toLowerCase()
            .compareTo(_schemeKey(b).toLowerCase());
      } else {
        final av = _sortValue(a);
        final bv = _sortValue(b);
        if (av == null && bv == null) {
          cmp = 0;
        } else if (av == null) {
          cmp = 1; // nulls last
        } else if (bv == null) {
          cmp = -1;
        } else {
          cmp = av.compareTo(bv);
        }
      }
      if (!_sortAsc) cmp = -cmp;
      if (cmp != 0) return cmp;
      return _schemeKey(a).toLowerCase().compareTo(_schemeKey(b).toLowerCase());
    });
    return list;
  }

  void _toggleSort(_MFSortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = field == _MFSortField.scheme;
      }
    });
  }

  String _formatReturn(double? v) {
    if (v == null) return '—';
    return '${v.toStringAsFixed(1)}%';
  }

  Color? _returnColor(double? v) {
    if (v == null) return null;
    return v >= 0 ? Colors.green : Colors.red;
  }

  double? _benchmarkFor(String column, GlobalIndex? idx) {
    if (idx == null) return null;
    if (column == 'FY26 YTD') return idx.returnYtd;
    final year = _yearFromColumn(column);
    if (year != null) return idx.returnForYear(year);
    return null;
  }

  Color? _vsBenchmarkColor(double? scheme, double? bench) {
    if (scheme == null) return null;
    if (bench == null) return _returnColor(scheme);
    if (scheme > bench) return Colors.green;
    if (scheme < bench) return Colors.red;
    return null;
  }

  /// Counts FY + YTD cells that are red vs Nifty (6 columns: FY21–FY25 + YTD).
  int _redVsBenchmarkCount(MutualFund mf, GlobalIndex? nifty) {
    var red = 0;
    for (final y in _returnYears) {
      final color = _vsBenchmarkColor(
        mf.returnForYear(y),
        nifty?.returnForYear(y),
      );
      if (color == Colors.red) red++;
    }
    final ytdColor = _vsBenchmarkColor(mf.returnYtd, nifty?.returnYtd);
    if (ytdColor == Colors.red) red++;
    return red;
  }

  /// 4–6 red → red, 3 → amber, 0–2 → green.
  Color _performanceMarkerColor(MutualFund mf, GlobalIndex? nifty) {
    final red = _redVsBenchmarkCount(mf, nifty);
    if (red >= 4) return Colors.red;
    if (red == 3) return Colors.amber.shade700;
    return Colors.green;
  }

  Widget _performanceMarker(MutualFund mf, GlobalIndex? nifty) {
    final color = _performanceMarkerColor(mf, nifty);
    final red = _redVsBenchmarkCount(mf, nifty);
    return Tooltip(
      message: '$red of 6 FYs/YTD below Nifty',
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
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
            if (showTableView)
              IconButton(
                icon: const Icon(Icons.view_column),
                onPressed: _showColumnSelectionDialog,
                tooltip: 'Select columns',
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
                              return _buildMutualFundCard(
                                  context, mf, provider);
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
    final sortMenu = _buildSortMenu();
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
                  const SizedBox(width: 8),
                  sortMenu,
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
                  sortMenu,
                  if (clearButton != null) clearButton,
                ],
              ),
      ),
    );
  }

  Widget _buildSortMenu() {
    final colorScheme = Theme.of(context).colorScheme;
    String label;
    switch (_sortField) {
      case _MFSortField.scheme:
        label = 'Scheme';
      case _MFSortField.return2021:
        label = 'FY21';
      case _MFSortField.return2022:
        label = 'FY22';
      case _MFSortField.return2023:
        label = 'FY23';
      case _MFSortField.return2024:
        label = 'FY24';
      case _MFSortField.return2025:
        label = 'FY25';
      case _MFSortField.returnYtd:
        label = 'FY26 YTD';
    }
    final dir = _sortAsc ? '↑' : '↓';
    return PopupMenuButton<_MFSortField>(
      tooltip: 'Sort',
      onSelected: (field) {
        setState(() {
          if (_sortField == field) {
            _sortAsc = !_sortAsc;
          } else {
            _sortField = field;
            _sortAsc = field == _MFSortField.scheme;
          }
        });
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: _MFSortField.scheme,
          checked: _sortField == _MFSortField.scheme,
          child: const Text('Scheme'),
        ),
        for (final y in _returnYears)
          CheckedPopupMenuItem(
            value: _sortFieldForYear(y),
            checked: _sortField == _sortFieldForYear(y),
            child: Text('${_fyColumnLabel(y)} return'),
          ),
        CheckedPopupMenuItem(
          value: _MFSortField.returnYtd,
          checked: _sortField == _MFSortField.returnYtd,
          child: const Text('FY26 YTD return'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort, size: 16, color: colorScheme.onSurface),
            const SizedBox(width: 6),
            Text('Sort: $label $dir'),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  _MFSortField _sortFieldForYear(int year) {
    switch (year) {
      case 2021:
        return _MFSortField.return2021;
      case 2022:
        return _MFSortField.return2022;
      case 2023:
        return _MFSortField.return2023;
      case 2024:
        return _MFSortField.return2024;
      case 2025:
        return _MFSortField.return2025;
      default:
        return _MFSortField.scheme;
    }
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

  Widget _buildReturnsRow(MutualFund mf, GlobalIndex? nifty) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final y in _returnYears)
          _buildInfoColumn(
            _fyColumnLabel(y),
            _formatReturn(mf.returnForYear(y)),
            _vsBenchmarkColor(mf.returnForYear(y), nifty?.returnForYear(y)),
          ),
        _buildInfoColumn(
          'FY26 YTD',
          _formatReturn(mf.returnYtd),
          _vsBenchmarkColor(mf.returnYtd, nifty?.returnYtd),
        ),
      ],
    );
  }

  Widget _buildMutualFundCard(
      BuildContext context, MutualFund mf, FinanceProvider provider) {
    final invested = mf.nav * mf.quantity;
    final current = mf.currentNav * mf.quantity;
    final profitLoss = current - invested;
    final profitLossPercentage =
        invested > 0 ? (profitLoss / invested) * 100 : 0.0;

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
                  child: Row(
                    children: [
                      _performanceMarker(mf, provider.nifty50),
                      Expanded(
                        child: Text(
                          mf.displayName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
                      icon:
                          const Icon(Icons.delete, size: 20, color: Colors.red),
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
            const SizedBox(height: 12),
            Text(
              'Annual returns',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildReturnsRow(mf, provider.nifty50),
          ],
        ),
      ),
    );
  }

  List<String> get _scrollColumns => _allColumns
      .where((column) =>
          _selectedColumns.contains(column) &&
          !_frozenColumnNames.contains(column))
      .toList();

  List<String> get _visibleFrozenColumns => _frozenColumnNames
      .where((column) => _selectedColumns.contains(column))
      .toList();

  double _scrollColumnWidth(String column) {
    switch (column) {
      case 'Code':
        return 88;
      case 'Units':
        return 80;
      case 'NAV':
        return 96;
      case 'Current NAV':
        return 112;
      case 'P/L':
        return 96;
      case 'P/L %':
        return 80;
      case 'Actions':
        return 96;
      default:
        return 80; // year / YTD returns (room for Nifty subtitle)
    }
  }

  _MFSortField? _sortFieldForColumn(String column) {
    switch (column) {
      case 'Scheme':
        return _MFSortField.scheme;
      case 'FY21':
        return _MFSortField.return2021;
      case 'FY22':
        return _MFSortField.return2022;
      case 'FY23':
        return _MFSortField.return2023;
      case 'FY24':
        return _MFSortField.return2024;
      case 'FY25':
        return _MFSortField.return2025;
      case 'FY26 YTD':
        return _MFSortField.returnYtd;
      default:
        return null;
    }
  }

  Widget _buildMutualFundTable(
      FinanceProvider provider, List<MutualFund> funds) {
    final headerColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final borderColor = Theme.of(context).dividerColor;
    final frozenColumns = _visibleFrozenColumns;
    final scrollableColumns = _scrollColumns;
    final minScrollableWidth = scrollableColumns.fold<double>(
      0,
      (sum, column) => sum + _scrollColumnWidth(column),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final schemeWidth = frozenColumns.isEmpty
            ? 0.0
            : (constraints.maxWidth * 0.25).clamp(120.0, constraints.maxWidth);
        final availableScrollableWidth =
            (constraints.maxWidth - schemeWidth).clamp(0.0, double.infinity);
        final needsHorizontalScroll =
            minScrollableWidth > availableScrollableWidth + 0.5;
        final contentWidth = needsHorizontalScroll
            ? minScrollableWidth
            : availableScrollableWidth;
        final stretchFactor = minScrollableWidth > 0 && !needsHorizontalScroll
            ? availableScrollableWidth / minScrollableWidth
            : 1.0;
        double widthFor(String column) =>
            _scrollColumnWidth(column) * stretchFactor;
        final horizontalPhysics = needsHorizontalScroll
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics();

        return Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: headerColor,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: SizedBox(
                height: _headerHeight,
                child: Row(
                  children: [
                    if (frozenColumns.isNotEmpty)
                      _buildHeaderCell(
                        'Scheme',
                        width: schemeWidth,
                        frozen: true,
                        headerColor: headerColor,
                        borderColor: borderColor,
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontalHeaderController,
                        scrollDirection: Axis.horizontal,
                        physics: horizontalPhysics,
                        child: SizedBox(
                          width: contentWidth,
                          child: Row(
                            children: scrollableColumns
                                .map((column) {
                                  final bench = _benchmarkFor(
                                      column, provider.nifty50);
                                  return _buildHeaderCell(
                                    column,
                                    width: widthFor(column),
                                    borderColor: borderColor,
                                    subtitle: bench == null
                                        ? null
                                        : _formatReturn(bench),
                                  );
                                })
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (frozenColumns.isNotEmpty)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(right: BorderSide(color: borderColor)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(2, 0),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: schemeWidth,
                        child: ListView.builder(
                          controller: _verticalFrozenController,
                          itemCount: funds.length,
                          itemExtent: _rowHeight,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemBuilder: (context, index) {
                            return _buildSchemeCell(
                              funds[index],
                              borderColor,
                              index.isEven,
                              provider.nifty50,
                            );
                          },
                        ),
                      ),
                    ),
                  Expanded(
                    child: Scrollbar(
                      controller: _horizontalBodyController,
                      thumbVisibility: needsHorizontalScroll,
                      trackVisibility: needsHorizontalScroll,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      child: SingleChildScrollView(
                        controller: _horizontalBodyController,
                        scrollDirection: Axis.horizontal,
                        physics: horizontalPhysics,
                        child: SizedBox(
                          width: contentWidth,
                          child: Scrollbar(
                            controller: _verticalBodyController,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: _verticalBodyController,
                              itemCount: funds.length,
                              itemExtent: _rowHeight,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemBuilder: (context, index) {
                                return _buildScrollableRow(
                                  provider,
                                  funds[index],
                                  borderColor,
                                  index.isEven,
                                  widthFor,
                                  scrollableColumns,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderCell(
    String column, {
    required double width,
    bool frozen = false,
    Color? headerColor,
    required Color borderColor,
    String? subtitle,
  }) {
    final sortField = _sortFieldForColumn(column);
    final isSorted = sortField != null && _sortField == sortField;
    final canSort = sortField != null;
    final showSubtitle = subtitle != null && subtitle.isNotEmpty;

    return Material(
      color: headerColor ?? Colors.transparent,
      child: InkWell(
        onTap: canSort ? () => _toggleSort(sortField) : null,
        child: Container(
          width: width,
          height: _headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: borderColor.withValues(alpha: 0.5)),
              bottom: frozen ? BorderSide(color: borderColor) : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      column,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isSorted
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showSubtitle)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (canSort)
                Icon(
                  isSorted
                      ? (_sortAsc
                          ? Icons.arrow_upward
                          : Icons.arrow_downward)
                      : Icons.unfold_more,
                  size: 14,
                  color: isSorted
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSchemeCell(
    MutualFund mf,
    Color borderColor,
    bool even,
    GlobalIndex? nifty,
  ) {
    final name = mf.displayName;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: even
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: borderColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              _performanceMarker(mf, nifty),
              Expanded(
                child: Tooltip(
                  message: name,
                  waitDuration: const Duration(milliseconds: 300),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableRow(
    FinanceProvider provider,
    MutualFund mf,
    Color borderColor,
    bool even,
    double Function(String column) widthFor,
    List<String> scrollableColumns,
  ) {
    final invested = mf.nav * mf.quantity;
    final current = mf.currentNav * mf.quantity;
    final profitLoss = current - invested;
    final profitLossPercentage =
        invested > 0 ? (profitLoss / invested) * 100 : 0.0;
    final plColor = profitLoss >= 0 ? Colors.green : Colors.red;

    Widget textCell(String value, {Color? color, bool bold = false}) {
      return Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      );
    }

    Widget cellFor(String column) {
      switch (column) {
        case 'Code':
          return textCell(mf.schemeCode);
        case 'Units':
          return textCell(mf.quantity.toStringAsFixed(2));
        case 'NAV':
          return textCell(formatInr(mf.nav));
        case 'Current NAV':
          return textCell(formatInr(mf.currentNav));
        case 'P/L':
          return textCell(formatInr(profitLoss), color: plColor);
        case 'P/L %':
          return textCell('${profitLossPercentage.toStringAsFixed(2)}%',
              color: plColor);
        case 'FY26 YTD':
          return textCell(_formatReturn(mf.returnYtd),
              color: _vsBenchmarkColor(
                  mf.returnYtd, provider.nifty50?.returnYtd),
              bold: true);
        case 'Actions':
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _showDeleteDialog(context, mf.id, provider),
              ),
            ],
          );
        default:
          final year = _yearFromColumn(column);
          if (year != null) {
            final v = mf.returnForYear(year);
            return textCell(
              _formatReturn(v),
              color: _vsBenchmarkColor(v, provider.nifty50?.returnForYear(year)),
            );
          }
          return const SizedBox.shrink();
      }
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: even
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: borderColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: scrollableColumns
            .map(
              (column) => SizedBox(
                width: widthFor(column),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: cellFor(column),
                  ),
                ),
              ),
            )
            .toList(),
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

  Future<void> _loadColumnPreferences() async {
    try {
      final hiddenRaw = await ApiService.getHiddenMutualFundColumns();
      final hidden = hiddenRaw
          .map((c) => _legacyColumnRemap[c] ?? c)
          .toSet();
      if (!mounted) return;
      setState(() {
        _selectedColumns
          ..clear()
          ..addAll(_allColumns.where((c) => !hidden.contains(c)));
        if (_selectedColumns.isEmpty) {
          _selectedColumns.addAll(_allColumns);
        }
      });
    } catch (_) {
      // Keep defaults if config cannot be loaded.
    }
  }

  Future<void> _saveColumnPreferences() async {
    if (_selectedColumns.isEmpty) {
      setState(() => _selectedColumns.addAll(_allColumns));
    }
    final hidden = _allColumns.where((c) => !_selectedColumns.contains(c)).toList();
    try {
      await ApiService.saveHiddenMutualFundColumns(hidden);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save column preferences: $e')),
        );
      }
    }
  }

  void _showColumnSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select Columns'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _allColumns.length,
              itemBuilder: (context, index) {
                final column = _allColumns[index];
                return CheckboxListTile(
                  title: Text(column),
                  value: _selectedColumns.contains(column),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        _selectedColumns.add(column);
                      } else {
                        _selectedColumns.remove(column);
                      }
                    });
                    setState(() {});
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _saveColumnPreferences();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
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
