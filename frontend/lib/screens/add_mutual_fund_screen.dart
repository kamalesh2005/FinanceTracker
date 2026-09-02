import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mutual_fund.dart';
import '../providers/auth_provider.dart';
import '../providers/finance_provider.dart';
import '../services/api_service.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

typedef _CatalogHit = ({
  String isin,
  String symbol,
  String schemeName,
  double currentNav,
});

typedef _MFImportRow = ({
  String schemeName,
  String isin,
  double quantity,
  double nav,
  double currentNav,
});

class AddMutualFundScreen extends StatefulWidget {
  final MutualFund? mutualFund;

  const AddMutualFundScreen({super.key, this.mutualFund});

  @override
  State<AddMutualFundScreen> createState() => _AddMutualFundScreenState();
}

class _AddMutualFundScreenState extends State<AddMutualFundScreen> {
  static const String _manualAddSource = 'Manual Add';

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _schemeNameController;
  late TextEditingController _sourceController;
  late TextEditingController _quantityController;
  late TextEditingController _navController;
  late TextEditingController _currentNavController;
  late DateTime _purchaseDate;

  String? _confirmedIsin;
  String? _confirmedSchemeName;
  String _schemeCode = '';

  List<_CatalogHit> _suggestions = [];
  bool _searching = false;
  String? _searchError;
  Timer? _searchDebounce;
  int _searchSeq = 0;

  bool _isImporting = false;
  bool _isDeletingAll = false;

  bool get _isEdit => widget.mutualFund != null;
  bool get _busy => _isImporting || _isDeletingAll;
  bool get _legacyEdit =>
      _isEdit && (widget.mutualFund!.isin.trim().isEmpty);

