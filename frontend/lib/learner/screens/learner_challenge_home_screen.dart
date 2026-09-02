import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/currency_format.dart';
import '../learner_provider.dart';
import '../learner_theme.dart';
import '../models/challenge.dart';
import '../../utils/screen_tracker.dart';
import 'learner_holdings_screen.dart';
import 'learner_team_screen.dart';
import 'learner_trade_screen.dart';

class LearnerChallengeHomeScreen extends StatefulWidget {
  final int challengeId;

  const LearnerChallengeHomeScreen({super.key, required this.challengeId});

  @override
  State<LearnerChallengeHomeScreen> createState() =>
      _LearnerChallengeHomeScreenState();
}

class _LearnerChallengeHomeScreenState extends State<LearnerChallengeHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LearnerProvider>().openChallenge(widget.challengeId);
    });
  }

  Color _plColor(double v) {
    if (v > 0) return Colors.green.shade700;
    if (v < 0) return Colors.red.shade700;
    return Colors.grey.shade700;
  }

  Future<void> _openHoldings() async {
    await Navigator.push(
      context,
      appPageRoute(LearnerHoldingsScreen(challengeId: widget.challengeId)),
    );
    if (!mounted) return;
    await context.read<LearnerProvider>().openChallenge(widget.challengeId);
  }

  Future<void> _openTrade() async {
    await Navigator.push(
      context,
      appPageRoute(LearnerTradeScreen(challengeId: widget.challengeId)),
    );
    if (!mounted) return;
    await context.read<LearnerProvider>().openChallenge(widget.challengeId);
  }

  Future<void> _openAddUsers() async {
    await Navigator.push(
      context,
      appPageRoute(LearnerTeamScreen(challengeId: widget.challengeId)),
    );
    if (!mounted) return;
    await context.read<LearnerProvider>().openChallenge(widget.challengeId);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LearnerProvider>();
    final d = provider.detail;
    final p = provider.portfolio;
    final showXirr = context.watch<AuthProvider>().showXirr;
    final board = provider.leaderboard;

    return wrapLearnerPage(Scaffold(
      appBar: AppBar(
        title: learnerBrandTitle(context, d?.name ?? 'Challenge'),
        actions: learnerAppBarActions(
          context,
          extra: [
            if (d != null)
              IconButton(
                tooltip: 'Copy invite code',
                icon: const Icon(Icons.share_outlined),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: d.inviteCode));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Invite code ${d.inviteCode} copied')),
                  );
                },
              ),
          ],
        ),
      ),
      body: provider.isLoading && d == null
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? Center(child: Text(provider.error ?? 'Challenge not found'))
              : RefreshIndicator(
                  onRefresh: () =>
                      context.read<LearnerProvider>().openChallenge(widget.challengeId),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.timer_outlined, size: 18),
                            label: Text(d.remainingLabel),
                          ),
                          Chip(
                            avatar: const Icon(Icons.groups_outlined, size: 18),
                            label: Text('${d.members.where((m) => m.isActive).length} active'),
                          ),
                          if (!d.tradingOpen)
                            const Chip(
                              label: Text('Trading closed'),
                              backgroundColor: Color(0xFFFFE8E0),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionHeader(
                        title: 'My ${d.name} Portfolio',
                        actions: [
                          OutlinedButton(
                            style: learnerOutlinedActionStyle(context),
                            onPressed: _openHoldings,
                            child: const Text('Holdings'),
                          ),
                          OutlinedButton(
                            style: learnerOutlinedActionStyle(context),
                            onPressed: d.tradingOpen ? _openTrade : null,
                            child: const Text('Trade'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _metricGrid(d, p, showXirr),
                      const SizedBox(height: 20),
                      _sectionHeader(
                        title: 'Leaderboard',
                        actions: [
                          if (d.isCreator)
                            OutlinedButton(
                              style: learnerOutlinedActionStyle(context),
                              onPressed: _openAddUsers,
                              child: const Text('Add users'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _leaderboardCard(board),
                    ],
                  ),
                ),
    ));
  }

  Widget _sectionHeader({
    required String title,
    required List<Widget> actions,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: actions,
        ),
      ],
    );
  }

  Widget _metricGrid(
    InvChallengeDetail d,
    InvChallengePortfolio? p,
    bool showXirr,
  ) {
    final cash = p?.cash ?? d.myCash;
    final nw = p?.networth ?? d.myNetworth;
    final pl = p?.profitLoss ?? (d.myNetworth - d.initialNetworth);
    final plPct = p?.profitLossPercentage ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _row('Cash', formatInr(cash)),
            _row('Holdings', formatInr(p?.holdingsValue ?? d.myHoldingsValue)),
            _row('Networth', formatInr(nw), bold: true),
            _row(
              'P/L vs start',
              '${formatInr(pl)}  (${plPct.toStringAsFixed(2)}%)',
              color: _plColor(pl),
            ),
            if (showXirr && p?.xirr != null)
              _row('XIRR', '${((p!.xirr ?? 0) * 100).toStringAsFixed(2)}%'),
          ],
        ),
      ),
    );
  }

  Widget _leaderboardCard(List<InvLeaderboardRow> rows) {
    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No active members yet.'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _leaderboardTile(rows[i], i == 0),
          ],
        ],
      ),
    );
  }

  Widget _leaderboardTile(InvLeaderboardRow r, bool first) {
    final plColor = r.profitLoss >= 0
        ? Colors.green.shade700
        : Colors.red.shade700;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: first
            ? Colors.amber.shade200
            : learnerSeed.withValues(alpha: 0.12),
        child: Text('${r.rank}'),
      ),
      title: Text(
        r.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Cash ${formatInr(r.cash)} · Holdings ${formatInr(r.holdingsValue)}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatInr(r.networth),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            '${r.profitLossPct.toStringAsFixed(2)}%',
            style: TextStyle(color: plColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
