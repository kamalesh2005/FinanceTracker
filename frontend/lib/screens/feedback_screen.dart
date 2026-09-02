import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/feedback.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import '../widgets/feedback_fab.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const int _pageSize = 5;

  bool _loading = true;
  String? _error;
  List<FeedbackItem> _items = [];
  int _page = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _totalPages {
    if (_total == 0) return 1;
    return ((_total - 1) ~/ _pageSize) + 1;
  }

  Future<void> _load({int? page}) async {
    final nextPage = page ?? _page;
    setState(() {
      _loading = true;
      _error = null;
      _page = nextPage;
    });
    try {
      final result = await ApiService.getMyFeedback(
        page: nextPage,
        pageSize: _pageSize,
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

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy, h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('My Feedback'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: 'New feedback',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => showFeedbackDialog(
              context,
              screenName: 'Feedback',
            ).then((_) => _load(page: 1)),
          ),
          ...authAppBarActions(context),
        ],
      ),
      body: Column(
        children: [
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No feedback yet.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => showFeedbackDialog(
                  context,
                  screenName: 'Feedback',
                ).then((_) => _load(page: 1)),
                icon: const Icon(Icons.feedback_outlined),
                label: const Text('Send feedback'),
              ),
            ],
          ),
        ),
      );
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusChip(open: item.isOpen),
                      const Spacer(),
                      Text(
                        dateFmt.format(item.createdAt.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (item.screenName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'From: ${item.screenName}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(item.message),
                  const SizedBox(height: 12),
                  Text(
                    'Response',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.hasResponse
                        ? item.adminResponse
                        : 'Awaiting response',
                    style: TextStyle(
                      color: item.hasResponse
                          ? null
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle:
                          item.hasResponse ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ],
              ),
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

class _StatusChip extends StatelessWidget {
  final bool open;

  const _StatusChip({required this.open});

  @override
  Widget build(BuildContext context) {
    final color = open ? Colors.orange : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        open ? 'Open' : 'Closed',
        style: TextStyle(
          color: color.shade800,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
