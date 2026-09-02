import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

class AdminStockReviewEmailScreen extends StatefulWidget {
  const AdminStockReviewEmailScreen({super.key});

  @override
  State<AdminStockReviewEmailScreen> createState() =>
      _AdminStockReviewEmailScreenState();
}

class _AdminStockReviewEmailScreenState
    extends State<AdminStockReviewEmailScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _sending = false;
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
      final status = await ApiService.getStockReviewEmailStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
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

  Future<void> _sendNow() async {
    setState(() => _sending = true);
    try {
      await ApiService.sendStockReviewEmails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock review email job started'),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _fmtTs(dynamic raw) {
    if (raw == null) return '—';
    final s = raw.toString().trim();
    if (s.isEmpty) return '—';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}-${two(local.month)}-${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status ?? const <String, dynamic>{};
    final lastStatus = (status['last_status'] ?? '').toString();
    final failed = lastStatus == 'failure';

    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Stock Review Emails'),
        actions: authAppBarActions(
          context,
          extra: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Weekday cron (Mon–Fri 12:30 PM IST)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Emails eligible users with actionable Buy, Sell, or Book '
                  'Profit signals. Users opt in via Configure; admin must '
                  'enable sending per user.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _statusRow('Status', lastStatus.isEmpty ? '—' : lastStatus,
                            color: failed
                                ? Colors.red.shade700
                                : (lastStatus == 'success'
                                    ? Colors.green.shade700
                                    : null)),
                        _statusRow('Last attempt', _fmtTs(status['last_attempt_at'])),
                        _statusRow('Last success', _fmtTs(status['last_success_at'])),
                        _statusRow('Source', (status['last_source'] ?? '—').toString()),
                        if ((status['last_error'] ?? '').toString().isNotEmpty)
                          _statusRow('Error', status['last_error'].toString(),
                              color: Colors.red.shade700),
                        if ((status['last_summary_json'] ?? '')
                            .toString()
                            .isNotEmpty)
                          _statusRow(
                            'Summary',
                            status['last_summary_json'].toString(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _sending ? null : _sendNow,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Send now'),
                ),
              ],
            ),
    );
  }

  Widget _statusRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
