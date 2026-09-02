import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/feedback.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  static const int _pageSize = 5;

  bool _loading = true;
  String? _error;
  List<FeedbackItem> _items = [];
  int _page = 1;
  int _total = 0;
  String _status = 'open';

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _totalPages {
    if (_total == 0) return 1;
    return ((_total - 1) ~/ _pageSize) + 1;
  }

  Future<void> _load({int? page, String? status}) async {
    final nextPage = page ?? _page;
    final nextStatus = status ?? _status;
    setState(() {
      _loading = true;
      _error = null;
      _page = nextPage;
      _status = nextStatus;
    });
    try {
      final result = await ApiService.getAdminFeedback(
        page: nextPage,
        pageSize: _pageSize,
        status: nextStatus,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _total = result.total;
        _page = result.page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openDetail(FeedbackItem item) async {
    final responseController = TextEditingController(text: item.adminResponse);
    final dateFmt = DateFormat('d MMM yyyy, h:mm a');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.username ?? 'User #${item.userId}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item.isOpen ? 'Open' : 'Closed'} · ${item.screenName} · ${dateFmt.format(item.createdAt.toLocal())}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                const Text('Feedback', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(item.message),
                const SizedBox(height: 16),
                const Text('Response', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (item.isOpen)
                  TextField(
                    controller: responseController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Write a response…',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                    minLines: 2,
                  )
                else
                  Text(
                    item.hasResponse
                        ? item.adminResponse
                        : 'No response recorded',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (item.isOpen) ...[
            FilledButton(
              onPressed: () async {
                final response = responseController.text.trim();
                if (response.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Response is required')),
                  );
                  return;
                }
                try {
                  await ApiService.respondToFeedback(
                    id: item.id,
                    response: response,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Response saved')),
                  );
                  _load(page: _page);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().replaceFirst('Exception: ', ''),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save response'),
            ),
            OutlinedButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    title: const Text('Close feedback?'),
                    content: Text(
                      responseController.text.trim().isEmpty
                          ? 'Close without a response?'
                          : 'Close this feedback item?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
                if (confirm != true) return;
                try {
                  if (responseController.text.trim().isNotEmpty) {
                    await ApiService.respondToFeedback(
                      id: item.id,
                      response: responseController.text.trim(),
                    );
                  }
                  await ApiService.closeFeedback(item.id);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Feedback closed')),
                  );
                  _load(page: _page);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().replaceFirst('Exception: ', ''),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Close'),
            ),
          ],
        ],
      ),
    );
    responseController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy, h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('User Feedback'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Open'),
                  selected: _status == 'open',
                  onSelected: (_) => _load(page: 1, status: 'open'),
                ),
                ChoiceChip(
                  label: const Text('Closed'),
                  selected: _status == 'closed',
                  onSelected: (_) => _load(page: 1, status: 'closed'),
                ),
                ChoiceChip(
                  label: const Text('All'),
                  selected: _status == 'all',
                  onSelected: (_) => _load(page: 1, status: 'all'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(dateFmt)),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildBody(DateFormat dateFmt) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => _load(), child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No feedback found.'));
    }

    return RefreshIndicator(
      onRefresh: () => _load(page: _page),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _items[index];
          return Card(
            child: ListTile(
              title: Text(item.username ?? 'User #${item.userId}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    '${item.isOpen ? 'Open' : 'Closed'} · ${item.screenName} · ${dateFmt.format(item.createdAt.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.hasResponse) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Response: ${item.adminResponse}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDetail(item),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPagination() {
    if (_total == 0) return const SizedBox.shrink();
    final from = ((_page - 1) * _pageSize) + 1;
    final to = (_page * _pageSize).clamp(0, _total);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Text('Showing $from–$to of $_total'),
            const Spacer(),
            IconButton(
              tooltip: 'Previous page',
              onPressed: !_loading && _page > 1
                  ? () => _load(page: _page - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Page $_page of $_totalPages'),
            IconButton(
              tooltip: 'Next page',
              onPressed: !_loading && _page < _totalPages
                  ? () => _load(page: _page + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
