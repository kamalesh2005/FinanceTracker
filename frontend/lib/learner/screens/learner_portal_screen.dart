import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../utils/currency_format.dart';
import '../../widgets/make_default_dashboard_button.dart';
import '../learner_provider.dart';
import '../learner_theme.dart';
import '../models/challenge.dart';
import '../../utils/screen_tracker.dart';
import 'learner_challenge_form_screen.dart';
import 'learner_challenge_home_screen.dart';

class LearnerPortalScreen extends StatefulWidget {
  final String? initialInviteCode;

  const LearnerPortalScreen({super.key, this.initialInviteCode});

  @override
  State<LearnerPortalScreen> createState() => _LearnerPortalScreenState();
}

class _LearnerPortalScreenState extends State<LearnerPortalScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<LearnerProvider>().loadChallenges();
      final code = widget.initialInviteCode?.trim();
      if (code != null && code.isNotEmpty && mounted) {
        context.read<AuthProvider>().clearPendingLearnerInvite();
        await _joinWithCode(code);
      }
    });
  }

  Future<void> _joinWithCode(String raw) async {
    final code = raw.trim().toUpperCase();
    if (code.isEmpty) return;
    try {
      final detail = await context.read<LearnerProvider>().join(code);
      if (!mounted) return;
      await Navigator.push(
        context,
        appPageRoute(LearnerChallengeHomeScreen(challengeId: detail.id)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _promptJoin() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a challenge'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Invite code',
            hintText: 'e.g. ABCD2345',
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (code != null && mounted) {
      await _joinWithCode(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LearnerProvider>();
    final isLearnerDefault =
        context.watch<AuthProvider>().isDefaultPortal(AppPortal.learner);
    return wrapLearnerPage(Scaffold(
      appBar: AppBar(
        title: learnerBrandTitle(
          context,
          'Learner Portal',
          trailing: isLearnerDefault
              ? null
              : const MakeDefaultDashboardButton(portal: AppPortal.learner),
        ),
        actions: [
          IconButton(
            tooltip: 'Main portal',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => goToMainPortal(context),
          ),
          ...learnerAppBarActions(context),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final learner = context.read<LearnerProvider>();
          await Navigator.push(
            context,
            appPageRoute(const LearnerChallengeFormScreen()),
          );
          if (!mounted) return;
          await learner.loadChallenges();
        },
        icon: const Icon(Icons.flag_outlined),
        label: const Text('New challenge'),
      ),
      body: provider.isLoading && provider.challenges.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => context.read<LearnerProvider>().loadChallenges(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Investment Challenges',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Each teammate starts with the same cash amount you set. '
                    'Books stay separate. Trades use live catalog prices plus a ₹20 fee.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _promptJoin,
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: const Text('I have an invite code'),
                  ),
                  const SizedBox(height: 20),
                  if (provider.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        provider.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  if (provider.challenges.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No challenges yet. Create one or join with an invite code.',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    )
                  else
                    ...provider.challenges.map(_challengeTile),
                  const SizedBox(height: 72),
                ],
              ),
            ),
    ));
  }

  Widget _challengeTile(InvChallengeSummary ch) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: learnerSeed.withValues(alpha: 0.12),
          child: Icon(
            ch.ended ? Icons.emoji_events_outlined : Icons.school_outlined,
            color: learnerSeed,
          ),
        ),
        title: Text(ch.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${ch.isCreator ? 'Host' : 'Member'} · ${ch.memberCount} people · '
          'start ${formatInr(ch.initialNetworth)} · '
          '${ch.ended ? 'Ended' : '${ch.remaining.inDays}d left'}',
        ),
        trailing: ch.inviteCode.isNotEmpty && ch.isCreator
            ? IconButton(
                tooltip: 'Copy invite code',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: ch.inviteCode));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied ${ch.inviteCode}')),
                  );
                },
              )
            : const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            appPageRoute(LearnerChallengeHomeScreen(challengeId: ch.id)),
          );
        },
      ),
    );
  }
}
