import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<AppUser> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await ApiService.getUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _toggleEnabled(AppUser user) async {
    try {
      final updated = await ApiService.setUserEnabled(user.id, !user.enabled);
      if (!mounted) return;
      setState(() {
        _users = _users
            .map(
              (u) => u.id == updated.id
                  ? updated.copyWith(
                      recommendationFluctuationPct:
                          u.recommendationFluctuationPct,
                      recommendationRulesIsOverride:
                          u.recommendationRulesIsOverride,
                      recommendationRulesCount: u.recommendationRulesCount,
                      recommendationRules: u.recommendationRules,
                      stockCount: u.stockCount,
                      invChallengeCount: u.invChallengeCount,
                    )
                  : u,
            )
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  String _formatLastLogin(DateTime? at) {
    if (at == null) return 'Never';
    final y = at.year.toString().padLeft(4, '0');
    final m = at.month.toString().padLeft(2, '0');
    final d = at.day.toString().padLeft(2, '0');
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _fluctuationLabel(AppUser user) {
    final v = user.recommendationFluctuationPct;
    if (v == null) return 'Default';
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return '$s%';
  }

  String _rulesLabel(AppUser user) {
    if (!user.recommendationRulesIsOverride) return 'Default';
    final n = user.recommendationRulesCount;
    return n > 0 ? 'Custom ($n)' : 'Custom';
  }

  void _showRulesDetail(AppUser user) {
    final rules = user.recommendationRules;
    final ruleList = (rules?['rules'] as List?) ?? const [];
    final named = (rules?['named_values'] as List?) ?? const [];

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Signal Rules — ${user.displayName}'),
          content: SizedBox(
            width: 520,
            child: !user.recommendationRulesIsOverride
                ? const Text('Using admin default signal rules.')
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fluctuation: ${_fluctuationLabel(user)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (named.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Named values',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          ...named.map((nv) {
                            final m = Map<String, dynamic>.from(nv as Map);
                            return Text(
                              '• ${m['name']}: ${m['value']}',
                            );
                          }),
                        ],
                        const SizedBox(height: 12),
                        const Text(
                          'Signal rules',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (ruleList.isEmpty)
                          const Text('No rules in override.')
                        else
                          ...ruleList.map((r) {
                            final m = Map<String, dynamic>.from(r as Map);
                            final order = m['order'] ?? '';
                            final rec = m['recommendation'] ?? '';
                            final cond = m['condition'] ?? '';
                            final onMatch = m['on_match'] ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SelectableText(
                                '#$order $rec ($onMatch)\n$cond',
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateDialog() async {
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    var role = 'user';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create user'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameCtrl,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    TextField(
                      controller: mobileCtrl,
                      decoration: const InputDecoration(labelText: 'Mobile'),
                    ),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: role,
                      items: const [
                        DropdownMenuItem(value: 'user', child: Text('User')),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: (v) => setDialogState(() => role = v ?? 'user'),
                      decoration: const InputDecoration(labelText: 'Role'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      await ApiService.createUser(
                        username: usernameCtrl.text.trim(),
                        email: emailCtrl.text.trim(),
                        mobile: mobileCtrl.text.trim(),
                        password: passwordCtrl.text,
                        role: role,
                      );
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString().replaceFirst('Exception: ', ''),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameCtrl.dispose();
    emailCtrl.dispose();
    mobileCtrl.dispose();
    passwordCtrl.dispose();

    if (created == true) {
      await _load();
    }
  }

  Future<void> _toggleStockReviewEmailAdmin(AppUser user) async {
    try {
      final updated = await ApiService.setUserStockReviewEmailAdmin(
        user.id,
        !user.stockReviewEmailAdminEnabled,
      );
      if (!mounted) return;
      setState(() {
        _users = _users
            .map(
              (u) => u.id == updated.id
                  ? u.copyWith(
                      stockReviewEmailEnabled: updated.stockReviewEmailEnabled,
                      stockReviewEmailAdminEnabled:
                          updated.stockReviewEmailAdminEnabled,
                      stockReviewEmailEffective:
                          updated.stockReviewEmailEffective,
                    )
                  : u,
            )
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Users'),
        actions: authAppBarActions(
          context,
          extra: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.person_add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _users.isEmpty
                  ? const Center(child: Text('No users found'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth - 32,
                              ),
                              child: DataTable(
                                columnSpacing: 20,
                                columns: const [
                                  DataColumn(label: Text('Username')),
                                  DataColumn(label: Text('Email')),
                                  DataColumn(label: Text('Mobile')),
                                  DataColumn(label: Text('Role')),
                                  DataColumn(label: Text('Logins')),
                                  DataColumn(label: Text('Last login')),
                                  DataColumn(
                                    numeric: true,
                                    tooltip:
                                        'Distinct stocks currently held in DhanShanti',
                                    label: Text('Stocks (DhanShanti)'),
                                  ),
                                  DataColumn(
                                    numeric: true,
                                    tooltip:
                                        'Investment challenges created or joined in FlexStreet',
                                    label: Text('Challenges (FlexStreet)'),
                                  ),
                                  DataColumn(label: Text('Fluctuation')),
                                  DataColumn(label: Text('Signal Rules')),
                                  DataColumn(label: Text('Review email')),
                                  DataColumn(label: Text('Admin send')),
                                  DataColumn(label: Text('Effective')),
                                  DataColumn(label: Text('Enabled')),
                                ],
                                rows: _users.map((user) {
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(user.username ?? '—')),
                                      DataCell(Text(user.email ?? '—')),
                                      DataCell(Text(user.mobile ?? '—')),
                                      DataCell(Text(user.role)),
                                      DataCell(Text('${user.loginCount}')),
                                      DataCell(
                                        Text(_formatLastLogin(user.lastLoginAt)),
                                      ),
                                      DataCell(Text('${user.stockCount}')),
                                      DataCell(Text('${user.invChallengeCount}')),
                                      DataCell(
                                        Text(_fluctuationLabel(user)),
                                      ),
                                      DataCell(
                                        InkWell(
                                          onTap: () => _showRulesDetail(user),
                                          child: Text(
                                            _rulesLabel(user),
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(
                                        user.email != null &&
                                                user.email!.isNotEmpty
                                            ? (user.stockReviewEmailEnabled
                                                ? 'On'
                                                : 'Off')
                                            : '—',
                                      )),
                                      DataCell(
                                        Switch(
                                          value: user.stockReviewEmailAdminEnabled,
                                          onChanged: user.email != null &&
                                                  user.email!.isNotEmpty
                                              ? (_) => _toggleStockReviewEmailAdmin(
                                                    user,
                                                  )
                                              : null,
                                        ),
                                      ),
                                      DataCell(Text(
                                        user.stockReviewEmailEffective
                                            ? 'Yes'
                                            : 'No',
                                      )),
                                      DataCell(
                                        Switch(
                                          value: user.enabled,
                                          onChanged: (_) =>
                                              _toggleEnabled(user),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
