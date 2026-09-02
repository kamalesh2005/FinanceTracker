import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/stock.dart';
import '../services/api_service.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

class AdminStockDataScreen extends StatefulWidget {
  const AdminStockDataScreen({super.key});

  @override
  State<AdminStockDataScreen> createState() => _AdminStockDataScreenState();
}

class _AdminStockDataScreenState extends State<AdminStockDataScreen> {
  static const int _pageSize = 50;

  final _searchController = TextEditingController();

  List<Stock> _stocks = [];
  int _total = 0;
  int _page = 1;
  bool _loading = false;
  bool _hasSearched = false;
  bool _uploading = false;
  String? _error;

  String _series = '';
  String _listingCategory = '';
  String _pullData = '';
  String _industry = '';
  List<String> _industries = [];

  List<Map<String, dynamic>> _importStatus = [];

  int get _totalPages {
    if (_total <= 0) return 1;
    return ((_total + _pageSize - 1) / _pageSize).floor();
  }

  @override
  void initState() {
    super.initState();
    _loadImportStatus();
    _loadIndustries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadIndustries() async {
    try {
      final opts = await ApiService.screenerOptions();
      if (!mounted) return;
      setState(() => _industries = List<String>.from(opts.industries));
    } catch (_) {
      // Industry filter stays empty if options fail to load.
    }
  }

  Future<void> _loadImportStatus() async {
    try {
      final rows = await ApiService.getStockImportStatus();
      if (!mounted) return;
      setState(() => _importStatus = rows);
    } catch (_) {
      // Status table is secondary; keep stock list usable if this fails.
    }
  }

  Future<void> _load({int? page}) async {
    final nextPage = page ?? _page;
    setState(() {
      _loading = true;
      _error = null;
      _page = nextPage;
      _hasSearched = true;
    });
    try {
      final result = await ApiService.getAdminStocks(
        q: _searchController.text,
        industry: _industry,
        series: _series,
        listingCategory: _listingCategory,
        pullData: _pullData,
        page: nextPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _stocks = result.items;
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

  String _kindLabel(String kind) {
    switch (kind) {
      case 'nse':
        return 'Upload NSE CSV';
      case 'etf':
        return 'Upload ETF CSV';
      case 'closes':
        return 'Upload Closing Prices';
      case 'bse_bhav':
        return 'Upload BSE Bhav';
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
    final kinds = ['nse', 'etf', 'closes', 'bse_bhav'];
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
            final canRunPr = kind == 'etf' || kind == 'closes';
            final canRunBse = kind == 'bse_bhav';
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
                    onPressed: _uploading ? null : () => _uploadForKind(kind),
                    icon: Icon(
                      kind == 'closes'
                          ? Icons.price_change_outlined
                          : Icons.upload_file,
                      size: 18,
                    ),
                    label: const Text('Upload'),
                  ),
                ),
                DataCell(
                  canRunPr
                      ? TextButton.icon(
                          onPressed: _uploading ? null : _runNsePrPull,
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Run'),
                        )
                      : canRunBse
                          ? TextButton.icon(
                              onPressed: _uploading ? null : _runBseBhavPull,
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

  void _uploadForKind(String kind) {
    switch (kind) {
      case 'nse':
        _uploadNseCsv();
        break;
      case 'etf':
        _uploadEtfCsv();
        break;
      case 'closes':
        _uploadClosingPrices();
        break;
      case 'bse_bhav':
        _uploadBseBhav();
        break;
    }
  }

  Future<void> _runNsePrPull() async {
    setState(() => _uploading = true);
    try {
      await ApiService.pullNsePrDaily();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('NSE PR pull completed'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadImportStatus();
      await _load(page: 1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('NSE PR pull failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
      await _loadImportStatus();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _runBseBhavPull() async {
    setState(() => _uploading = true);
    try {
      await ApiService.pullBseBhavDaily();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('BSE bhav pull completed'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadImportStatus();
      await _load(page: 1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('BSE bhav pull failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
      await _loadImportStatus();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _uploadNseCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read CSV contents'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _uploading = true);
      final summary = await ApiService.importNseCatalog(
        bytes,
        picked.name.isNotEmpty ? picked.name : 'nse.csv',
      );
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'NSE import: created ${summary.created}, updated ${summary.updated}, '
            'skipped ${summary.skipped}, errors ${summary.errors}',
          ),
          backgroundColor:
              summary.errors > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 6),
        ),
      );
      await _load(page: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _uploadEtfCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read CSV contents'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _uploading = true);
      final summary = await ApiService.importEtfCsv(
        bytes,
        picked.name.isNotEmpty ? picked.name : 'etf.csv',
      );
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ETF import: created ${summary.created}, updated ${summary.updated}, '
            'skipped ${summary.skipped}, errors ${summary.errors}',
          ),
          backgroundColor: summary.errors > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 6),
        ),
      );
      await _load(page: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ETF import failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _uploadClosingPrices() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read XLSX contents'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _uploading = true);
      final summary = await ApiService.importClosingPrices(
        bytes,
        picked.name.isNotEmpty ? picked.name : 'gl.xlsx',
      );
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Closes import: created ${summary.created}, updated ${summary.updated}, '
            'skipped ${summary.skipped}, unmatched ${summary.unmatched}, '
            'errors ${summary.errors}',
          ),
          backgroundColor: summary.errors > 0 || summary.unmatched > 0
              ? Colors.orange
              : Colors.green,
          duration: const Duration(seconds: 6),
        ),
      );
      await _load(page: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Closing prices import failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _uploadBseBhav() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read CSV contents'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _uploading = true);
      final summary = await ApiService.importBseBhav(
        bytes,
        picked.name.isNotEmpty ? picked.name : 'bse_bhav.csv',
      );
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'BSE bhav: created ${summary.created}, updated ${summary.updated}, '
            'skipped ${summary.skipped}, errors ${summary.errors}',
          ),
          backgroundColor:
              summary.errors > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 6),
        ),
      );
      await _load(page: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('BSE bhav import failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
      await _loadImportStatus();
    }
  }

  Future<void> _editStock(Stock stock) async {
    final nameController = TextEditingController(text: stock.name);
    final industryController = TextEditingController(text: stock.industry);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update ${stock.symbol}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: industryController,
                decoration: const InputDecoration(
                  labelText: 'Industry',
                  hintText: 'e.g. Software—Infrastructure, Banks—Regional',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) {
      nameController.dispose();
      industryController.dispose();
      return;
    }

    try {
      await ApiService.updateStockAdminFields(
        stock.id,
        name: nameController.text.trim(),
        industry: industryController.text.trim(),
      );
      nameController.dispose();
      industryController.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock updated'),
          backgroundColor: Colors.green,
        ),
      );
      _load();
    } catch (e) {
      nameController.dispose();
      industryController.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = _total == 0 ? 0 : ((_page - 1) * _pageSize) + 1;
    final to = (_page * _pageSize).clamp(0, _total);

    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Update Stock Data'),
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
                    hintText: 'Search symbol, name, or industry…',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(page: 1),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: _industry.isEmpty ? '' : _industry,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Industry',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('All')),
                          ..._industries.map(
                            (i) => DropdownMenuItem(
                              value: i,
                              child: Text(i, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _industry = v ?? '');
                        },
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<String>(
                        value: _series.isEmpty ? '' : _series,
                        decoration: const InputDecoration(
                          labelText: 'Series',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('All')),
                          DropdownMenuItem(value: 'EQ', child: Text('EQ')),
                          DropdownMenuItem(value: 'BE', child: Text('BE')),
                          DropdownMenuItem(value: 'SM', child: Text('SM')),
                          DropdownMenuItem(value: 'ST', child: Text('ST')),
                          DropdownMenuItem(value: 'BZ', child: Text('BZ')),
                          DropdownMenuItem(value: 'IV', child: Text('IV')),
                        ],
                        onChanged: (v) {
                          setState(() => _series = v ?? '');
                        },
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<String>(
                        value: _listingCategory.isEmpty ? '' : _listingCategory,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('All')),
                          DropdownMenuItem(
                            value: 'Listed',
                            child: Text('Listed'),
                          ),
                          DropdownMenuItem(
                            value: 'Permitted',
                            child: Text('Permitted'),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _listingCategory = v ?? '');
                        },
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<String>(
                        value: _pullData.isEmpty ? '' : _pullData,
                        decoration: const InputDecoration(
                          labelText: 'Pull data',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('All')),
                          DropdownMenuItem(value: 'Y', child: Text('Y')),
                          DropdownMenuItem(value: 'N', child: Text('N')),
                        ],
                        onChanged: (v) {
                          setState(() => _pullData = v ?? '');
                        },
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _loading ? null : () => _load(page: 1),
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Search'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  !_hasSearched
                      ? 'Set filters and click Search to load stocks'
                      : _total == 0
                          ? 'No matching stocks'
                          : 'Showing $from–$to of $_total',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: !_hasSearched
                ? const Center(
                    child: Text('Set filters and click Search to load stocks'),
                  )
                : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text('Error: $_error'))
                        : _stocks.isEmpty
                            ? const Center(child: Text('No stocks found'))
                            : RefreshIndicator(
                                onRefresh: () => _load(),
                                child: ListView.builder(
                              itemCount: _stocks.length,
                              itemBuilder: (context, index) {
                                final s = _stocks[index];
                                final meta = <String>[
                                  if (s.name.isNotEmpty) s.name,
                                  if (s.series.isNotEmpty) 'Series: ${s.series}',
                                  if (s.listingCategory.isNotEmpty)
                                    s.listingCategory,
                                  'Pull: ${s.pullData.isEmpty ? "N" : s.pullData}',
                                  if (s.industry.isNotEmpty)
                                    'Industry: ${s.industry}',
                                  if (s.currentPrice > 0)
                                    formatInr(s.currentPrice),
                                ];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      s.symbol,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(meta.join(' · ')),
                                    trailing: const Icon(Icons.edit),
                                    onTap: () => _editStock(s),
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
                    onPressed: _hasSearched && !_loading && _page > 1
                        ? () => _load(page: _page - 1)
                        : null,
                    child: const Text('Previous'),
                  ),
                  Expanded(
                    child: Text(
                      _hasSearched
                          ? 'Page $_page of $_totalPages'
                          : 'Page —',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _hasSearched && !_loading && _page < _totalPages
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
