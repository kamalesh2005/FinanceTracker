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

import '../models/stock.dart';
import '../providers/finance_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

class AddStockScreen extends StatefulWidget {
  final Stock? stock;

  const AddStockScreen({super.key, this.stock});

  @override
  State<AddStockScreen> createState() => _AddStockScreenState();
}

class _AddStockScreenState extends State<AddStockScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _symbolController;
  late TextEditingController _quantityController;
  late TextEditingController _buyPriceController;
  final _symbolFocusNode = FocusNode();
  late DateTime _transactionDate;
  List<Stock> _importedStocks = [];
  bool _isImporting = false;
  bool _isSavingImported = false;
  String? _importSource;
  /// True when Buy Price was last set from a Global_Stocks LTP lookup.
  bool _buyPriceFromLtp = false;
  String? _ltpLookupSymbol;
  /// Catalog symbol confirmed via autocomplete selection or exact lookup.
  String? _confirmedCatalogSymbol;
  String? _confirmedCatalogName;

  @override
  void initState() {
    super.initState();
    _symbolController = TextEditingController(text: widget.stock?.symbol ?? '');
    _quantityController = TextEditingController(
      text: widget.stock?.quantity.toString() ?? '',
    );
    _buyPriceController =
        TextEditingController(text: widget.stock?.buyPrice.toString() ?? '');
    _transactionDate = DateTime.now();
    if (widget.stock != null) {
      _confirmedCatalogSymbol = widget.stock!.symbol.toUpperCase();
      _confirmedCatalogName = widget.stock!.name;
    }
    _symbolFocusNode.addListener(() {
      if (!_symbolFocusNode.hasFocus) {
        _confirmCatalogExactMatch();
        _tryPrefillBuyPriceFromLtp();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AuthProvider>().useAsStockWatchList) {
        _quantityController.text = '1';
        setState(() {});
      }
      if (widget.stock == null && _symbolController.text.trim().isNotEmpty) {
        _confirmCatalogExactMatch();
        _tryPrefillBuyPriceFromLtp();
      }
    });
  }

  @override
  void dispose() {
    _symbolFocusNode.dispose();
    _symbolController.dispose();
    _quantityController.dispose();
    _buyPriceController.dispose();
    super.dispose();
  }

  String _formatPrice(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    final fixed = value.toStringAsFixed(2);
    if (fixed.endsWith('0')) {
      return value.toStringAsFixed(1);
    }
    return fixed;
  }

  Future<void> _tryPrefillBuyPriceFromLtp() async {
    final symbol = _symbolController.text.trim().toUpperCase();
    if (symbol.isEmpty) return;
    if (_ltpLookupSymbol == symbol) return;

    // Prefer an already-loaded holding (same Global_Stocks LTP) for instant fill.
    final local = context.read<FinanceProvider>().stocks.where(
          (s) => s.symbol.toUpperCase() == symbol && s.currentPrice > 0,
        );
    if (local.isNotEmpty) {
      _applyLtpToBuyPrice(symbol, local.first.currentPrice);
      return;
    }

    try {
      final hit = await ApiService.lookupGlobalStock(symbol);
      if (!mounted) return;
      if (hit == null || hit.currentPrice <= 0) {
        _ltpLookupSymbol = symbol;
        return;
      }
      _applyLtpToBuyPrice(symbol, hit.currentPrice);
    } catch (_) {
      // Lookup is best-effort; leave Buy Price as the user entered it.
    }
  }

  void _applyLtpToBuyPrice(String symbol, double ltp) {
    final buyEmpty = _buyPriceController.text.trim().isEmpty;
    if (!buyEmpty && !_buyPriceFromLtp) {
      _ltpLookupSymbol = symbol;
      return;
    }
    setState(() {
      _buyPriceController.text = _formatPrice(ltp);
      _buyPriceFromLtp = true;
      _ltpLookupSymbol = symbol;
    });
  }

  void _selectCatalogHit(
    ({String symbol, String name, double currentPrice}) hit,
  ) {
    final symbol = hit.symbol.toUpperCase();
    setState(() {
      _symbolController.text = symbol;
      _symbolController.selection = TextSelection.collapsed(offset: symbol.length);
      _confirmedCatalogSymbol = symbol;
      _confirmedCatalogName = hit.name;
    });
    if (hit.currentPrice > 0) {
      _applyLtpToBuyPrice(symbol, hit.currentPrice);
    }
  }

  Future<void> _confirmCatalogExactMatch() async {
    if (widget.stock != null) return;
    final symbol = _symbolController.text.trim().toUpperCase();
    if (symbol.isEmpty) return;
    if (_confirmedCatalogSymbol == symbol) return;
    try {
      final hit = await ApiService.lookupGlobalStock(symbol);
      if (!mounted) return;
      if (hit == null) {
        setState(() {
          _confirmedCatalogSymbol = null;
          _confirmedCatalogName = null;
        });
        return;
      }
      _selectCatalogHit(hit);
    } catch (_) {
      // Best-effort; validator will block submit if unconfirmed.
    }
  }

  Future<List<({String symbol, String name, double currentPrice})>>
      _searchCatalog(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      return await ApiService.searchGlobalStocks(q);
    } catch (_) {
      return [];
    }
  }

  Future<Uint8List?> _readPickedFileBytes(PlatformFile file) async {
    if (file.bytes != null) {
      return file.bytes!;
    }
    // path is unavailable on web and throws if accessed
    if (!kIsWeb && file.path != null) {
      return File(file.path!).readAsBytes();
    }
    return null;
  }

  Future<void> _pickAndImportFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _isImporting = true;
        });

        final picked = result.files.single;
        final bytes = await _readPickedFileBytes(picked);
        if (bytes == null) {
          throw Exception('Could not read file contents');
        }

        final extension = picked.extension?.toLowerCase();
        List<Stock> stocks = [];

        if (extension == 'csv') {
          stocks = _parseCSV(bytes);
        } else if (extension == 'xlsx' || extension == 'xls') {
          stocks = _parseExcel(bytes);
        }

        setState(() {
          _importedStocks = stocks;
          _importSource = 'Manual Bulk Upload';
          _isImporting = false;
        });

        if (stocks.isNotEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully imported ${stocks.length} stocks'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing file: $e'),
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
    }
  }

  Future<void> _pickAndImportICICIDirectFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _isImporting = true;
        });

        final bytes = await _readPickedFileBytes(result.files.single);
        if (bytes == null) {
          throw Exception('Could not read file contents');
        }

        final stocks = _parseICICIDirectExcel(bytes);

        setState(() {
          _importedStocks = stocks;
          _importSource = 'ICICIDirect';
          _isImporting = false;
        });

        if (stocks.isNotEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully imported ${stocks.length} stocks from ICICIDirect'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No stocks found. Ensure this is an ICICIDirect portfolio Excel export.'),
              backgroundColor: Colors.orange,
              duration: const Duration(days: 1),
              action: SnackBarAction(
                label: 'Close',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing ICICIDirect file: $e'),
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
    }
  }

  Future<void> _pickAndImportHDFCSecFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _isImporting = true;
        });

        final bytes = await _readPickedFileBytes(result.files.single);
        if (bytes == null) {
          throw Exception('Could not read file contents');
        }

        final stocks = _parseHDFCSecCSV(bytes);

        setState(() {
          _importedStocks = stocks;
          _importSource = 'HDFCSec';
          _isImporting = false;
        });

        if (stocks.isNotEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully imported ${stocks.length} stocks from HDFCSec'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'No stocks found. Ensure this is an HDFC Securities portfolio CSV export.',
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
        }
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing HDFCSec file: $e'),
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
    }
  }

  Future<void> _pickAndImportZerodhaFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _isImporting = true;
        });

        final bytes = await _readPickedFileBytes(result.files.single);
        if (bytes == null) {
          throw Exception('Could not read file contents');
        }

        final stocks = _parseZerodhaExcel(bytes);

        setState(() {
          _importedStocks = stocks;
          _importSource = 'Zerodha';
          _isImporting = false;
        });

        if (stocks.isNotEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully imported ${stocks.length} stocks from Zerodha'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'No stocks found. Ensure this is a Zerodha holdings Excel export.',
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
        }
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing Zerodha file: $e'),
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
    }
  }

  List<Stock> _parseCSV(Uint8List bytes) {
    final input = utf8.decode(bytes);
    final fields = const CsvToListConverter().convert(input);

    if (fields.isEmpty) return [];

    // Assume first row is header, skip it
    final dataRows = fields.skip(1).toList();
    List<Stock> stocks = [];

    // Expected columns: symbol, quantity, buyPrice
    for (var row in dataRows) {
      if (row.length < 3) continue;

      try {
        final symbol = row[0].toString().trim().toUpperCase();
        final quantity = double.parse(row[1].toString());
        final buyPrice = double.parse(row[2].toString());
        if (symbol.isEmpty || quantity == 0 || buyPrice == 0) continue;

        final stock = Stock(
          id: 0,
          symbol: symbol,
          name: '',
          quantity: quantity,
          buyPrice: buyPrice,
          currentPrice: 0.0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        stocks.add(stock);
      } catch (e) {
        // Skip invalid rows
        continue;
      }
    }

    return stocks;
  }

  List<Stock> _parseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);

    List<Stock> stocks = [];

    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null || sheet.rows.isEmpty) continue;

      // Skip header row
      final dataRows = sheet.rows.skip(1).toList();

      for (var row in dataRows) {
        if (row.length < 3) continue;

        try {
          final symbol = row[0]?.value?.toString().trim() ?? '';
          final quantity = double.parse(row[1]?.value?.toString() ?? '0');
          final buyPrice = double.parse(row[2]?.value?.toString() ?? '0');

          if (symbol.isEmpty || quantity == 0 || buyPrice == 0) continue;

          final stock = Stock(
            id: 0,
            symbol: symbol.toUpperCase(),
            name: '',
            quantity: quantity,
            buyPrice: buyPrice,
            currentPrice: 0.0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          stocks.add(stock);
        } catch (e) {
          // Skip invalid rows
          continue;
        }
      }
    }

    return stocks;
  }

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

  /// Extracts a 12-char Indian ISIN (INE…) from spreadsheet cell text.
  String? _parseIsinFromCell(String raw) {
    if (raw.trim().isEmpty) return null;
    final alnum = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final match = RegExp(r'INE[A-Z0-9]{9}[0-9]').firstMatch(alnum);
    if (match == null) return null;
    return match.group(0);
  }

  bool _isOleOrZipExcel(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // OLE Compound Document (.xls BIFF)
    final isOle = bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0;
    // ZIP archive (.xlsx)
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
        .map((line) => line.split(delimiter).map((cell) => cell.trim()).toList())
        .toList();
  }

  List<List<String>> _parseHtmlTableRows(String html) {
    final rows = <List<String>>[];
    final rowRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
    final cellRegex = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true);

    for (final rowMatch in rowRegex.allMatches(html)) {
      final cells = <String>[];
      for (final cellMatch in cellRegex.allMatches(rowMatch.group(1)!)) {
        final raw = cellMatch.group(1)!
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll('&nbsp;', ' ')
            .replaceAll('&amp;', '&')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        cells.add(raw);
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
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

  List<Stock> _stocksFromICICIDirectRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    final now = DateTime.now();
    final stocks = <Stock>[];

    int? headerRowIndex;
    int symbolCol = -1;
    int nameCol = -1;
    int qtyCol = -1;
    int buyPriceCol = -1;
    int currentPriceCol = -1;
    int isinCol = -1;

    for (var i = 0; i < rows.length; i++) {
      final headers = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final header = _normalizeImportHeader(rows[i][j]);
        if (header.isNotEmpty) {
          headers[header] = j;
        }
      }

      final hasStockSymbol = headers.keys.any((h) => h.contains('stock symbol'));
      final hasQty = headers.keys.any((h) => h == 'qty' || h.contains('qty'));
      final hasAvgCost = headers.keys.any(
        (h) => h.contains('average cost price') || h.contains('avg cost'),
      );

      if (hasStockSymbol && hasQty && hasAvgCost) {
        headerRowIndex = i;
        symbolCol = headers.entries
            .firstWhere((e) => e.key.contains('stock symbol'))
            .value;
        nameCol = -1;
        for (final entry in headers.entries) {
          if (entry.key.contains('company name')) {
            nameCol = entry.value;
            break;
          }
        }
        qtyCol = headers.entries
            .firstWhere((e) => e.key == 'qty' || e.key.contains('qty'))
            .value;
        buyPriceCol = headers.entries
            .firstWhere(
              (e) =>
                  e.key.contains('average cost price') ||
                  e.key.contains('avg cost'),
            )
            .value;
        currentPriceCol = -1;
        for (final entry in headers.entries) {
          if (entry.key.contains('current market price')) {
            currentPriceCol = entry.value;
            break;
          }
        }
        for (final entry in headers.entries) {
          if (entry.key.contains('isin')) {
            isinCol = entry.value;
            break;
          }
        }
        break;
      }
    }

    if (headerRowIndex == null || symbolCol < 0 || qtyCol < 0 || buyPriceCol < 0) {
      return [];
    }

    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      try {
        final symbol = symbolCol < row.length ? row[symbolCol].trim() : '';
        if (symbol.isEmpty ||
            symbol.toLowerCase().contains('total') ||
            symbol.toLowerCase() == 'stock symbol') {
          continue;
        }

        final name = nameCol >= 0 && nameCol < row.length ? row[nameCol].trim() : '';
        final quantity =
            qtyCol < row.length ? _parseNumber(row[qtyCol]) : 0.0;
        final buyPrice = buyPriceCol < row.length
            ? _parseNumber(row[buyPriceCol])
            : 0.0;
        final currentPrice = currentPriceCol >= 0 && currentPriceCol < row.length
            ? _parseNumber(row[currentPriceCol])
            : 0.0;
        final isinRaw = isinCol >= 0 && isinCol < row.length ? row[isinCol].trim() : '';
        final isin = isinRaw.isEmpty ? null : isinRaw.toUpperCase();

        if (quantity == 0) continue;

        stocks.add(
          Stock(
            id: 0,
            symbol: symbol.toUpperCase(),
            name: name,
            quantity: quantity,
            buyPrice: buyPrice,
            currentPrice: currentPrice,
            createdAt: now,
            updatedAt: now,
            isin: isin,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    return stocks;
  }

  List<Stock> _parseICICIDirectExcel(Uint8List bytes) {
    List<List<String>> rows;

    if (_isOleOrZipExcel(bytes)) {
      rows = _rowsFromExcelBytes(bytes);
    } else {
      final text = _decodeSpreadsheetText(bytes);
      final lower = text.toLowerCase();
      if (lower.contains('<table') || lower.contains('<html')) {
        rows = _parseHtmlTableRows(text);
      } else {
        // ICICIDirect often exports tab-separated text with a .xls extension
        rows = _parseDelimitedRows(text);
      }
    }

    final stocks = _stocksFromICICIDirectRows(rows);
    if (stocks.isNotEmpty) return stocks;

    // Fallback: try the other strategies if header mapping failed
    if (_isOleOrZipExcel(bytes)) {
      final text = _decodeSpreadsheetText(bytes);
      return _stocksFromICICIDirectRows(_parseDelimitedRows(text));
    }

    try {
      return _stocksFromICICIDirectRows(_rowsFromExcelBytes(bytes));
    } catch (_) {
      return stocks;
    }
  }

  List<Stock> _parseHDFCSecCSV(Uint8List bytes) {
    final input = utf8.decode(bytes);
    final fields = const CsvToListConverter().convert(input);
    if (fields.isEmpty) return [];

    final rows = fields
        .map((row) => row.map((cell) => cell.toString().trim()).toList())
        .toList();
    return _stocksFromHDFCSecRows(rows);
  }

  List<Stock> _stocksFromHDFCSecRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    final now = DateTime.now();
    final stocks = <Stock>[];

    int? headerRowIndex;
    int symbolCol = -1;
    int qtyCol = -1;
    int buyPriceCol = -1;
    int currentPriceCol = -1;

    for (var i = 0; i < rows.length; i++) {
      final headers = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final header = _normalizeImportHeader(rows[i][j]);
        if (header.isNotEmpty) {
          headers[header] = j;
        }
      }

      final hasSymbol = headers.keys.any((h) => h == 'symbol' || h.contains('symbol'));
      final hasQty = headers.keys.any((h) => h == 'qty' || h.contains('qty'));
      final hasAvgPrice = headers.keys.any(
        (h) => h.contains('avg price') || h.contains('average price'),
      );

      if (hasSymbol && hasQty && hasAvgPrice) {
        headerRowIndex = i;
        symbolCol = headers['symbol'] ??
            headers.entries
                .firstWhere((e) => e.key.contains('symbol'))
                .value;
        // Prefer exact "qty" over "long term qty"
        qtyCol = headers['qty'] ??
            headers.entries
                .firstWhere((e) => e.key.contains('qty'))
                .value;
        buyPriceCol = headers.entries
            .firstWhere(
              (e) =>
                  e.key.contains('avg price') || e.key.contains('average price'),
            )
            .value;
        currentPriceCol = -1;
        if (headers.containsKey('ltp')) {
          currentPriceCol = headers['ltp']!;
        } else {
          for (final entry in headers.entries) {
            if (entry.key.contains('ltp')) {
              currentPriceCol = entry.value;
              break;
            }
          }
        }
        break;
      }
    }

    if (headerRowIndex == null || symbolCol < 0 || qtyCol < 0 || buyPriceCol < 0) {
      return [];
    }

    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      // Skip summary/empty rows: third column must not be empty
      if (row.length < 3 || row[2].trim().isEmpty) continue;

      try {
        final symbol = symbolCol < row.length ? row[symbolCol].trim() : '';
        if (symbol.isEmpty ||
            symbol.toLowerCase().contains('total') ||
            symbol.toLowerCase() == 'symbol') {
          continue;
        }

        final quantity = qtyCol < row.length ? _parseNumber(row[qtyCol]) : 0.0;
        final buyPrice =
            buyPriceCol < row.length ? _parseNumber(row[buyPriceCol]) : 0.0;
        final currentPrice =
            currentPriceCol >= 0 && currentPriceCol < row.length
                ? _parseNumber(row[currentPriceCol])
                : 0.0;

        if (quantity == 0) continue;

        stocks.add(
          Stock(
            id: 0,
            symbol: symbol.toUpperCase(),
            name: '',
            quantity: quantity,
            buyPrice: buyPrice,
            currentPrice: currentPrice,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    return stocks;
  }

  List<Stock> _parseZerodhaExcel(Uint8List bytes) {
    final rows = _rowsFromExcelBytes(bytes);
    return _stocksFromZerodhaRows(rows);
  }

  List<Stock> _stocksFromZerodhaRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    final now = DateTime.now();
    final stocks = <Stock>[];

    int? headerRowIndex;
    int symbolCol = -1;
    int isinCol = -1;
    int sectorCol = -1;
    int qtyCol = -1;
    int buyPriceCol = -1;
    int currentPriceCol = -1;

    for (var i = 0; i < rows.length; i++) {
      final headers = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final header = _normalizeImportHeader(rows[i][j]);
        if (header.isNotEmpty) {
          headers[header] = j;
        }
      }

      final hasSymbol =
          headers.keys.any((h) => h == 'symbol' || h.contains('symbol'));
      final hasQtyAvailable = headers.keys.any((h) => h == 'quantity available');
      final hasAvgPrice = headers.keys.any(
        (h) => h == 'average price' || h.contains('average price'),
      );

      if (hasSymbol && hasQtyAvailable && hasAvgPrice) {
        headerRowIndex = i;
        symbolCol = headers['symbol'] ??
            headers.entries
                .firstWhere((e) => e.key.contains('symbol'))
                .value;
        qtyCol = headers['quantity available']!;
        buyPriceCol = headers['average price'] ??
            headers.entries
                .firstWhere(
                  (e) =>
                      e.key == 'average price' ||
                      e.key.contains('average price'),
                )
                .value;
        isinCol = -1;
        for (final entry in headers.entries) {
          if (entry.key == 'isin' || entry.key.contains('isin')) {
            isinCol = entry.value;
            break;
          }
        }
        sectorCol = -1;
        for (final entry in headers.entries) {
          if (entry.key == 'sector' || entry.key.contains('sector')) {
            sectorCol = entry.value;
            break;
          }
        }
        currentPriceCol = -1;
        for (final entry in headers.entries) {
          if (entry.key.contains('previous closing price')) {
            currentPriceCol = entry.value;
            break;
          }
        }
        break;
      }
    }

    if (headerRowIndex == null || symbolCol < 0 || qtyCol < 0 || buyPriceCol < 0) {
      return [];
    }

    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      try {
        final symbol = symbolCol < row.length ? row[symbolCol].trim() : '';
        if (symbol.isEmpty ||
            symbol.toLowerCase().contains('total') ||
            symbol.toLowerCase() == 'symbol') {
          continue;
        }

        final quantity = qtyCol < row.length ? _parseNumber(row[qtyCol]) : 0.0;
        final buyPrice =
            buyPriceCol < row.length ? _parseNumber(row[buyPriceCol]) : 0.0;
        final currentPrice =
            currentPriceCol >= 0 && currentPriceCol < row.length
                ? _parseNumber(row[currentPriceCol])
                : 0.0;
        final isinRaw =
            isinCol >= 0 && isinCol < row.length ? row[isinCol].trim() : '';
        final isin = isinRaw.isEmpty ? null : isinRaw.toUpperCase();
        final sector =
            sectorCol >= 0 && sectorCol < row.length ? row[sectorCol].trim() : '';

        if (quantity == 0) continue;

        stocks.add(
          Stock(
            id: 0,
            symbol: symbol.toUpperCase(),
            name: '',
            sector: sector,
            quantity: quantity,
            buyPrice: buyPrice,
            currentPrice: currentPrice,
            createdAt: now,
            updatedAt: now,
            isin: isin,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    return stocks;
  }

  Future<void> _saveImportedStocks() async {
    if (_importedStocks.isEmpty || _importSource == null || _isSavingImported) {
      return;
    }

    setState(() => _isSavingImported = true);

    try {
      final provider = context.read<FinanceProvider>();
      final watchList = context.read<AuthProvider>().useAsStockWatchList;
      final toSave = watchList
          ? _importedStocks
              .map(
                (s) => Stock(
                  id: s.id,
                  symbol: s.symbol,
                  name: s.name,
                  sector: s.sector,
                  industry: s.industry,
                  marketCap: s.marketCap,
                  source: s.source,
                  quantity: 1,
                  buyPrice: s.buyPrice,
                  currentPrice: s.currentPrice,
                  sixthHighestPrice: s.sixthHighestPrice,
                  sixthLowestPrice: s.sixthLowestPrice,
                  lastFetchedDate: s.lastFetchedDate,
                  lastPriceFetchedDate: s.lastPriceFetchedDate,
                  createdAt: s.createdAt,
                  updatedAt: s.updatedAt,
                  isin: s.isin,
                  lastBuyPrice: s.lastBuyPrice,
                  lastBuyDate: s.lastBuyDate,
                  lastSalePrice: s.lastSalePrice,
                  lastSaleDate: s.lastSaleDate,
                ),
              )
              .toList()
          : _importedStocks;
      await provider.addStocksBulk(toSave, source: _importSource!);

      if (provider.error != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${provider.error}'),
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
        return;
      }

      setState(() {
        _importedStocks = [];
        _importSource = null;
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stocks imported successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingImported = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBrandTitle(
          widget.stock == null ? 'Add Stock' : 'Edit Stock',
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (widget.stock == null) ...[
                Card(
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
                          'Upload ICICIDirect portfolio Excel (Stock Symbol, ISIN Code, Qty, Average Cost Price). ISIN auto-maps broker symbols to NSE/Yahoo on import.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _isImporting ? null : _pickAndImportICICIDirectFile,
                          icon: _isImporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(_isImporting ? 'Importing...' : 'Select ICICIDirect File'),
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
                            Icon(Icons.account_balance, color: Colors.teal),
                            SizedBox(width: 8),
                            Text(
                              'Import HDFC Securities CSV',
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
                          'Upload HDFC Securities portfolio CSV (Symbol, Qty, Avg Price). Account: HDFCSec. Transaction date is set to today.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _isImporting ? null : _pickAndImportHDFCSecFile,
                          icon: _isImporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(_isImporting ? 'Importing...' : 'Select HDFCSec File'),
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
                            Icon(Icons.account_balance, color: Colors.indigo),
                            SizedBox(width: 8),
                            Text(
                              'Import Zerodha Holdings Excel',
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
                          'Upload Zerodha holdings Excel (Symbol, ISIN, Sector, Quantity Available, Average Price). Account: Zerodha. Transaction date is set to today.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _isImporting ? null : _pickAndImportZerodhaFile,
                          icon: _isImporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(_isImporting ? 'Importing...' : 'Select Zerodha File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
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
                          'Upload a CSV or Excel file with columns: symbol, quantity, buyPrice',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _isImporting ? null : _pickAndImportFile,
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
                        if (_importedStocks.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          Text(
                            'Imported ${_importedStocks.length} stocks',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _importedStocks.length,
                              itemBuilder: (context, index) {
                                final stock = _importedStocks[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.chevron_right, size: 20),
                                  title: Text(
                                    stock.symbol,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (stock.isin != null) stock.isin!,
                                      '${stock.quantity} @ ${formatInr(stock.buyPrice)}',
                                    ].join(' · '),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isSavingImported
                                      ? null
                                      : _saveImportedStocks,
                                  icon: _isSavingImported
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.save),
                                  label: Text(
                                    _isSavingImported
                                        ? 'Saving...'
                                        : 'Save All Stocks',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        Colors.green.shade300,
                                    disabledForegroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isSavingImported
                                      ? null
                                      : () {
                                          setState(() {
                                            _importedStocks = [];
                                            _importSource = null;
                                          });
                                        },
                                  child: const Text('Clear'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  color: Colors.indigo.shade50,
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    leading: Icon(Icons.edit_note, color: Colors.indigo.shade700),
                    title: Text(
                      'Manual Add - Single Stock',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                    subtitle: const Text(
                      'Enter symbol, quantity, and buy price for one stock',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildManualStockFormFields(),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                ..._buildManualStockFormFields(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildManualStockFormFields() {
    return [
      if (widget.stock != null)
        TextFormField(
          controller: _symbolController,
          enabled: false,
          decoration: const InputDecoration(
            labelText: 'Symbol *',
            border: OutlineInputBorder(),
            helperText: 'Symbol cannot be changed for existing holdings',
          ),
        )
      else
        RawAutocomplete<({String symbol, String name, double currentPrice})>(
          textEditingController: _symbolController,
          focusNode: _symbolFocusNode,
          displayStringForOption: (o) => o.symbol,
          optionsBuilder: (TextEditingValue value) async {
            final q = value.text.trim();
            if (q.isEmpty) {
              return const Iterable<
                  ({String symbol, String name, double currentPrice})>.empty();
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
            if (!mounted || _symbolController.text.trim() != q) {
              return const Iterable<
                  ({String symbol, String name, double currentPrice})>.empty();
            }
            return _searchCatalog(q);
          },
          onSelected: _selectCatalogHit,
          fieldViewBuilder:
              (context, controller, focusNode, onFieldSubmitted) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Symbol *',
                hintText: 'Start typing to search catalog',
                border: const OutlineInputBorder(),
                helperText: _confirmedCatalogName != null &&
                        _confirmedCatalogName!.isNotEmpty
                    ? _confirmedCatalogName
                    : 'Choose a symbol from the NSE catalog',
              ),
              onChanged: (_) {
                _ltpLookupSymbol = null;
                if (_confirmedCatalogSymbol != null &&
                    _confirmedCatalogSymbol !=
                        controller.text.trim().toUpperCase()) {
                  setState(() {
                    _confirmedCatalogSymbol = null;
                    _confirmedCatalogName = null;
                  });
                }
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a symbol';
                }
                final sym = value.trim().toUpperCase();
                if (_confirmedCatalogSymbol == null ||
                    _confirmedCatalogSymbol != sym) {
                  return 'Select a symbol from the catalog suggestions';
                }
                return null;
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240, maxWidth: 480),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      final price = option.currentPrice > 0
                          ? ' · ${formatInr(option.currentPrice)}'
                          : '';
                      return ListTile(
                        dense: true,
                        title: Text(
                          option.symbol,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${option.name}$price',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
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
              labelText: 'Quantity *',
              hintText: watchList ? 'Fixed to 1 (watch list)' : 'e.g., 10',
              border: const OutlineInputBorder(),
              helperText: watchList
                  ? 'Watch list mode always saves quantity as 1'
                  : null,
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter quantity';
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
        controller: _buyPriceController,
        decoration: InputDecoration(
          labelText: 'Buy Price (₹) *',
          hintText: 'e.g., 2500.50',
          border: const OutlineInputBorder(),
          helperText: _buyPriceFromLtp
              ? 'Prefilled from Global Stocks LTP'
              : null,
        ),
        keyboardType: TextInputType.number,
        onChanged: (_) {
          if (_buyPriceFromLtp) {
            setState(() => _buyPriceFromLtp = false);
          }
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter buy price';
          }
          if (double.tryParse(value) == null) {
            return 'Please enter a valid number';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Transaction Date'),
        subtitle: Text('${_transactionDate.toLocal()}'.split(' ')[0]),
        trailing: const Icon(Icons.calendar_today),
        onTap: () async {
          final DateTime? picked = await showDatePicker(
            context: context,
            initialDate: _transactionDate,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
          );
          if (picked != null && picked != _transactionDate) {
            setState(() {
              _transactionDate = picked;
            });
          }
        },
      ),
      if (widget.stock != null) ...[
        const SizedBox(height: 16),
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stock Information',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (widget.stock!.industry.isNotEmpty)
                  _buildInfoRow('Industry', widget.stock!.industry),
                if (widget.stock!.sixthHighestPrice > 0)
                  _buildInfoRow(
                    'High',
                    formatInr(widget.stock!.sixthHighestPrice),
                  ),
                if (widget.stock!.sixthLowestPrice > 0)
                  _buildInfoRow(
                    'Low',
                    formatInr(widget.stock!.sixthLowestPrice),
                  ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),
      Consumer<FinanceProvider>(
        builder: (context, provider, child) {
          return ElevatedButton(
            onPressed: provider.isLoading
                ? null
                : () async {
                    await _confirmCatalogExactMatch();
                    await _tryPrefillBuyPriceFromLtp();
                    if (!_formKey.currentState!.validate()) return;

                    final watchList =
                        context.read<AuthProvider>().useAsStockWatchList;
                    final qty = watchList
                        ? 1.0
                        : double.parse(_quantityController.text);
                    final stock = Stock(
                      id: widget.stock?.id ?? 0,
                      symbol: _symbolController.text.toUpperCase(),
                      name: _confirmedCatalogName ?? widget.stock?.name ?? '',
                      quantity: qty,
                      buyPrice: double.parse(_buyPriceController.text),
                      // Current price is filled from Yahoo / Global_Stocks on the backend.
                      currentPrice: 0.0,
                      createdAt: widget.stock?.createdAt ?? DateTime.now(),
                      updatedAt: DateTime.now(),
                    );

                    if (widget.stock == null) {
                      await provider.addStock(
                        stock,
                        transactionDate: _transactionDate,
                      );
                    } else {
                      await provider.updateStock(widget.stock!.id, stock);
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
                  },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: provider.isLoading
                ? const CircularProgressIndicator()
                : Text(widget.stock == null ? 'Add Stock' : 'Update Stock'),
          );
        },
      ),
    ];
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