  @override
  void initState() {
    super.initState();
    final existing = widget.mutualFund;
    _schemeNameController =
        TextEditingController(text: existing?.schemeName ?? '');
    _schemeCode = existing?.schemeCode ?? '';
    final existingSource = existing?.source.trim() ?? '';
    _sourceController = TextEditingController(
      text: existingSource.isEmpty ? _manualAddSource : existingSource,
    );
    _quantityController =
        TextEditingController(text: existing?.quantity.toString() ?? '');
    _navController =
        TextEditingController(text: existing?.nav.toString() ?? '');
    _currentNavController = TextEditingController(
      text: (existing != null && existing.currentNav > 0)
          ? existing.currentNav.toString()
          : '',
    );
    _purchaseDate = existing?.purchaseDate ?? DateTime.now();

    if (existing != null && existing.isin.trim().isNotEmpty) {
      _confirmedIsin = existing.isin.toUpperCase();
      _confirmedSchemeName = existing.schemeName;
      _schemeCode = existing.schemeCode;
    }

    _schemeNameController.addListener(_onSchemeNameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AuthProvider>().useAsStockWatchList) {
        _quantityController.text = '1';
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _schemeNameController.removeListener(_onSchemeNameChanged);
    _schemeNameController.dispose();
    _sourceController.dispose();
    _quantityController.dispose();
    _navController.dispose();
    _currentNavController.dispose();
    super.dispose();
  }

  void _onSchemeNameChanged() {
    if (_legacyEdit) return;
    final text = _schemeNameController.text;
    if (_confirmedSchemeName != null &&
        _confirmedSchemeName!.toLowerCase() != text.trim().toLowerCase()) {
      _confirmedIsin = null;
      _confirmedSchemeName = null;
      _schemeCode = '';
    }
    _searchDebounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      setState(() {
        _suggestions = [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    if (_confirmedIsin != null &&
        _confirmedSchemeName != null &&
        _confirmedSchemeName!.toLowerCase() == q.toLowerCase()) {
      setState(() {
        _suggestions = [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _runSearch(q);
    });
  }

  Future<void> _runSearch(String query) async {
    final seq = ++_searchSeq;
    try {
      final hits = await ApiService.searchGlobalMutualFunds(query);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _suggestions = hits;
        _searching = false;
        _searchError = null;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _suggestions = [];
        _searching = false;
        _searchError = e.toString();
      });
    }
  }

  void _selectCatalogHit(_CatalogHit hit) {
    _searchDebounce?.cancel();
    setState(() {
      _confirmedIsin = hit.isin.toUpperCase();
      _confirmedSchemeName = hit.schemeName;
      _schemeCode = hit.symbol;
      _suggestions = [];
      _searching = false;
      _searchError = null;
      if (hit.currentNav > 0) {
        _currentNavController.text = hit.currentNav.toString();
      }
    });
    _schemeNameController.removeListener(_onSchemeNameChanged);
    _schemeNameController.text = hit.schemeName;
    _schemeNameController.addListener(_onSchemeNameChanged);
  }

  Future<Uint8List?> _readPickedFileBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes!;
    if (!kIsWeb && file.path != null) {
      return File(file.path!).readAsBytes();
    }
    return null;
  }

  void _showImportError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: 'Close',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteAllFunds() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Funds'),
        content: const Text(
          'This deletes every mutual fund holding and transaction for your account. The fund catalog is not removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAll = true);
    final provider = context.read<FinanceProvider>();
    final ok = await provider.deleteAllMutualFunds();
    if (!mounted) return;
    setState(() => _isDeletingAll = false);
    if (!ok) {
      _showImportError('Error: ${provider.error}');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All mutual funds deleted'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _persistImportedFunds(
    List<_MFImportRow> funds,
    String source,
  ) async {
    final provider = context.read<FinanceProvider>();
    final watchList = context.read<AuthProvider>().useAsStockWatchList;
    final result = await provider.replaceMutualFundsBySource(
      source: source,
      items: funds
          .map(
            (f) => (
              schemeName: f.schemeName,
              isin: f.isin,
              quantity: watchList ? 1.0 : f.quantity,
              nav: f.nav,
              currentNav: f.currentNav,
            ),
          )
          .toList(),
    );
    if (!mounted) return;
    setState(() => _isImporting = false);
    if (provider.error != null || result == null) {
      _showImportError('Error: ${provider.error ?? 'Import failed'}');
      return;
    }
    final unmatchedNote =
        result.unmatched > 0 ? ' (${result.unmatched} pending catalog link)' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved ${result.count} mutual funds$unmatchedNote'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _pickAndImportICICIDirectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      setState(() => _isImporting = true);
      final bytes = await _readPickedFileBytes(result.files.single);
      if (bytes == null) throw Exception('Could not read file contents');

      final funds = _parseICICIMF(bytes);
      if (funds.isEmpty) {
        setState(() => _isImporting = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No funds found. Ensure this is an ICICIDirect MF portfolio Excel export.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(days: 1),
            action: SnackBarAction(
              label: 'Close',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
        return;
      }
      await _persistImportedFunds(funds, 'ICICIDirect');
    } catch (e) {
      setState(() => _isImporting = false);
      _showImportError('Error importing ICICIDirect file: $e');
    }
  }

  Future<void> _pickAndImportHDFCSecFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      setState(() => _isImporting = true);
      final bytes = await _readPickedFileBytes(result.files.single);
      if (bytes == null) throw Exception('Could not read file contents');

      final funds = _parseHDFCMF(bytes);
      if (funds.isEmpty) {
        setState(() => _isImporting = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No funds found. Ensure this is an HDFC Securities MF portfolio Excel export.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(days: 1),
            action: SnackBarAction(
              label: 'Close',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
        return;
      }
      await _persistImportedFunds(funds, 'HDFCSec');
    } catch (e) {
      setState(() => _isImporting = false);
      _showImportError('Error importing HDFCSec file: $e');
    }
  }

  Future<void> _pickAndImportBulkFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      setState(() => _isImporting = true);
      final picked = result.files.single;
      final bytes = await _readPickedFileBytes(picked);
      if (bytes == null) throw Exception('Could not read file contents');

      final extension = picked.extension?.toLowerCase();
      List<_MFImportRow> funds = [];
      if (extension == 'csv') {
        funds = _parseBulkCSV(bytes);
      } else if (extension == 'xlsx' || extension == 'xls') {
        funds = _parseBulkExcel(bytes);
      }

      if (funds.isEmpty) {
        setState(() => _isImporting = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No funds found. Expected columns: scheme name, quantity, buyPrice',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(days: 1),
            action: SnackBarAction(
              label: 'Close',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
        return;
      }
      await _persistImportedFunds(funds, 'Manual Bulk Upload');
    } catch (e) {
      setState(() => _isImporting = false);
      _showImportError('Error importing file: $e');
    }
  }

  // --- Parsing helpers ---

  String _cellText(Data? cell) {
    if (cell?.value == null) return '';
    return cell!.value.toString().trim();
  }

  double _parseNumber(String value) {
    if (value.isEmpty) return 0.0;
    final cleaned = value
        .replaceAll(',', '')
        .replaceAll('₹', '')
        .replaceAll('(', '-')
        .replaceAll(')', '')
        .trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  String _normalizeImportHeader(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Indian ISIN (IN…), including INF mutual-fund ISINs.
  String? _parseIsinFromCell(String raw) {
    if (raw.trim().isEmpty) return null;
    final alnum = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final match = RegExp(r'IN[A-Z0-9]{10}').firstMatch(alnum);
    return match?.group(0);
  }

  bool _isOleOrZipExcel(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final isOle = bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0;
    final isZip = bytes[0] == 0x50 && bytes[1] == 0x4B;
    return isOle || isZip;
  }

  String _decodeSpreadsheetText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  List<List<String>> _parseDelimitedRows(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];

    final delimiter = lines.first.contains('\t')
        ? '\t'
        : (lines.first.contains(',') ? ',' : '\t');

    return lines
        .map(
          (line) => line.split(delimiter).map((cell) => cell.trim()).toList(),
        )
        .toList();
  }

  List<List<String>> _rowsFromExcelBytes(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final rows = <List<String>>[];
    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null || sheet.rows.isEmpty) continue;
      for (final row in sheet.rows) {
        rows.add(row.map((cell) => _cellText(cell)).toList());
      }
    }
    return rows;
  }

  List<List<String>> _rowsFromBytes(Uint8List bytes) {
    if (_isOleOrZipExcel(bytes)) {
      return _rowsFromExcelBytes(bytes);
    }
    return _parseDelimitedRows(_decodeSpreadsheetText(bytes));
  }

  List<_MFImportRow> _parseICICIMF(Uint8List bytes) {
    return _fundsFromICICIRows(_rowsFromBytes(bytes));
  }

  List<_MFImportRow> _fundsFromICICIRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    int? headerRowIndex;
    int schemeCol = -1;
    int qtyCol = -1;
    int buyPriceCol = -1;
    int currentNavCol = -1;

    for (var i = 0; i < rows.length; i++) {
      final headers = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final header = _normalizeImportHeader(rows[i][j]);
        if (header.isNotEmpty) headers[header] = j;
      }

      final hasScheme = headers.containsKey('scheme');
      final hasUnitsHeld = headers.keys.any(
        (h) => h == 'units held' || h.contains('units held'),
      );
      final hasAvgCost = headers.keys.any(
        (h) =>
            h.contains('average cost price') || h.contains('avg cost'),
      );

      if (hasScheme && hasUnitsHeld && hasAvgCost) {
        headerRowIndex = i;
        schemeCol = headers['scheme']!;
        qtyCol = headers.entries
            .firstWhere(
              (e) => e.key == 'units held' || e.key.contains('units held'),
            )
            .value;
        buyPriceCol = headers.entries
            .firstWhere(
              (e) =>
                  e.key.contains('average cost price') ||
                  e.key.contains('avg cost'),
            )
            .value;
        // Prefer exact "Last Recorded NAV"; do not match "Last Recorded NAV On"
        // (date column), which also contains that phrase.
        currentNavCol = -1;
        for (final entry in headers.entries) {
          if (entry.key == 'last recorded nav') {
            currentNavCol = entry.value;
            break;
          }
        }
        if (currentNavCol < 0) {
          for (final entry in headers.entries) {
            if (entry.key.contains('last recorded nav') &&
                !entry.key.contains('nav on') &&
                !entry.key.contains('date')) {
              currentNavCol = entry.value;
              break;
            }
          }
        }
        break;
      }
    }

    if (headerRowIndex == null ||
        schemeCol < 0 ||
        qtyCol < 0 ||
        buyPriceCol < 0) {
      return [];
    }

    final funds = <_MFImportRow>[];
    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      try {
        final schemeName =
            schemeCol < row.length ? row[schemeCol].trim() : '';
        if (schemeName.isEmpty ||
            schemeName.toLowerCase().contains('total') ||
            schemeName.toLowerCase() == 'scheme') {
          continue;
        }
        final quantity = qtyCol < row.length ? _parseNumber(row[qtyCol]) : 0.0;
        final nav =
            buyPriceCol < row.length ? _parseNumber(row[buyPriceCol]) : 0.0;
        if (quantity <= 0 || nav <= 0) continue;
        final currentNav = currentNavCol >= 0 && currentNavCol < row.length
            ? _parseNumber(row[currentNavCol])
            : 0.0;
        funds.add((
          schemeName: schemeName,
          isin: '',
          quantity: quantity,
          nav: nav,
          currentNav: currentNav,
        ));
      } catch (_) {
        continue;
      }
    }
    return funds;
  }

  List<_MFImportRow> _parseHDFCMF(Uint8List bytes) {
    return _fundsFromHDFCRows(_rowsFromBytes(bytes));
  }

  List<_MFImportRow> _fundsFromHDFCRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    int? headerRowIndex;
    int schemeCol = -1;
    int isinCol = -1;
    int qtyCol = -1;
    int buyPriceCol = -1;
    int currentNavCol = -1;

    for (var i = 0; i < rows.length; i++) {
      final headers = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final header = _normalizeImportHeader(rows[i][j]);
        if (header.isNotEmpty) headers[header] = j;
      }

      final hasSchemeName = headers.keys.any(
        (h) => h == 'scheme name' || h.contains('scheme name'),
      );
      final hasUnits = headers.keys.any(
        (h) => h == 'units' || (h.contains('units') && !h.contains('nearing')),
      );
      final hasAvgCost = headers.keys.any(
        (h) =>
            h.contains('average cost price') ||
            h.contains('avg cost') ||
            h.contains('average cost'),
      );

      if (hasSchemeName && hasUnits && hasAvgCost) {
        headerRowIndex = i;
        schemeCol = headers.entries
            .firstWhere(
              (e) => e.key == 'scheme name' || e.key.contains('scheme name'),
            )
            .value;
        qtyCol = headers['units'] ??
            headers.entries
                .firstWhere(
                  (e) =>
                      e.key.contains('units') && !e.key.contains('nearing'),
                )
                .value;
        buyPriceCol = headers.entries
            .firstWhere(
              (e) =>
                  e.key.contains('average cost price') ||
                  e.key.contains('average cost') ||
                  e.key.contains('avg cost'),
            )
            .value;
        isinCol = -1;
        for (final entry in headers.entries) {
          if (entry.key == 'isin' || entry.key.contains('isin')) {
            isinCol = entry.value;
            break;
          }
        }
        currentNavCol = -1;
        for (final entry in headers.entries) {
          // Prefer exact "nav" over columns that mention nav in longer labels
          // (e.g. avoid mistaking average cost). Skip buy-price-like headers.
          if (entry.key == 'nav' ||
              (entry.key.endsWith(' nav') &&
                  !entry.key.contains('cost') &&
                  !entry.key.contains('average') &&
                  !entry.key.contains('purchase'))) {
            currentNavCol = entry.value;
            if (entry.key == 'nav') break;
          }
        }
        break;
      }
    }

