import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/global_mutual_fund.dart';
import '../services/api_service.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

class AdminMutualFundDataScreen extends StatefulWidget {
  const AdminMutualFundDataScreen({super.key});

  @override
  State<AdminMutualFundDataScreen> createState() =>
      _AdminMutualFundDataScreenState();
}

class _AdminMutualFundDataScreenState extends State<AdminMutualFundDataScreen> {
  static const int _pageSize = 50;

  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<GlobalMutualFund> _items = [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  List<Map<String, dynamic>> _importStatus = [];

  int get _totalPages {
    if (_total <= 0) return 1;
    return ((_total + _pageSize - 1) / _pageSize).floor();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadImportStatus() async {
    try {
      final rows = await ApiService.getMFImportStatus();
      if (!mounted) return;
      setState(() => _importStatus = rows);
    } catch (_) {
      // Status table is secondary; keep list usable if this fails.
    }
  }

  Future<void> _load({int? page}) async {
    final nextPage = page ?? _page;
    setState(() {
      _loading = true;
      _error = null;
      _page = nextPage;
    });
    try {
      final result = await ApiService.getAdminMutualFunds(
        q: _searchController.text,
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
      await _loadImportStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _load(page: 1);
    });
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'mf_catalog':
        return 'Upload Catalog';
      case 'mf_var':
        return 'Upload MF_VAR (NAV)';
      default:
        return kind;
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

  Widget _importStatusTable() {
    final kinds = ['mf_catalog', 'mf_var'];
    final byKind = <String, Map<String, dynamic>>{};
    for (final row in _importStatus) {
      final k = (row['kind'] ?? '').toString();
      if (k.isNotEmpty) byKind[k] = row;
    }

    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 56,
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('Upload')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Last attempt')),
            DataColumn(label: Text('Last success')),
            DataColumn(label: Text('Source')),
            DataColumn(label: Text('Manual')),
            DataColumn(label: Text('Run now')),
          ],
          rows: kinds.map((kind) {
            final row = byKind[kind] ?? const <String, dynamic>{};
            final status = (row['last_status'] ?? '').toString();
            final failed = status == 'failure';
            final statusLabel = status.isEmpty ? '—' : status;
            final source = (row['last_source'] ?? '').toString();
            final canRun = kind == 'mf_var';
            return DataRow(
              cells: [
                DataCell(Text(_kindLabel(kind))),
                DataCell(
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontWeight: failed ? FontWeight.w600 : FontWeight.normal,
                      color: failed
                          ? Colors.red.shade700
                          : (status == 'success'
                              ? Colors.green.shade700
                              : null),
                    ),
                  ),
                ),
                DataCell(Text(_fmtTs(row['last_attempt_at']))),
                DataCell(Text(_fmtTs(row['last_success_at']))),
                DataCell(Text(source.isEmpty ? '—' : source)),
                DataCell(
                  TextButton.icon(
                    onPressed: _uploading ? null : _uploadFile,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Upload'),
                  ),
                ),
                DataCell(
                  canRun
                      ? TextButton.icon(
                          onPressed: _uploading ? null : _runMFVarPull,
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Run'),
                        )
                      : const Text('—'),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _runMFVarPull() async {
    setState(() => _uploading = true);
    try {
      await ApiService.pullMFVarDaily();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('MF_VAR pull completed'),
          backgroundColor: Colors.green,
        ),
      );
      await _load(page: 1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('MF_VAR pull failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
      await _loadImportStatus();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx', 'xlsm'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read file contents'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _uploading = true);
      final summary = await ApiService.importMutualFunds(
        bytes,
        picked.name.isNotEmpty ? picked.name : 'mf.csv',
      );
      if (!mounted) return;
      setState(() => _uploading = false);
      final kindLabel = summary.kind == 'nav'
          ? 'NAV update'
          : summary.kind == 'catalog'
              ? 'Catalog import'
              : 'Import';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$kindLabel: created ${summary.created}, updated ${summary.updated}, '
            'skipped ${summary.skipped}, errors ${summary.errors}',
          ),
          backgroundColor: summary.errors > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 6),
        ),
      );
      try {
        await _load(page: 1);
      } catch (_) {
        // Import already succeeded; list refresh failure should not look like import failure.
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
      await _loadImportStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = _total == 0 ? 0 : ((_page - 1) * _pageSize) + 1;
    final to = (_page * _pageSize).clamp(0, _total);

    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Update Mutual Fund Data'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_uploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ...authAppBarActions(context),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _importStatusTable(),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search ISIN, symbol, or scheme name…',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _load(page: 1);
                      },
                    ),
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _load(page: 1),
                ),
                const SizedBox(height: 8),
                Text(
                  _total == 0
                      ? 'No matching mutual funds'
                      : 'Showing $from–$to of $_total',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _items.isEmpty
                        ? const Center(child: Text('No mutual funds found'))
                        : RefreshIndicator(
                            onRefresh: () => _load(),
                            child: ListView.builder(
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final m = _items[index];
                                final meta = <String>[
                                  if (m.isin.isNotEmpty) m.isin,
                                  if (m.symbol.isNotEmpty) 'Code: ${m.symbol}',
                                  if (m.series.isNotEmpty) 'Series: ${m.series}',
                                  if (m.currentNav > 0)
                                    'NAV ${formatInr(m.currentNav)}',
                                ];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      m.schemeName.isNotEmpty
                                          ? m.schemeName
                                          : m.isin,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(meta.join(' · ')),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: !_loading && _page > 1
                        ? () => _load(page: _page - 1)
                        : null,
                    child: const Text('Previous'),
                  ),
                  Expanded(
                    child: Text(
                      'Page $_page of $_totalPages',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: !_loading && _page < _totalPages
                        ? () => _load(page: _page + 1)
                        : null,
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
