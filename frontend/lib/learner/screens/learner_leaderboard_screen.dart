import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/currency_format.dart';
import '../learner_provider.dart';
import '../learner_theme.dart';

class LearnerLeaderboardScreen extends StatelessWidget {
  final int challengeId;

  const LearnerLeaderboardScreen({super.key, required this.challengeId});

  @override
  Widget build(BuildContext context) {
    final rows = context.watch<LearnerProvider>().leaderboard;
    return wrapLearnerPage(Scaffold(
      appBar: AppBar(
        title: learnerBrandTitle(context, 'Leaderboard'),
        actions: learnerAppBarActions(context),
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<LearnerProvider>().openChallenge(challengeId),
        child: rows.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No active members yet.'),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final plColor = r.profitLoss >= 0
                      ? Colors.green.shade700
                      : Colors.red.shade700;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: i == 0
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
                    ),
                  );
                },
              ),
      ),
    ));
  }
}
