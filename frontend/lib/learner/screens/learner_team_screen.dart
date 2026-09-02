import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../learner_api.dart';
import '../learner_provider.dart';
import '../learner_theme.dart';
import '../models/challenge.dart';

class LearnerTeamScreen extends StatefulWidget {
  final int challengeId;

  const LearnerTeamScreen({super.key, required this.challengeId});

  @override
  State<LearnerTeamScreen> createState() => _LearnerTeamScreenState();
}

class _LearnerTeamScreenState extends State<LearnerTeamScreen> {
  final _lookup = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _lookup.dispose();
    super.dispose();
  }

  Future<void> _reload() =>
      context.read<LearnerProvider>().openChallenge(widget.challengeId);

  Future<void> _addExisting() async {
    final id = _lookup.text.trim();
    if (id.isEmpty) return;
    try {
      await LearnerApi.addMember(
        widget.challengeId,
        InvRosterDraft(identifier: id),
      );
      _lookup.clear();
      await _reload();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _addPending() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final mobile = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pending invite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: mobile, decoration: const InputDecoration(labelText: 'Phone')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await LearnerApi.addMember(
        widget.challengeId,
        InvRosterDraft(
          displayName: name.text.trim(),
          invitedEmail: email.text.trim(),
          invitedMobile: mobile.text.trim(),
        ),
      );
      await _reload();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<LearnerProvider>().detail;
    final members = d?.members ?? [];
    final challengeName = d?.name ?? 'Challenge';
    return wrapLearnerPage(Scaffold(
      appBar: AppBar(
        title: learnerBrandTitle(context, 'LP:$challengeName : Team'),
        actions: learnerAppBarActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (d != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Invite code'),
              subtitle: Text(d.inviteCode),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: d.inviteCode));
                },
              ),
            ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lookup,
                  decoration: const InputDecoration(
                    labelText: 'Add by id / email / phone',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _addExisting, child: const Text('Add')),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addPending,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add pending slot'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          ...members.map((m) {
            return ListTile(
              leading: Icon(m.isPending ? Icons.hourglass_empty : Icons.person),
              title: Text(m.displayName.isEmpty ? 'Pending' : m.displayName),
              subtitle: Text(
                m.isPending
                    ? '${m.invitedEmail} ${m.invitedMobile}'.trim()
                    : 'Cash is personal to this member',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () async {
                  try {
                    await LearnerApi.removeMember(widget.challengeId, m.id);
                    await _reload();
                  } catch (e) {
                    setState(() =>
                        _error = e.toString().replaceFirst('Exception: ', ''));
                  }
                },
              ),
            );
          }),
        ],
      ),
    ));
  }
}