    if (headerRowIndex == null ||
        schemeCol < 0 ||
        qtyCol < 0 ||
        buyPriceCol < 0) {
      return [];
    }

    final funds = <_MFImportRow>[];
    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      try {
        final schemeName =
            schemeCol < row.length ? row[schemeCol].trim() : '';
        if (schemeName.isEmpty ||
            schemeName.toLowerCase().contains('total') ||
            schemeName.toLowerCase() == 'scheme name') {
          continue;
        }
        final quantity = qtyCol < row.length ? _parseNumber(row[qtyCol]) : 0.0;
        final nav =
            buyPriceCol < row.length ? _parseNumber(row[buyPriceCol]) : 0.0;
        if (quantity <= 0 || nav <= 0) continue;
        final isinRaw =
            isinCol >= 0 && isinCol < row.length ? row[isinCol].trim() : '';
        final isin = _parseIsinFromCell(isinRaw) ?? '';
        final currentNav = currentNavCol >= 0 && currentNavCol < row.length
            ? _parseNumber(row[currentNavCol])
            : 0.0;
        funds.add((
          schemeName: schemeName,
          isin: isin,
          quantity: quantity,
          nav: nav,
          currentNav: currentNav,
        ));
      } catch (_) {
        continue;
      }
    }
    return funds;
  }

  List<_MFImportRow> _parseBulkCSV(Uint8List bytes) {
    final input = utf8.decode(bytes);
    final fields = const CsvToListConverter().convert(input);
    if (fields.isEmpty) return [];
    final rows = fields
        .map((row) => row.map((cell) => cell.toString().trim()).toList())
        .toList();
    return _fundsFromBulkRows(rows);
  }

  List<_MFImportRow> _parseBulkExcel(Uint8List bytes) {
    return _fundsFromBulkRows(_rowsFromBytes(bytes));
  }

  List<_MFImportRow> _fundsFromBulkRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    int? headerRowIndex;
    int nameCol = -1;
    int qtyCol = -1;
    int priceCol = -1;
    int currentNavCol = -1;

    for (var i = 0; i < rows.length; i++) {
      final headers = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final header = _normalizeImportHeader(rows[i][j]);
        if (header.isNotEmpty) headers[header] = j;
      }

      int findName() {
        for (final key in [
          'scheme name',
          'schemename',
          'scheme',
          'name',
        ]) {
          if (headers.containsKey(key)) return headers[key]!;
        }
        for (final e in headers.entries) {
          if (e.key.contains('scheme name') || e.key == 'scheme') {
            return e.value;
          }
        }
        return -1;
      }

      int findQty() {
        for (final key in ['quantity', 'qty', 'units']) {
          if (headers.containsKey(key)) return headers[key]!;
        }
        for (final e in headers.entries) {
          if (e.key.contains('quantity') ||
              e.key.contains('qty') ||
              e.key.contains('units')) {
            return e.value;
          }
        }
        return -1;
      }

      int findPrice() {
        for (final key in [
          'buyprice',
          'buy price',
          'purchase nav',
          'average cost price',
          'avg cost',
        ]) {
          if (headers.containsKey(key)) return headers[key]!;
        }
        for (final e in headers.entries) {
          if (e.key.contains('buyprice') ||
              e.key.contains('buy price') ||
              e.key.contains('purchase nav') ||
              e.key.contains('average cost')) {
            return e.value;
          }
        }
        // "nav" alone is buy price only when there is no separate current nav column
        if (headers.containsKey('nav')) return headers['nav']!;
        return -1;
      }

      int findCurrentNav() {
        for (final key in [
          'current nav',
          'currentnav',
          'last recorded nav',
        ]) {
          if (headers.containsKey(key)) return headers[key]!;
        }
        for (final e in headers.entries) {
          if (e.key.contains('current nav') ||
              e.key.contains('last recorded nav')) {
            return e.value;
          }
        }
        return -1;
      }

      final n = findName();
      final q = findQty();
      final p = findPrice();
      if (n >= 0 && q >= 0 && p >= 0) {
        headerRowIndex = i;
        nameCol = n;
        qtyCol = q;
        priceCol = p;
        currentNavCol = findCurrentNav();
        // If buy price used plain "nav" and we also found current nav elsewhere,
        // keep both. If only one "nav" column exists, it is buy price (currentNav=0).
        if (currentNavCol == priceCol) {
          currentNavCol = -1;
        }
        break;
      }
    }

    // Fallback: no header — assume scheme name, quantity, buyPrice
    if (headerRowIndex == null) {
      if (rows.first.length < 3) return [];
      headerRowIndex = -1;
      nameCol = 0;
      qtyCol = 1;
      priceCol = 2;
      currentNavCol = rows.first.length >= 4 ? 3 : -1;
    }

    final funds = <_MFImportRow>[];
    final start = headerRowIndex + 1;
    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) continue;
      try {
        final schemeName = nameCol < row.length ? row[nameCol].trim() : '';
        if (schemeName.isEmpty) continue;
        final lower = schemeName.toLowerCase();
        if (lower == 'scheme name' ||
            lower == 'scheme' ||
            lower == 'name' ||
            lower.contains('total')) {
          continue;
        }
        final quantity = qtyCol < row.length ? _parseNumber(row[qtyCol]) : 0.0;
        final nav =
            priceCol < row.length ? _parseNumber(row[priceCol]) : 0.0;
        if (quantity <= 0 || nav <= 0) continue;
        final currentNav = currentNavCol >= 0 && currentNavCol < row.length
            ? _parseNumber(row[currentNavCol])
            : 0.0;
        funds.add((
          schemeName: schemeName,
          isin: '',
          quantity: quantity,
          nav: nav,
          currentNav: currentNav,
        ));
      } catch (_) {
        continue;
      }
    }
    return funds;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBrandTitle(
          widget.mutualFund == null ? 'Add Mutual Fund' : 'Edit Mutual Fund',
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            if (!_isEdit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: OutlinedButton(
                  onPressed: _busy ? null : _confirmAndDeleteAllFunds,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade700),
                  ),
                  child: _isDeletingAll
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Delete All Funds'),
                ),
              ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (!_isEdit) ...[
                _buildImportCard(),
                const SizedBox(height: 16),
                Card(
                  color: Colors.indigo.shade50,
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    leading:
                        Icon(Icons.edit_note, color: Colors.indigo.shade700),
                    title: Text(
                      'Manual Add - Single Fund',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                    subtitle: const Text(
                      'Search catalog and enter units and purchase NAV',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildManualFormFields(),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                ..._buildManualFormFields(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_balance, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Import ICICIDirect Excel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload ICICIDirect MF portfolio (Scheme, Units Held, Average Cost Price). Account: ICICIDirect.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _busy ? null : _pickAndImportICICIDirectFile,
              icon: _isImporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(
                _isImporting ? 'Importing...' : 'Select ICICIDirect File',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.account_balance_wallet, color: Colors.teal),
                SizedBox(width: 8),
                Text(
                  'Import HDFC Securities Excel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload HDFC MF portfolio (Scheme Name, Units, Average Cost Price). Account: HDFCSec. ISIN used if scheme name does not match.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _busy ? null : _pickAndImportHDFCSecFile,
              icon: _isImporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(
                _isImporting ? 'Importing...' : 'Select HDFCSec File',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.hourglass_empty, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  'Import Zerodha Excel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Coming soon — Zerodha MF export format is not available yet.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.upload_file),
              label: const Text('Coming soon'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.indigo.shade200,
                disabledForegroundColor: Colors.white70,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.upload_file, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Bulk Upload',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Upload a CSV or Excel file with columns: scheme name, quantity, buyPrice. Account: Manual Bulk Upload.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _busy ? null : _pickAndImportBulkFile,
              icon: _isImporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_upload),
              label: Text(_isImporting ? 'Importing...' : 'Select File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildManualFormFields() {
    return [
      if (_legacyEdit)
        TextFormField(
          controller: _schemeNameController,
          decoration: const InputDecoration(
            labelText: 'Scheme Name *',
            border: OutlineInputBorder(),
            helperText: 'Legacy holding — re-select from catalog to link ISIN',
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter scheme name';
            }
            return null;
          },
        )
      else ...[
        TextFormField(
          controller: _schemeNameController,
          decoration: InputDecoration(
            labelText: 'Scheme Name *',
            hintText: 'Start typing to search catalog',
            border: const OutlineInputBorder(),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            helperText: _confirmedIsin != null
                ? 'ISIN: $_confirmedIsin'
                : 'Choose a scheme from Global Mutual Funds',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter scheme name';
            }
            if (_confirmedIsin == null) {
              return 'Select a scheme from the search results';
            }
            return null;
          },
        ),
        if (_searchError != null) ...[
          const SizedBox(height: 8),
          Text(
            _searchError!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final option = _suggestions[index];
                  final nav = option.currentNav > 0
                      ? ' · ${formatInr(option.currentNav)}'
                      : '';
                  return ListTile(
                    dense: true,
                    title: Text(option.schemeName),
                    subtitle: Text(
                      '${option.isin}'
                      '${option.symbol.isNotEmpty ? ' · ${option.symbol}' : ''}'
                      '$nav',
                    ),
                    onTap: () => _selectCatalogHit(option),
                  );
                },
              ),
            ),
          ),
        ],
      ],
      const SizedBox(height: 16),
      Builder(
        builder: (context) {
          final watchList =
              context.watch<AuthProvider>().useAsStockWatchList;
          if (watchList && _quantityController.text != '1') {
            _quantityController.text = '1';
          }
          return TextFormField(
            controller: _quantityController,
            enabled: !watchList,
            decoration: InputDecoration(
              labelText: 'Units *',
              hintText: watchList ? 'Fixed to 1 (watch list)' : 'e.g., 100',
              border: const OutlineInputBorder(),
              helperText: watchList
                  ? 'Watch list mode always saves units as 1'
                  : null,
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter units';
              }
              if (double.tryParse(value) == null) {
                return 'Please enter a valid number';
              }
              return null;
            },
          );
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _navController,
        decoration: const InputDecoration(
          labelText: 'Purchase NAV (₹) *',
          hintText: 'e.g., 50.25',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter purchase NAV';
          }
          if (double.tryParse(value) == null) {
            return 'Please enter a valid number';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _currentNavController,
        readOnly: !_legacyEdit,
        decoration: InputDecoration(
          labelText: 'Current NAV (₹)',
          hintText:
              _legacyEdit ? 'e.g., 55.75' : 'From catalog (optional)',
          border: const OutlineInputBorder(),
          helperText: _legacyEdit
              ? null
              : 'Not required — filled from Global Mutual Funds when available',
        ),
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _sourceController,
        decoration: const InputDecoration(
          labelText: 'Account *',
          hintText: 'e.g., Manual Add, Zerodha, Groww',
          border: OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter account';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Purchase Date'),
        subtitle: Text('${_purchaseDate.toLocal()}'.split(' ')[0]),
        trailing: const Icon(Icons.calendar_today),
        onTap: () async {
          final DateTime? picked = await showDatePicker(
            context: context,
            initialDate: _purchaseDate,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
          );
          if (picked != null && picked != _purchaseDate) {
            setState(() => _purchaseDate = picked);
          }
        },
      ),
      const SizedBox(height: 24),
      Consumer<FinanceProvider>(
        builder: (context, provider, child) {
          return ElevatedButton(
            onPressed: provider.isLoading
                ? null
                : () async {
                    if (_formKey.currentState!.validate()) {
                      final watchList = context
                          .read<AuthProvider>()
                          .useAsStockWatchList;
                      final mf = MutualFund(
                        id: widget.mutualFund?.id ?? 0,
                        isin: _confirmedIsin ??
                            widget.mutualFund?.isin ??
                            '',
                        schemeCode: _schemeCode.isNotEmpty
                            ? _schemeCode
                            : (widget.mutualFund?.schemeCode ?? ''),
                        schemeName: _schemeNameController.text.trim(),
                        sourceSchemeName:
                            widget.mutualFund?.sourceSchemeName ?? '',
                        fundHouse: widget.mutualFund?.fundHouse ?? '',
                        source: _sourceController.text.trim().isEmpty
                            ? _manualAddSource
                            : _sourceController.text.trim(),
                        quantity: watchList
                            ? 1
                            : double.parse(_quantityController.text),
                        nav: double.parse(_navController.text),
                        currentNav: _currentNavController.text.isEmpty
                            ? 0.0
                            : double.parse(_currentNavController.text),
                        purchaseDate: _purchaseDate,
                        createdAt:
                            widget.mutualFund?.createdAt ?? DateTime.now(),
                        updatedAt: DateTime.now(),
                      );

                      if (widget.mutualFund == null) {
                        await provider.addMutualFund(mf);
                      } else {
                        await provider.updateMutualFund(
                          widget.mutualFund!.id,
                          mf,
                        );
                      }

                      if (provider.error != null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${provider.error}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                        return;
                      }

                      if (context.mounted) Navigator.pop(context);
                    }
                  },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: provider.isLoading
                ? const CircularProgressIndicator()
                : Text(
                    widget.mutualFund == null
                        ? 'Add Mutual Fund'
                        : 'Update Mutual Fund',
                  ),
          );
        },
      ),
    ];
  }
}
