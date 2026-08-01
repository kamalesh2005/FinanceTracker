import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/recommendation_engine.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import '../widgets/recommendation_rules_editor.dart';

class AdminAppSettingsScreen extends StatefulWidget {
  const AdminAppSettingsScreen({super.key});

  @override
  State<AdminAppSettingsScreen> createState() => _AdminAppSettingsScreenState();
}

class _AdminAppSettingsScreenState extends State<AdminAppSettingsScreen> {
  final _rulesKey = GlobalKey<RecommendationRulesEditorState>();
  RecommendationRuleset? _rules;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getAdminConfig();
      final raw = data['recommendation_rules'];
      setState(() {
        _rules = raw is Map<String, dynamic>
            ? RecommendationRuleset.fromJson(raw)
            : RecommendationRuleset.defaults();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      setState(() => _rules = RecommendationRuleset.defaults());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final errors = <String>[];
    final rs = _rulesKey.currentState?.buildRuleset(errors: errors);
    if (rs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errors.isEmpty ? 'Invalid rules' : errors.first),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.saveAdminConfig(recommendationRules: rs.toJson());
      if (!mounted) return;
      setState(() => _rules = rs);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin signal rules saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('App Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: _loading || _rules == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Default signal rules',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'These are the defaults for all users who have not set their '
                  'own rules. Seeded to match the previous built-in logic.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                RecommendationRulesEditor(
                  key: _rulesKey,
                  initial: _rules!,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
    );
  }
}
