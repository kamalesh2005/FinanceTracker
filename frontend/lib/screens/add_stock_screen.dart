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
  late TextEditingController _nameController;
  late TextEditingController _quantityController;
  late TextEditingController _buyPriceController;
  late TextEditingController _currentPriceController;
  late DateTime _transactionDate;
  List<Stock> _importedStocks = [];
  bool _isImporting = false;
  String? _importSource;

  @override
  void initState() {
    super.initState();
    _symbolController = TextEditingController(text: widget.stock?.symbol ?? '');
    _nameController = TextEditingController(text: widget.stock?.name ?? '');
    _quantityController = TextEditingController(
      text: widget.stock?.quantity.toString() ?? '',
    );
    _buyPriceController =
        TextEditingController(text: widget.stock?.buyPrice.toString() ?? '');
    _currentPriceController =
        TextEditingController(text: widget.stock?.currentPrice.toString() ?? '');
    _transactionDate = DateTime.now();
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
    _symbolController.dispose();
    _nameController.dispose();
    _quantityController.dispose();
    _buyPriceController.dispose();
    _currentPriceController.dispose();
    super.dispose();
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

    // Expected columns: symbol, name, quantity, buyPrice, currentPrice
    for (var row in dataRows) {
      if (row.length < 3) continue; // At least symbol, quantity, buyPrice required

      try {
        final stock = Stock(
          id: 0,
          symbol: row[0].toString().toUpperCase(),
          name: row.length > 1 ? row[1].toString() : '',
          quantity: double.parse(row[2].toString()),
          buyPrice: double.parse(row[3].toString()),
          currentPrice: row.length > 4 && row[4].toString().isNotEmpty
              ? double.parse(row[4].toString())
              : 0.0,
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
        if (row.length < 3) continue; // At least symbol, quantity, buyPrice required

        try {
          final symbol = row[0]?.value?.toString() ?? '';
          final name = row.length > 1 ? row[1]?.value?.toString() ?? '' : '';
          final quantity = double.parse(row[2]?.value?.toString() ?? '0');
          final buyPrice = double.parse(row[3]?.value?.toString() ?? '0');
          final currentPrice = row.length > 4 && row[4]?.value != null
              ? double.parse(row[4]!.value.toString())
              : 0.0;

          if (symbol.isEmpty || quantity == 0 || buyPrice == 0) continue;

          final stock = Stock(
            id: 0,
            symbol: symbol.toUpperCase(),
            name: name,
            quantity: quantity,
            buyPrice: buyPrice,
            currentPrice: currentPrice,
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
    if (_importedStocks.isEmpty || _importSource == null) return;

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
                          'Upload a CSV or Excel file with columns: symbol, name, quantity, buyPrice, currentPrice',
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
                                child: ElevatedButton(
                                  onPressed: _saveImportedStocks,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Save All Stocks'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
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
                      'Enter symbol, quantity, and prices for one stock',
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
      TextFormField(
        controller: _symbolController,
        decoration: const InputDecoration(
          labelText: 'Symbol *',
          hintText: 'e.g., RELIANCE, TCS',
          border: OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter a symbol';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Company Name',
          hintText: 'e.g., Reliance Industries',
          border: OutlineInputBorder(),
        ),
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
        decoration: const InputDecoration(
          labelText: 'Buy Price (₹) *',
          hintText: 'e.g., 2500.50',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
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
      TextFormField(
        controller: _currentPriceController,
        decoration: const InputDecoration(
          labelText: 'Current Price (₹)',
          hintText: 'e.g., 2600.75',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
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
                if (widget.stock!.sector.isNotEmpty)
                  _buildInfoRow('Sector', widget.stock!.sector),
                if (widget.stock!.sixthHighestPrice > 0)
                  _buildInfoRow(
                    '6th Highest Price',
                    formatInr(widget.stock!.sixthHighestPrice),
                  ),
                if (widget.stock!.sixthLowestPrice > 0)
                  _buildInfoRow(
                    '6th Lowest Price',
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
                    if (_formKey.currentState!.validate()) {
                      final watchList = context
                          .read<AuthProvider>()
                          .useAsStockWatchList;
                      final qty = watchList
                          ? 1.0
                          : double.parse(_quantityController.text);
                      final stock = Stock(
                        id: widget.stock?.id ?? 0,
                        symbol: _symbolController.text.toUpperCase(),
                        name: _nameController.text,
                        quantity: qty,
                        buyPrice: double.parse(_buyPriceController.text),
                        currentPrice: _currentPriceController.text.isEmpty
                            ? 0.0
                            : double.parse(_currentPriceController.text),
                        createdAt:
                            widget.stock?.createdAt ?? DateTime.now(),
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
                    }
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
