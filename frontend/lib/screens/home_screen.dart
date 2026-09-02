import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/global_index.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import '../widgets/make_default_dashboard_button.dart';
import '../utils/screen_tracker.dart';
import 'stocks_screen.dart';
import 'stock_screener_screen.dart';
import 'stock_watchlist_screen.dart';
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

  /// Below this width, stack Stocks and Mutual Funds cards vertically.
  static const double _portfolioCardsBreakpoint = 900;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final finance = context.read<FinanceProvider>();
      // Load the dashboard immediately; preferences can finish in parallel.
      await Future.wait<void>([
        auth.loadPreferences(),
        finance.loadPortfolioSummary(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final watchList = auth.useAsStockWatchList;

    return Scaffold(
      appBar: AppBar(
        title: AppBrandTitle(
          'Dhan Shanti',
          trailing: auth.isDefaultPortal(AppPortal.main)
              ? null
              : const MakeDefaultDashboardButton(portal: AppPortal.main),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            if (auth.isAdmin)
              IconButton(
                tooltip: 'Admin',
                icon: const Icon(Icons.admin_panel_settings),
                onPressed: () {
                  Navigator.push(
                    context,
                    appPageRoute(const AdminScreen()),
                  );
                },
              ),
            IconButton(
              tooltip: 'Configure',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () async {
                await Navigator.push(
                  context,
                  appPageRoute(const ConfigureScreen()),
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
          final totalInvested = _asDouble(summary['total_invested']);
          final currentValue = _asDouble(summary['current_value']);
          final profitLoss = _asDouble(summary['profit_loss']);
          final profitLossPercentage =
              _asDouble(summary['profit_loss_percentage']);
          final stockCount = _asInt(summary['stock_count']);
          final mfCount = _asInt(summary['mf_count']);
          final bySource = (summary['by_source'] as List<dynamic>?) ?? [];
          final byMfSource = (summary['by_mf_source'] as List<dynamic>?) ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  watchList ? 'Stocks Watch List Summary' : 'Stocks Portfolio Summary',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
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
                            mfCount.toString(),
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
                    scaleAmounts: auth.isAdmin,
                  ),
                const SizedBox(height: 24),
                _buildPortfolioCardsRow(
                  watchList: watchList,
                  stockCount: stockCount,
                  mfCount: mfCount,
                  bySource: bySource,
                  byMfSource: byMfSource,
                  nifty: provider.nifty50,
                  scaleAmounts: auth.isAdmin,
                ),
                const SizedBox(height: 16),
                _buildStockResearchCard(),
                const SizedBox(height: 16),
                _buildLearnerPortalCard(),
                const SizedBox(height: 16),
                _buildFreedomPortalCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPortfolioCardsRow({
    required bool watchList,
    required int stockCount,
    required int mfCount,
    required List<dynamic> bySource,
    required List<dynamic> byMfSource,
    GlobalIndex? nifty,
    required bool scaleAmounts,
  }) {
    final stocksCard = _buildStocksPortfolioCard(
      watchList: watchList,
      stockCount: stockCount,
      bySource: bySource,
      nifty: nifty,
      scaleAmounts: scaleAmounts,
    );
    final mfCard = _buildMutualFundsCard(
      watchList: watchList,
      mfCount: mfCount,
      byMfSource: byMfSource,
      scaleAmounts: scaleAmounts,
    );
    final sideBySide =
        MediaQuery.sizeOf(context).width >= _portfolioCardsBreakpoint;

    if (!sideBySide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stocksCard,
          const SizedBox(height: 16),
          mfCard,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: stocksCard),
        const SizedBox(width: 16),
        Expanded(child: mfCard),
      ],
    );
  }

  Widget _buildStocksPortfolioCard({
    required bool watchList,
    required int stockCount,
    required List<dynamic> bySource,
    GlobalIndex? nifty,
    required bool scaleAmounts,
  }) {
    Widget body;
    final showXirrNote = !watchList && bySource.isNotEmpty;
    if (watchList) {
      body = bySource.isEmpty
          ? _buildSummaryRow('Number of Stocks', stockCount.toString())
          : _buildByAccountCountTable(bySource);
    } else if (bySource.isEmpty) {
      body = const Text('No stock holdings by account');
    } else {
      body = _buildByAccountTable(
        bySource,
        showXirr: true,
        showFyReturns: true,
        nifty: nifty,
        scaleAmounts: scaleAmounts,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAlignedSection(
              header: _buildSectionHeader(
                icon: Icons.show_chart,
                iconColor: Colors.blue,
                title: 'Stocks',
                onManage: () async {
                  await Navigator.push(
                    context,
                    appPageRoute(const StocksScreen()),
                  );
                  if (!mounted) return;
                  await context.read<FinanceProvider>().loadPortfolioSummary();
                },
              ),
              body: body,
            ),
            if (showXirrNote) ...[
              const SizedBox(height: 8),
              Text(
                '* XIRR is calculated based on available transaction data with date.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMutualFundsCard({
    required bool watchList,
    required int mfCount,
    required List<dynamic> byMfSource,
    required bool scaleAmounts,
  }) {
    Widget body;
    final showXirrNote = !watchList && byMfSource.isNotEmpty;
    if (watchList) {
      body = byMfSource.isEmpty
          ? _buildSummaryRow(
              'Number of Mutual Funds',
              mfCount.toString(),
            )
          : _buildByAccountCountTable(byMfSource);
    } else if (byMfSource.isEmpty) {
      body = const Text('No mutual fund holdings by account');
    } else {
      body = _buildByAccountTable(
        byMfSource,
        showXirr: true,
        showFyReturns: true,
        scaleAmounts: scaleAmounts,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _buildAlignedSection(
          header: _buildSectionHeader(
            icon: Icons.account_balance,
            iconColor: Colors.purple,
            title: 'Mutual Funds',
            onManage: () async {
              await Navigator.push(
                context,
                appPageRoute(const MutualFundsScreen()),
              );
              if (!mounted) return;
              await context.read<FinanceProvider>().loadPortfolioSummary();
            },
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              body,
              if (showXirrNote) ...[
                const SizedBox(height: 8),
                Text(
                  '* XIRR is calculated based on available transaction data with date.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockResearchCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < _summaryCardsBreakpoint;

    void openScreener() {
      Navigator.push(
        context,
        appPageRoute(const StockScreenerScreen()),
      );
    }

    void openWatchlist() {
      Navigator.push(
        context,
        appPageRoute(const StockWatchlistScreen()),
      );
    }

    final evaluateButton = FilledButton.icon(
      onPressed: openScreener,
      icon: const Icon(Icons.insights_outlined),
      label: const Text('Evaluate Stocks to Buy'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
    final watchlistButton = OutlinedButton.icon(
      onPressed: openWatchlist,
      icon: const Icon(Icons.bookmark_outline),
      label: const Text('WatchList'),
      style: _outlinedActionStyle().copyWith(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );

    return Card(
      color: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.08),
        colorScheme.surface,
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStockResearchHeader(colorScheme),
                  const SizedBox(height: 16),
                  evaluateButton,
                  const SizedBox(height: 8),
                  watchlistButton,
                ],
              )
            : Row(
                children: [
                  Expanded(child: _buildStockResearchHeader(colorScheme)),
                  const SizedBox(width: 16),
                  evaluateButton,
                  const SizedBox(width: 8),
                  watchlistButton,
                ],
              ),
      ),
    );
  }

  Widget _buildStockResearchHeader(ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(Icons.trending_up, color: colorScheme.primary, size: 32),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock Research',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'Screen the market for buy ideas and track symbols on your WatchList.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLearnerPortalCard() {
    return _buildPortalCard(
      icon: Icons.school_outlined,
      iconColor: const Color(0xFF0F5C56),
      title: 'Learner Portal',
      description:
          'Run an Investment Challenge: each teammate gets the same starting cash and paper-trades catalog prices.',
      onOpen: () => context.read<AuthProvider>().openPortal(AppPortal.learner),
    );
  }

  Widget _buildFreedomPortalCard() {
    return _buildPortalCard(
      icon: Icons.park_outlined,
      iconColor: const Color(0xFF1B5E20),
      title: 'Financial Freedom Portal',
      description:
          'Plan assets, income, and expenses — see ready to retire, live well fund, and term insurance needs.',
      onOpen: () => context.read<AuthProvider>().openPortal(AppPortal.freedom),
    );
  }

  Widget _buildPortalCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required VoidCallback onOpen,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(description),
                  ],
                ),
              ),
              OutlinedButton(
                style: _outlinedActionStyle(),
                onPressed: onOpen,
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Header stays in the visible card; tables manage their own horizontal scroll.
  Widget _buildAlignedSection({
    required Widget header,
    required Widget body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 12),
        body,
      ],
    );
  }

  static double _asDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  /// Admin dashboard only: show money amounts ÷10 as whole INR.
  String _formatDashboardAmount(num value, {required bool scaleForAdmin}) {
    final v = scaleForAdmin ? (value / 10) : value;
    return formatInr(v);
  }

  Widget _buildByAccountTable(
    List<dynamic> rows, {
    bool showXirr = false,
    bool showFyReturns = false,
    GlobalIndex? nifty,
    required bool scaleAmounts,
  }) {
    final parsed = rows.map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      return (
        source: map['source']?.toString() ?? '-',
        invested: _asDouble(map['total_invested']),
        current: _asDouble(map['current_value']),
        pl: _asDouble(map['profit_loss']),
        plPct: _asDouble(map['profit_loss_percentage']),
        xirr: _optRate(map['xirr']),
        sinceFy25: _optRate(map['since_fy25']),
        fy26Ytd: _optRate(map['fy26_ytd']),
      );
    }).toList();

    const minAccountW = 100.0;
    const minMoneyW = 100.0;
    const minPctW = 64.0;
    const minFyW = 64.0;

    final minScrollCols = <({String id, double width})>[
      (id: 'invested', width: minMoneyW),
      (id: 'current', width: minMoneyW),
      (id: 'pl', width: minMoneyW),
      (id: 'plPct', width: minPctW),
      if (showXirr) (id: 'xirr', width: minPctW),
      if (showFyReturns) (id: 'sinceFy25', width: minFyW),
      if (showFyReturns) (id: 'fy26Ytd', width: minFyW),
    ];
    final minScrollWidth =
        minScrollCols.fold<double>(0, (s, c) => s + c.width);
    final minTableWidth = minAccountW + minScrollWidth;
    final headerH = nifty != null ? 44.0 : 32.0;
    const rowH = 36.0;

    Widget headerLabel(String text, {Widget? trailing}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 2), trailing],
        ],
      );
    }

    Widget fyHeader(String title, double? niftyPct, String helpMessage) {
      if (nifty == null) {
        return headerLabel(title);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          headerLabel(title),
          if (niftyPct != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatNiftyPct(niftyPct),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 2),
                Tooltip(
                  message: helpMessage,
                  waitDuration: const Duration(milliseconds: 300),
                  child: const Icon(
                    Icons.help_outline,
                    size: 13,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
        ],
      );
    }

    Widget cellText(String text, {Color? color, bool bold = false}) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    Widget headerFor(String id) {
      switch (id) {
        case 'invested':
          return headerLabel('Invested');
        case 'current':
          return headerLabel('Current');
        case 'pl':
          return headerLabel('P/L');
        case 'plPct':
          return headerLabel('P/L %');
        case 'xirr':
          return headerLabel('XIRR*');
        case 'sinceFy25':
          return fyHeader(
            'FY25',
            nifty?.return2025,
            'NSE 50 return for FY25',
          );
        case 'fy26Ytd':
          return fyHeader(
            'FY26',
            nifty?.returnYtd,
            'NSE 50 return in FY26 YTD',
          );
        default:
          return const SizedBox.shrink();
      }
    }

    Widget cellFor(String id, dynamic row) {
      final plColor = row.pl >= 0 ? Colors.green : Colors.red;
      switch (id) {
        case 'invested':
          return cellText(
            _formatDashboardAmount(row.invested, scaleForAdmin: scaleAmounts),
          );
        case 'current':
          return cellText(
            _formatDashboardAmount(row.current, scaleForAdmin: scaleAmounts),
          );
        case 'pl':
          return cellText(
            _formatDashboardAmount(row.pl, scaleForAdmin: scaleAmounts),
            color: plColor,
          );
        case 'plPct':
          return cellText('${row.plPct.toStringAsFixed(1)}%', color: plColor);
        case 'xirr':
          final x = row.xirr as double?;
          return cellText(
            x == null ? '-' : '${(x * 100).toStringAsFixed(1)}%',
            color: x == null ? null : (x >= 0 ? Colors.green : Colors.red),
          );
        case 'sinceFy25':
          return _fyReturnCell(row.sinceFy25 as double?, compact: true);
        case 'fy26Ytd':
          return _fyReturnCell(row.fy26Ytd as double?, compact: true);
        default:
          return const SizedBox.shrink();
      }
    }

    Widget accountCol({
      required double? width,
      required bool showBorder,
    }) {
      final col = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: headerH,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
                right: showBorder
                    ? BorderSide(color: Theme.of(context).dividerColor)
                    : BorderSide.none,
              ),
            ),
            child: headerLabel('Account'),
          ),
          ...parsed.map((row) {
            return Container(
              height: rowH,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                  ),
                  right: showBorder
                      ? BorderSide(color: Theme.of(context).dividerColor)
                      : BorderSide.none,
                ),
              ),
              child: cellText(row.source, bold: true),
            );
          }),
        ],
      );
      if (width == null) return col;
      return SizedBox(width: width, child: col);
    }

    Widget scrollBody(List<({String id, double width})> cols) {
      final bodyWidth = cols.fold<double>(0, (s, c) => s + c.width);
      return SizedBox(
        width: bodyWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: headerH,
              child: Row(
                children: [
                  for (final col in cols)
                    SizedBox(
                      width: col.width,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: headerFor(col.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            ...parsed.map((row) {
              return SizedBox(
                height: rowH,
                child: Row(
                  children: [
                    for (final col in cols)
                      SizedBox(
                        width: col.width,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: cellFor(col.id, row),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }

    /// Fills [constraints] by giving each column flex proportional to its min width.
    Widget expandedTable() {
      Widget cellPad(Widget child) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Align(alignment: Alignment.centerLeft, child: child),
          );

      Widget headerRow() {
        return SizedBox(
          height: headerH,
          child: Row(
            children: [
              Expanded(
                flex: minAccountW.round(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: headerLabel('Account'),
                  ),
                ),
              ),
              for (final col in minScrollCols)
                Expanded(
                  flex: col.width.round(),
                  child: cellPad(headerFor(col.id)),
                ),
            ],
          ),
        );
      }

      Widget dataRow(dynamic row) {
        return SizedBox(
          height: rowH,
          child: Row(
            children: [
              Expanded(
                flex: minAccountW.round(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: cellText(row.source, bold: true),
                  ),
                ),
              ),
              for (final col in minScrollCols)
                Expanded(
                  flex: col.width.round(),
                  child: cellPad(cellFor(col.id, row)),
                ),
            ],
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headerRow(),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          ...parsed.map(dataRow),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final needsFreeze = available < minTableWidth - 8;

        if (needsFreeze) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              accountCol(width: minAccountW, showBorder: true),
              Expanded(
                child: _HorizontalScrollWithBar(
                  child: scrollBody(minScrollCols),
                ),
              ),
            ],
          );
        }

        return expandedTable();
      },
    );
  }

  static double? _optRate(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return null;
  }

  String _formatNiftyPct(double rate) {
    // Index returns from API are already percent points (e.g. 12.3).
    return '${rate.toStringAsFixed(1)}%';
  }

  Widget _fyReturnCell(double? rate, {bool compact = false}) {
    if (rate == null) {
      return Text('-', style: const TextStyle(fontSize: 14));
    }
    final color = rate >= 0 ? Colors.green : Colors.red;
    return Text(
      '${(rate * 100).toStringAsFixed(compact ? 1 : 2)}%',
      style: TextStyle(fontSize: 14, color: color),
    );
  }

  Widget _buildByAccountCountTable(List<dynamic> rows) {
    return DataTable(
      columns: const [
        DataColumn(label: Text('Account')),
        DataColumn(label: Text('Count')),
      ],
      rows: rows.map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        final source = map['source']?.toString() ?? '-';
        final count = _asInt(map['count']);

        return DataRow(
          cells: [
            DataCell(Text(
              source,
              style: const TextStyle(fontWeight: FontWeight.bold),
            )),
            DataCell(Text(count.toString())),
          ],
        );
      }).toList(),
    );
  }

  ButtonStyle _outlinedActionStyle() {
    final color = Theme.of(context).colorScheme.primary;
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Future<void> Function() onManage,
  }) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        OutlinedButton(
          style: _outlinedActionStyle(),
          onPressed: () {
            onManage();
          },
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
    required bool scaleAmounts,
  }) {
    final plColor = profitLoss >= 0 ? Colors.green : Colors.red;
    final metrics = <({String label, String value, Color? color})>[
      (
        label: 'Total Invested',
        value: _formatDashboardAmount(totalInvested, scaleForAdmin: scaleAmounts),
        color: null,
      ),
      (
        label: 'Current Value',
        value: _formatDashboardAmount(currentValue, scaleForAdmin: scaleAmounts),
        color: null,
      ),
      (
        label: 'Profit/Loss',
        value: _formatDashboardAmount(profitLoss, scaleForAdmin: scaleAmounts),
        color: plColor,
      ),
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

/// Horizontal scroll + always-visible bar, sharing one [ScrollController]
/// so the thumb can be dragged (required on web/desktop).
class _HorizontalScrollWithBar extends StatefulWidget {
  const _HorizontalScrollWithBar({required this.child});

  final Widget child;

  @override
  State<_HorizontalScrollWithBar> createState() =>
      _HorizontalScrollWithBarState();
}

class _HorizontalScrollWithBarState extends State<_HorizontalScrollWithBar> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: widget.child,
      ),
    );
  }
}
