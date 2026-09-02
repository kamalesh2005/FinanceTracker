import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../learner_api.dart';
import '../learner_provider.dart';
import '../learner_theme.dart';
import '../models/challenge.dart';
import '../../utils/screen_tracker.dart';
import 'learner_challenge_home_screen.dart';

class LearnerChallengeFormScreen extends StatefulWidget {
  const LearnerChallengeFormScreen({super.key});

  @override
  State<LearnerChallengeFormScreen> createState() =>
      _LearnerChallengeFormScreenState();
}

class _LearnerChallengeFormScreenState extends State<LearnerChallengeFormScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController(text: '100000');
  final _days = TextEditingController(text: '30');
  final _lookup = TextEditingController();
  final _pendingName = TextEditingController();
  final _pendingEmail = TextEditingController();
  final _pendingMobile = TextEditingController();
  final List<InvRosterDraft> _roster = [];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _days.dispose();
    _lookup.dispose();
    _pendingName.dispose();
    _pendingEmail.dispose();
    _pendingMobile.dispose();
    super.dispose();
  }

  Future<void> _lookupExisting() async {
    final id = _lookup.text.trim();
    if (id.isEmpty) return;
    try {
      final user = await LearnerApi.lookupUser(id);
      setState(() {
        _roster.add(InvRosterDraft(
          userId: (user['id'] as num?)?.toInt(),
          identifier: id,
          displayName: (user['username'] ?? user['email'] ?? user['mobile'] ?? id)
              .toString(),
        ));
        _lookup.clear();
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _addPending() {
    final name = _pendingName.text.trim();
    final email = _pendingEmail.text.trim();
    final mobile = _pendingMobile.text.trim();
    if (name.isEmpty && email.isEmpty && mobile.isEmpty) {
      setState(() => _error = 'Enter a name, email, or phone for the invite slot');
      return;
    }
    setState(() {
      _roster.add(InvRosterDraft(
        displayName: name,
        invitedEmail: email,
        invitedMobile: mobile,
      ));
      _pendingName.clear();
      _pendingEmail.clear();
      _pendingMobile.clear();
      _error = null;
    });
  }

  Future<void> _copyFromPrevious() async {
    final list = context.read<LearnerProvider>().challenges
        .where((c) => c.isCreator)
        .toList();
    if (list.isEmpty) {
      setState(() => _error = 'You have no previous challenges to copy a team from');
      return;
    }
    final picked = await showModalBottomSheet<InvChallengeSummary>(
      context: context,
      builder: (ctx) => ListView(
        children: [
          const ListTile(title: Text('Copy team from')),
          ...list.map(
            (c) => ListTile(
              title: Text(c.name),
              subtitle: Text('${c.memberCount} members'),
              onTap: () => Navigator.pop(ctx, c),
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    try {
      final detail = await LearnerApi.getChallenge(picked.id);
      if (!mounted) return;
      final me = context.read<AuthProvider>().user?.id;
      setState(() {
        _roster
          ..clear()
          ..addAll(detail.members.where((m) {
            if (m.userId != null && m.userId == me) return false;
            return m.displayName.isNotEmpty ||
                m.invitedEmail.isNotEmpty ||
                m.invitedMobile.isNotEmpty ||
                m.userId != null;
          }).map((m) {
            if (m.userId != null) {
              return InvRosterDraft(
                userId: m.userId,
                displayName: m.displayName,
              );
            }
            return InvRosterDraft(
              displayName: m.displayName,
              invitedEmail: m.invitedEmail,
              invitedMobile: m.invitedMobile,
            );
          }));
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final days = int.tryParse(_days.text.trim()) ?? 0;
    if (name.isEmpty || amount <= 0 || days < 1) {
      setState(() => _error = 'Name, starting cash, and duration are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await context.read<LearnerProvider>().createChallenge(
            name: name,
            initialNetworth: amount,
            durationDays: days,
            members: _roster,
          );
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: created.inviteCode));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite code ${created.inviteCode} copied')),
      );
      Navigator.pushReplacement(
        context,
        appPageRoute(LearnerChallengeHomeScreen(challengeId: created.id)),
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return wrapLearnerPage(Scaffold(
      appBar: AppBar(
        title: learnerBrandTitle(context, 'New challenge'),
        actions: learnerAppBarActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Challenge name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Starting cash for each member (₹)',
              helperText: 'Copied onto every member. Not a shared pool.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Duration (days)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Team', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _copyFromPrevious,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copy previous team'),
                style: learnerOutlinedActionStyle(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lookup,
                  decoration: const InputDecoration(
                    labelText: 'Existing user (id / email / phone)',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _lookupExisting(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _lookupExisting, child: const Text('Add')),
            ],
          ),
          const SizedBox(height: 12),
          Text('Pending invite slot', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _pendingName,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pendingEmail,
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pendingMobile,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addPending,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add pending slot'),
          ),
          const SizedBox(height: 12),
          ..._roster.asMap().entries.map((e) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                e.value.userId != null ? Icons.person : Icons.hourglass_empty,
              ),
              title: Text(e.value.label),
              subtitle: Text(
                e.value.userId != null ? 'Existing user' : 'Joins with invite code',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _roster.removeAt(e.key)),
              ),
            );
          }),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Start challenge'),
          ),
        ],
      ),
    ));
  }
}
