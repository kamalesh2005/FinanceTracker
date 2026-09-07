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

enum _StockImportKind {
  iciciSummary,
  iciciTransactions,
  hdfc,
  hdfcTransactions,
  zerodha,
  zerodhaTransactions,
  bulk,
  bulkTransactions,
  cas,
}

typedef _TradeTxnRow = ({
  String symbol,
  String name,
  String isin,
  String action,
  double quantity,
  double price,
  DateTime transactionDate,
  double brokerage,
  double transactionCharges,
  double stampDuty,
  String segment,
  String stt,
  String exchange,
});

typedef _ICICITxnRow = _TradeTxnRow;

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
  _StockImportKind? _importingKind;
  bool _isDeletingAll = false;

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
      text: (widget.stock == null || widget.stock!.quantity <= 0)
          ? ''
          : widget.stock!.quantity.toString(),
    );
    _buyPriceController = TextEditingController(
      text: (widget.stock == null || widget.stock!.buyPrice <= 0)
          ? ''
          : widget.stock!.buyPrice.toString(),
    );
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

  bool get _isImporting => _importingKind != null || _isDeletingAll;

  bool _isBusy(_StockImportKind kind) => _importingKind == kind;

  void _setImporting(_StockImportKind? kind) {
    if (!mounted) return;
    setState(() => _importingKind = kind);
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
      _symbolController.selection =
          TextSelection.collapsed(offset: symbol.length);
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

  void _showImportWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
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

  List<Stock> _watchListStocks(List<Stock> stocks) {
    return stocks
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
        .toList();
  }

  Future<void> _persistImportedStocks(List<Stock> stocks, String source) async {
    final provider = context.read<FinanceProvider>();
    final watchList = context.read<AuthProvider>().useAsStockWatchList;
    final toSave = watchList ? _watchListStocks(stocks) : stocks;
    await provider.addStocksBulk(toSave, source: source);
    if (!mounted) return;
    _setImporting(null);
    if (provider.error != null) {
      _showImportError('Error: ${provider.error}');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stocks imported successfully'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  Future<String?> _promptCasPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('NSDL e-CAS password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the PDF password. For NSDL e-CAS this is the PAN of the first/sole holder (capital letters).',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'PAN password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (password == null || password.isEmpty) return null;
    return password;
  }

  Future<void> _pickAndImportCasFile() async {
    if (!context.read<AuthProvider>().isAdmin) {
      _showImportError('NSDL e-CAS import is available to admins only');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final password = await _promptCasPassword();
      if (password == null) return;
      if (!mounted) return;

      _setImporting(_StockImportKind.cas);
      final picked = result.files.single;
      final bytes = await _readPickedFileBytes(picked);
      if (bytes == null) {
        throw Exception('Could not read file contents');
      }
      if (!mounted) return;
      final filename = picked.name.isNotEmpty ? picked.name : 'cas.pdf';
      final provider = context.read<FinanceProvider>();
      final summary = await provider.importCas(
        bytes: bytes,
        filename: filename,
        password: password,
      );
      if (!mounted) return;
      _setImporting(null);
      if (summary == null) {
        _showImportError('Error: ${provider.error ?? 'CAS import failed'}');
        return;
      }
      final srcNames = summary.sources
          .map((s) => (s['source'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CAS imported: ${summary.stocks} stocks, ${summary.mutualFunds} MFs'
            '${srcNames.isEmpty ? '' : ' ($srcNames)'}',
          ),
          backgroundColor: Colors.green,
        ),
      );
      if (summary.warnings.isNotEmpty) {
        _showImportWarning(
          '${summary.warnings.length} scheme(s) need catalog mapping.',
        );
      }
      Navigator.pop(context);
    } catch (e) {
      _setImporting(null);
      _showImportError('Error importing CAS: $e');
    }
  }

  Future<void> _pickAndImportFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      _setImporting(_StockImportKind.bulk);

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

      if (stocks.isEmpty) {
        _setImporting(null);
        _showImportWarning(
            'No stocks found. Expected columns: symbol, quantity, buyPrice');
        return;
      }
      await _persistImportedStocks(stocks, 'Manual Bulk Upload');
    } catch (e) {
      _setImporting(null);
      _showImportError('Error importing file: $e');
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

      if (result == null || result.files.isEmpty) return;

      _setImporting(_StockImportKind.iciciSummary);

      final bytes = await _readPickedFileBytes(result.files.single);
      if (bytes == null) {
        throw Exception('Could not read file contents');
      }

      final stocks = _parseICICIDirectExcel(bytes);
      if (stocks.isEmpty) {
        _setImporting(null);
        _showImportWarning(
          'No stocks found. Ensure this is an ICICIDirect portfolio Excel export.',
        );
        return;
      }
      await _persistImportedStocks(stocks, 'ICICIDirect');
    } catch (e) {
      _setImporting(null);
      _showImportError('Error importing ICICIDirect file: $e');
    }
  }

  Future<void> _confirmAndImportICICIDirectTransactions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import ICICIDirect transactions'),
        content: const Text(
          'All previous transactions will be erased and newly created',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _pickAndImportICICIDirectTransactionsFile();
  }

  Future<void> _confirmAndDeleteAllHoldings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Stocks'),
        content: const Text(
          'This deletes every holding and transaction for your account. The stock catalog is not removed. This cannot be undone.',
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
    final ok = await provider.deleteAllHoldings();
    if (!mounted) return;
    setState(() => _isDeletingAll = false);
    if (!ok) {
      _showImportError('Error: ${provider.error}');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All stocks deleted'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _pickAndImportICICIDirectTransactionsFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      _setImporting(_StockImportKind.iciciTransactions);

      final bytes = await _readPickedFileBytes(result.files.single);
      if (bytes == null) {
        throw Exception('Could not read file contents');
      }

      final rows = _parseICICIDirectTransactions(bytes);
      if (rows.isEmpty) {
        _setImporting(null);
        _showImportWarning(
          'No transactions found. Ensure this is an ICICIDirect transactions Excel export (Action, Transaction Date, Transaction Price).',
        );
        return;
      }

      if (!mounted) return;
      final provider = context.read<FinanceProvider>();
      await provider.rebuildLedgerFromTransactions(
        source: 'ICICIDirect',
        items: rows
            .map(
              (r) => {
                'symbol': r.symbol,
                'name': r.name,
                'isin': r.isin,
                'action': r.action,
                'quantity': r.quantity,
                'price': r.price,
                'transaction_date': r.transactionDate.toUtc().toIso8601String(),
                'brokerage': r.brokerage,
                'transaction_charges': r.transactionCharges,
                'stamp_duty': r.stampDuty,
                'segment': r.segment,
                'stt': r.stt,
                'exchange': r.exchange,
              },
            )
            .toList(),
      );
      if (!mounted) return;
      _setImporting(null);
      if (provider.error != null) {
        _showImportError('Error: ${provider.error}');
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${rows.length} ICICIDirect transactions'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      _setImporting(null);
      _showImportError('Error importing ICICIDirect transactions file: $e');
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

      if (result == null || result.files.isEmpty) return;

      _setImporting(_StockImportKind.hdfc);

      final bytes = await _readPickedFileBytes(result.files.single);
      if (bytes == null) {
        throw Exception('Could not read file contents');
      }

      final stocks = _parseHDFCSecCSV(bytes);
      if (stocks.isEmpty) {
        _setImporting(null);
        _showImportWarning(
          'No stocks found. Ensure this is an HDFC Securities portfolio CSV export.',
        );
        return;
      }
      await _persistImportedStocks(stocks, 'HDFCSec');
    } catch (e) {
      _setImporting(null);
      _showImportError('Error importing HDFCSec file: $e');
    }
  }

  Future<void> _confirmAndImportPartialTransactions({
    required String title,
    required String body,
    required Future<void> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onConfirm();
    }
  }

  List<Map<String, dynamic>> _tradeTxnApiItems(List<_TradeTxnRow> rows) {
    return rows
        .map(
          (r) => {
            'symbol': r.symbol,
            'name': r.name,
            'isin': r.isin,
            'action': r.action,
            'quantity': r.quantity,
            'price': r.price,
            'transaction_date': r.transactionDate.toUtc().toIso8601String(),
            'brokerage': r.brokerage,
            'transaction_charges': r.transactionCharges,
            'stamp_duty': r.stampDuty,
            'segment': r.segment,
            'stt': r.stt,
            'exchange': r.exchange,
          },
        )
        .toList();
  }

  Future<void> _importPartialTransactions({
    required _StockImportKind kind,
    required String source,
    required String label,
    required List<_TradeTxnRow> Function(Uint8List bytes) parse,
    required String emptyMessage,
    List<String> extensions = const ['xlsx', 'xls'],
  }) async {
    try {
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        allowMultiple: false,
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) return;

      _setImporting(kind);

      final bytes = await _readPickedFileBytes(picked.files.single);
      if (bytes == null) {
        throw Exception('Could not read file contents');
      }

      final rows = parse(bytes);
      if (rows.isEmpty) {
        _setImporting(null);
        _showImportWarning(emptyMessage);
        return;
      }

      if (!mounted) return;
      final provider = context.read<FinanceProvider>();
      final resultMerge = await provider.mergeLedgerFromTransactions(
        source: source,
        items: _tradeTxnApiItems(rows),
      );
      if (!mounted) return;
      _setImporting(null);
      if (provider.error != null || resultMerge == null) {
        _showImportError('Error: ${provider.error ?? 'import failed'}');
        return;
      }
      final unmapped = resultMerge.unmapped;
      final msg = unmapped.isEmpty
          ? 'Imported ${resultMerge.count} $label transactions'
          : 'Imported ${resultMerge.count} $label transactions; '
              '${unmapped.length} unmapped: ${unmapped.take(5).join(', ')}'
              '${unmapped.length > 5 ? '…' : ''}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: unmapped.isEmpty ? Colors.green : Colors.orange,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      _setImporting(null);
      _showImportError('Error importing $label transactions file: $e');
    }
  }

  Future<void> _confirmAndImportHDFCTransactions() async {
    await _confirmAndImportPartialTransactions(
      title: 'Import HDFC transactions',
      body:
          'For each stock in the file, transactions in the file date range (and any undated rows) will be replaced. Other stocks and out-of-range history are kept.',
      onConfirm: () => _importPartialTransactions(
        kind: _StockImportKind.hdfcTransactions,
        source: 'HDFCSec',
        label: 'HDFCSec',
        parse: _parseHDFCTransactions,
        emptyMessage:
            'No transactions found. Ensure this is an HDFC Equity Trade Details export (Scrip Name, Trade Date, Buy/Sell).',
      ),
    );
  }

  Future<void> _confirmAndImportZerodhaTransactions() async {
    await _confirmAndImportPartialTransactions(
      title: 'Import Zerodha transactions',
      body:
          'For each stock in the file, transactions in the file date range (and any undated rows) will be replaced. Other stocks and out-of-range history are kept.',
      onConfirm: () => _importPartialTransactions(
        kind: _StockImportKind.zerodhaTransactions,
        source: 'Zerodha',
        label: 'Zerodha',
        parse: _parseZerodhaTransactions,
        emptyMessage:
            'No transactions found. Ensure this is a Zerodha tradebook export (Symbol, Trade Date, Trade Type).',
      ),
    );
  }

  Future<void> _confirmAndImportBulkTransactions() async {
    await _confirmAndImportPartialTransactions(
      title: 'Import bulk transactions',
      body:
          'For each stock in the file, transactions in the file date range (and any undated rows) will be replaced. Other stocks and out-of-range history are kept.',
      onConfirm: () => _importPartialTransactions(
        kind: _StockImportKind.bulkTransactions,
        source: 'Manual Bulk Upload',
        label: 'Bulk',
        parse: _parseBulkTransactions,
        emptyMessage:
            'No transactions found. Use columns: Symbol, Trade Date, Trade Type, Quantity, Price.',
        extensions: const ['csv', 'xlsx', 'xls'],
      ),
    );
  }

  Future<void> _downloadSampleCsv({
    required String fileName,
    required String content,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save sample file',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: bytes,
    );
    if (!mounted) return;
    if (path == null && !kIsWeb) {
      _showImportWarning('Sample download cancelled');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved $fileName'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _downloadBulkSummarySample() async {
    await _downloadSampleCsv(
      fileName: 'bulk_holdings_sample.csv',
      content: 'symbol,quantity,buyPrice\n'
          'RELIANCE,10,2500.00\n'
          'TCS,5,3500.50\n',
    );
  }

  Future<void> _downloadBulkTransactionsSample() async {
    await _downloadSampleCsv(
      fileName: 'bulk_transactions_sample.csv',
      content: 'Symbol,Trade Date,Trade Type,Quantity,Price\n'
          'RELIANCE,01-Jan-2024,Buy,10,2500.00\n'
          'RELIANCE,15-Jun-2024,Sell,2,2800.00\n'
          'TCS,2024-03-01,buy,5,3500.50\n',
    );
  }

  Future<void> _pickAndImportZerodhaFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      _setImporting(_StockImportKind.zerodha);

      final bytes = await _readPickedFileBytes(result.files.single);
      if (bytes == null) {
        throw Exception('Could not read file contents');
      }

      final stocks = _parseZerodhaExcel(bytes);
      if (stocks.isEmpty) {
        _setImporting(null);
        _showImportWarning(
          'No stocks found. Ensure this is a Zerodha holdings Excel export.',
        );
        return;
      }
      await _persistImportedStocks(stocks, 'Zerodha');
    } catch (e) {
      _setImporting(null);
      _showImportError('Error importing Zerodha file: $e');
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

  double _parseOptionalNumber(String value) {
    final t = value.trim();
    if (t.isEmpty || t.toUpperCase() == 'NA') return 0.0;
    return _parseNumber(t);
  }

  String _cellAt(List<String> row, int col) {
    if (col < 0 || col >= row.length) return '';
    return row[col].trim();
  }

  DateTime? _parseICICITransactionDate(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final iso = DateTime.tryParse(t);
    if (iso != null) return iso;
    final match = RegExp(r'^(\d{1,2})-([A-Za-z]{3})-(\d{2,4})$').firstMatch(t);
    if (match != null) {
      const months = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };
      final day = int.tryParse(match.group(1)!);
      final month = months[match.group(2)!.toLowerCase()];
      var year = int.tryParse(match.group(3)!);
      if (day == null || month == null || year == null) return null;
      if (year < 100) year += 2000;
      return DateTime(year, month, day);
    }
    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(t);
    if (slash != null) {
      final day = int.tryParse(slash.group(1)!);
      final month = int.tryParse(slash.group(2)!);
      var year = int.tryParse(slash.group(3)!);
      if (day == null || month == null || year == null) return null;
      if (year < 100) year += 2000;
      return DateTime(year, month, day);
    }
    return null;
  }

  int _headerCol(Map<String, int> headers, bool Function(String) test) {
    for (final entry in headers.entries) {
      if (test(entry.key)) return entry.value;
    }
    return -1;
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
        .map(
            (line) => line.split(delimiter).map((cell) => cell.trim()).toList())
        .toList();
  }

  List<List<String>> _parseHtmlTableRows(String html) {
    final rows = <List<String>>[];
    final rowRegex =
        RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
    final cellRegex = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>',
        caseSensitive: false, dotAll: true);

    for (final rowMatch in rowRegex.allMatches(html)) {
      final cells = <String>[];
      for (final cellMatch in cellRegex.allMatches(rowMatch.group(1)!)) {
        final raw = cellMatch
            .group(1)!
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

      final hasStockSymbol =
          headers.keys.any((h) => h.contains('stock symbol'));
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

    if (headerRowIndex == null ||
        symbolCol < 0 ||
        qtyCol < 0 ||
        buyPriceCol < 0) {
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

        final name =
            nameCol >= 0 && nameCol < row.length ? row[nameCol].trim() : '';
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

  List<List<String>> _rowsFromICICIDirectBytes(Uint8List bytes) {
    if (_isOleOrZipExcel(bytes)) {
      return _rowsFromExcelBytes(bytes);
    }
    final text = _decodeSpreadsheetText(bytes);
    final lower = text.toLowerCase();
    if (lower.contains('<table') || lower.contains('<html')) {
      return _parseHtmlTableRows(text);
    }
    // ICICIDirect often exports tab-separated text with a .xls extension
    return _parseDelimitedRows(text);
  }

  List<Stock> _parseICICIDirectExcel(Uint8List bytes) {
    final rows = _rowsFromICICIDirectBytes(bytes);
    final stocks = _stocksFromICICIDirectRows(rows);
    if (stocks.isNotEmpty) return stocks;

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

  List<_ICICITxnRow> _parseICICIDirectTransactions(Uint8List bytes) {
    var rows = _txnsFromICICIDirectRows(_rowsFromICICIDirectBytes(bytes));
    if (rows.isNotEmpty) return rows;
    if (_isOleOrZipExcel(bytes)) {
      final text = _decodeSpreadsheetText(bytes);
      rows = _txnsFromICICIDirectRows(_parseDelimitedRows(text));
      if (rows.isNotEmpty) return rows;
    }
    try {
      return _txnsFromICICIDirectRows(_rowsFromExcelBytes(bytes));
    } catch (_) {
      return rows;
    }
  }

  List<_ICICITxnRow> _txnsFromICICIDirectRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    int? headerRowIndex;
    var symbolCol = -1;
    var nameCol = -1;
    var isinCol = -1;
    var actionCol = -1;
    var qtyCol = -1;
    var priceCol = -1;
    var brokerageCol = -1;
    var chargesCol = -1;
    var stampCol = -1;
    var segmentCol = -1;
    var sttCol = -1;
    var dateCol = -1;
    var exchangeCol = -1;

    for (var i = 0; i < rows.length; i++) {
      final headers = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final header = _normalizeImportHeader(rows[i][j]);
        if (header.isNotEmpty) headers[header] = j;
      }
      final hasAction = headers.keys.any((h) => h == 'action');
      final hasTxnDate =
          headers.keys.any((h) => h.contains('transaction date'));
      final hasTxnPrice =
          headers.keys.any((h) => h.contains('transaction price'));
      if (!hasAction || !hasTxnDate || !hasTxnPrice) continue;

      headerRowIndex = i;
      symbolCol = _headerCol(headers, (h) => h.contains('stock symbol'));
      nameCol = _headerCol(headers, (h) => h.contains('company name'));
      isinCol = _headerCol(headers, (h) => h.contains('isin'));
      actionCol = _headerCol(headers, (h) => h == 'action');
      qtyCol = _headerCol(headers, (h) => h == 'quantity' || h == 'qty');
      priceCol = _headerCol(headers, (h) => h.contains('transaction price'));
      brokerageCol = _headerCol(headers, (h) => h.contains('brokerage'));
      chargesCol =
          _headerCol(headers, (h) => h.contains('transaction charges'));
      stampCol = _headerCol(headers, (h) => h.contains('stamp'));
      segmentCol = _headerCol(headers, (h) => h == 'segment');
      sttCol = _headerCol(headers, (h) => h.contains('stt'));
      dateCol = _headerCol(headers, (h) => h.contains('transaction date'));
      exchangeCol = _headerCol(headers, (h) => h == 'exchange');
      break;
    }

    if (headerRowIndex == null ||
        symbolCol < 0 ||
        actionCol < 0 ||
        qtyCol < 0 ||
        priceCol < 0 ||
        dateCol < 0) {
      return [];
    }

    final txns = <_ICICITxnRow>[];
    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      final symbol = _cellAt(row, symbolCol).toUpperCase();
      if (symbol.isEmpty ||
          symbol.contains('TOTAL') ||
          symbol == 'STOCK SYMBOL') {
        continue;
      }
      final action = _cellAt(row, actionCol);
      if (action.isEmpty) continue;
      final quantity = _parseOptionalNumber(_cellAt(row, qtyCol));
      if (quantity <= 0) continue;
      final date = _parseICICITransactionDate(_cellAt(row, dateCol));
      if (date == null) continue;
      txns.add((
        symbol: symbol,
        name: _cellAt(row, nameCol),
        isin: _parseIsinFromCell(_cellAt(row, isinCol)) ?? '',
        action: action,
        quantity: quantity,
        price: _parseOptionalNumber(_cellAt(row, priceCol)),
        transactionDate: date,
        brokerage: _parseOptionalNumber(_cellAt(row, brokerageCol)),
        transactionCharges: _parseOptionalNumber(_cellAt(row, chargesCol)),
        stampDuty: _parseOptionalNumber(_cellAt(row, stampCol)),
        segment: _cellAt(row, segmentCol),
        stt: _cellAt(row, sttCol),
        exchange: _cellAt(row, exchangeCol),
      ));
    }
    return txns;
  }

  List<_TradeTxnRow> _parseExcelOrDelimitedTxns(
    Uint8List bytes,
    List<_TradeTxnRow> Function(List<List<String>> rows) fromRows,
  ) {
    try {
      final rows = fromRows(_rowsFromExcelBytes(bytes));
      if (rows.isNotEmpty) return rows;
    } catch (_) {}
    if (_isOleOrZipExcel(bytes)) {
      final text = _decodeSpreadsheetText(bytes);
      final rows = fromRows(_parseDelimitedRows(text));
      if (rows.isNotEmpty) return rows;
    }
    try {
      final text = utf8.decode(bytes);
      return fromRows(_parseDelimitedRows(text));
    } catch (_) {
      return [];
    }
  }

  List<_TradeTxnRow> _parseHDFCTransactions(Uint8List bytes) {
    return _parseExcelOrDelimitedTxns(bytes, _txnsFromHDFCTradeRows);
  }

  List<_TradeTxnRow> _txnsFromHDFCTradeRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    int? headerRowIndex;
    var nameCol = -1;
    var actionCol = -1;
    var qtyCol = -1;
    var priceCol = -1;
    var dateCol = -1;
    var brokerageCol = -1;
    var chargesCol = -1;
    var stampCol = -1;
    var sttCol = -1;
    var exchangeCol = -1;

    for (var i = 0; i < rows.length; i++) {
      final headers = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final header = _normalizeImportHeader(rows[i][j]);
        if (header.isNotEmpty) headers[header] = j;
      }
      final hasScrip = headers.keys.any((h) => h.contains('scrip name'));
      final hasTradeDate = headers.keys.any((h) => h.contains('trade date'));
      final hasBuySell = headers.keys.any(
        (h) => h == 'buy/sell' || h == 'buy sell' || h.contains('buy/sell'),
      );
      if (!hasScrip || !hasTradeDate || !hasBuySell) continue;

      headerRowIndex = i;
      nameCol = _headerCol(headers, (h) => h.contains('scrip name'));
      actionCol = _headerCol(
        headers,
        (h) => h == 'buy/sell' || h == 'buy sell' || h.contains('buy/sell'),
      );
      qtyCol = _headerCol(headers, (h) => h == 'qty' || h == 'quantity');
      priceCol = _headerCol(
        headers,
        (h) => h.contains('market price') || h == 'price',
      );
      dateCol = _headerCol(headers, (h) => h.contains('trade date'));
      brokerageCol = _headerCol(
        headers,
        (h) => h.contains('brok') || h.contains('brokerage'),
      );
      chargesCol = _headerCol(headers, (h) => h.contains('transaction charges'));
      stampCol = _headerCol(headers, (h) => h.contains('stamp'));
      sttCol = _headerCol(headers, (h) => h == 'stt' || h.startsWith('stt '));
      exchangeCol = _headerCol(headers, (h) => h == 'exchange');
      break;
    }

    if (headerRowIndex == null ||
        nameCol < 0 ||
        actionCol < 0 ||
        qtyCol < 0 ||
        priceCol < 0 ||
        dateCol < 0) {
      return [];
    }

    final txns = <_TradeTxnRow>[];
    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      final name = _cellAt(row, nameCol);
      if (name.isEmpty ||
          name.toUpperCase().contains('TOTAL') ||
          name.toUpperCase() == 'SCRIP NAME') {
        continue;
      }
      final action = _cellAt(row, actionCol);
      if (action.isEmpty) continue;
      final quantity = _parseOptionalNumber(_cellAt(row, qtyCol));
      if (quantity <= 0) continue;
      final date = _parseICICITransactionDate(_cellAt(row, dateCol));
      if (date == null) continue;
      txns.add((
        symbol: '',
        name: name,
        isin: '',
        action: action,
        quantity: quantity,
        price: _parseOptionalNumber(_cellAt(row, priceCol)),
        transactionDate: date,
        brokerage: _parseOptionalNumber(_cellAt(row, brokerageCol)),
        transactionCharges: _parseOptionalNumber(_cellAt(row, chargesCol)),
        stampDuty: _parseOptionalNumber(_cellAt(row, stampCol)),
        segment: '',
        stt: _cellAt(row, sttCol),
        exchange: _cellAt(row, exchangeCol),
      ));
    }
    return txns;
  }

  List<_TradeTxnRow> _parseZerodhaTransactions(Uint8List bytes) {
    return _parseExcelOrDelimitedTxns(bytes, _txnsFromZerodhaTradeRows);
  }

  List<_TradeTxnRow> _txnsFromZerodhaTradeRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    int? headerRowIndex;
    var symbolCol = -1;
    var isinCol = -1;
    var actionCol = -1;
    var qtyCol = -1;
    var priceCol = -1;
    var dateCol = -1;
    var exchangeCol = -1;
    var segmentCol = -1;

    for (var i = 0; i < rows.length; i++) {
      final headers = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final header = _normalizeImportHeader(rows[i][j]);
        if (header.isNotEmpty) headers[header] = j;
      }
      final hasSymbol = headers.keys.any((h) => h == 'symbol');
      final hasTradeDate = headers.keys.any((h) => h.contains('trade date'));
      final hasTradeType = headers.keys.any((h) => h.contains('trade type'));
      if (!hasSymbol || !hasTradeDate || !hasTradeType) continue;

      headerRowIndex = i;
      symbolCol = _headerCol(headers, (h) => h == 'symbol');
      isinCol = _headerCol(headers, (h) => h.contains('isin'));
      actionCol = _headerCol(headers, (h) => h.contains('trade type'));
      qtyCol = _headerCol(headers, (h) => h == 'quantity' || h == 'qty');
      priceCol = _headerCol(headers, (h) => h == 'price');
      dateCol = _headerCol(headers, (h) => h.contains('trade date'));
      exchangeCol = _headerCol(headers, (h) => h == 'exchange');
      segmentCol = _headerCol(headers, (h) => h == 'segment');
      break;
    }

    if (headerRowIndex == null ||
        symbolCol < 0 ||
        actionCol < 0 ||
        qtyCol < 0 ||
        priceCol < 0 ||
        dateCol < 0) {
      return [];
    }

    final txns = <_TradeTxnRow>[];
    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      final symbol = _cellAt(row, symbolCol).toUpperCase();
      final isin = _parseIsinFromCell(_cellAt(row, isinCol)) ?? '';
      if (symbol.isEmpty && isin.isEmpty) continue;
      if (symbol.contains('TOTAL') || symbol == 'SYMBOL') continue;
      final action = _cellAt(row, actionCol);
      if (action.isEmpty) continue;
      final quantity = _parseOptionalNumber(_cellAt(row, qtyCol));
      if (quantity <= 0) continue;
      final date = _parseICICITransactionDate(_cellAt(row, dateCol));
      if (date == null) continue;
      txns.add((
        symbol: symbol,
        name: '',
        isin: isin,
        action: action,
        quantity: quantity,
        price: _parseOptionalNumber(_cellAt(row, priceCol)),
        transactionDate: date,
        brokerage: 0,
        transactionCharges: 0,
        stampDuty: 0,
        segment: _cellAt(row, segmentCol),
        stt: '',
        exchange: _cellAt(row, exchangeCol),
      ));
    }
    return txns;
  }

  List<_TradeTxnRow> _parseBulkTransactions(Uint8List bytes) {
    final fromExcel = _parseExcelOrDelimitedTxns(bytes, _txnsFromBulkTradeRows);
    if (fromExcel.isNotEmpty) return fromExcel;
    try {
      final input = utf8.decode(bytes);
      final fields = const CsvToListConverter().convert(input);
      final rows = fields
          .map((row) => row.map((cell) => cell.toString().trim()).toList())
          .toList();
      return _txnsFromBulkTradeRows(rows);
    } catch (_) {
      return [];
    }
  }

  List<_TradeTxnRow> _txnsFromBulkTradeRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    int? headerRowIndex;
    var symbolCol = -1;
    var actionCol = -1;
    var qtyCol = -1;
    var priceCol = -1;
    var dateCol = -1;

    for (var i = 0; i < rows.length; i++) {
      final headers = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final header = _normalizeImportHeader(rows[i][j]);
        if (header.isNotEmpty) headers[header] = j;
      }
      final hasSymbol = headers.keys.any((h) => h == 'symbol');
      final hasTradeDate = headers.keys.any(
        (h) => h.contains('trade date') || h.contains('transaction date'),
      );
      final hasType = headers.keys.any(
        (h) =>
            h.contains('trade type') ||
            h == 'buy/sell' ||
            h == 'action' ||
            h == 'type',
      );
      if (!hasSymbol || !hasTradeDate || !hasType) continue;

      headerRowIndex = i;
      symbolCol = _headerCol(headers, (h) => h == 'symbol');
      actionCol = _headerCol(
        headers,
        (h) =>
            h.contains('trade type') ||
            h == 'buy/sell' ||
            h == 'action' ||
            h == 'type',
      );
      qtyCol = _headerCol(headers, (h) => h == 'quantity' || h == 'qty');
      priceCol = _headerCol(
        headers,
        (h) => h == 'price' || h.contains('buy price') || h.contains('trade price'),
      );
      dateCol = _headerCol(
        headers,
        (h) => h.contains('trade date') || h.contains('transaction date'),
      );
      break;
    }

    if (headerRowIndex == null ||
        symbolCol < 0 ||
        actionCol < 0 ||
        qtyCol < 0 ||
        priceCol < 0 ||
        dateCol < 0) {
      return [];
    }

    final txns = <_TradeTxnRow>[];
    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      final symbol = _cellAt(row, symbolCol).toUpperCase();
      if (symbol.isEmpty || symbol.contains('TOTAL') || symbol == 'SYMBOL') {
        continue;
      }
      final action = _cellAt(row, actionCol);
      if (action.isEmpty) continue;
      final quantity = _parseOptionalNumber(_cellAt(row, qtyCol));
      if (quantity <= 0) continue;
      final date = _parseICICITransactionDate(_cellAt(row, dateCol));
      if (date == null) continue;
      txns.add((
        symbol: symbol,
        name: '',
        isin: '',
        action: action,
        quantity: quantity,
        price: _parseOptionalNumber(_cellAt(row, priceCol)),
        transactionDate: date,
        brokerage: 0,
        transactionCharges: 0,
        stampDuty: 0,
        segment: '',
        stt: '',
        exchange: '',
      ));
    }
    return txns;
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

      final hasSymbol =
          headers.keys.any((h) => h == 'symbol' || h.contains('symbol'));
      final hasQty = headers.keys.any((h) => h == 'qty' || h.contains('qty'));
      final hasAvgPrice = headers.keys.any(
        (h) => h.contains('avg price') || h.contains('average price'),
      );

      if (hasSymbol && hasQty && hasAvgPrice) {
        headerRowIndex = i;
        symbolCol = headers['symbol'] ??
            headers.entries.firstWhere((e) => e.key.contains('symbol')).value;
        // Prefer exact "qty" over "long term qty"
        qtyCol = headers['qty'] ??
            headers.entries.firstWhere((e) => e.key.contains('qty')).value;
        buyPriceCol = headers.entries
            .firstWhere(
              (e) =>
                  e.key.contains('avg price') ||
                  e.key.contains('average price'),
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

    if (headerRowIndex == null ||
        symbolCol < 0 ||
        qtyCol < 0 ||
        buyPriceCol < 0) {
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
      final hasQtyAvailable =
          headers.keys.any((h) => h == 'quantity available');
      final hasAvgPrice = headers.keys.any(
        (h) => h == 'average price' || h.contains('average price'),
      );

      if (hasSymbol && hasQtyAvailable && hasAvgPrice) {
        headerRowIndex = i;
        symbolCol = headers['symbol'] ??
            headers.entries.firstWhere((e) => e.key.contains('symbol')).value;
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

    if (headerRowIndex == null ||
        symbolCol < 0 ||
        qtyCol < 0 ||
        buyPriceCol < 0) {
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
        final sector = sectorCol >= 0 && sectorCol < row.length
            ? row[sectorCol].trim()
            : '';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBrandTitle(
          widget.stock == null ? 'Add Stock' : 'Edit Stock',
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            if (widget.stock == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: OutlinedButton(
                  onPressed: _isImporting ? null : _confirmAndDeleteAllHoldings,
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
                      : const Text('Delete All Stocks'),
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
                          'Upload ICICIDirect portfolio Excel (Stock Symbol, ISIN Code, Qty, Average Cost Price) or the transactions export (Action, Transaction Date). ISIN auto-maps broker symbols to NSE/Yahoo on import.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isImporting
                                  ? null
                                  : _pickAndImportICICIDirectFile,
                              icon: _isBusy(_StockImportKind.iciciSummary)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.upload_file),
                              label: Text(
                                _isBusy(_StockImportKind.iciciSummary)
                                    ? 'Importing...'
                                    : 'Select ICICIDirect Summary File',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _isImporting
                                  ? null
                                  : _confirmAndImportICICIDirectTransactions,
                              icon: _isBusy(_StockImportKind.iciciTransactions)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.receipt_long),
                              label: Text(
                                _isBusy(_StockImportKind.iciciTransactions)
                                    ? 'Importing...'
                                    : 'Select ICICIDirect Transactions File',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepOrange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            Icon(Icons.account_balance, color: Colors.teal),
                            SizedBox(width: 8),
                            Text(
                              'Import HDFC Securities',
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
                          'Upload HDFC portfolio CSV (Symbol, Qty, Avg Price) or Equity Trade Details Excel (Scrip Name, Trade Date, Buy/Sell). Account: HDFCSec. Scrip names must match Global Stocks.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isImporting
                                  ? null
                                  : _pickAndImportHDFCSecFile,
                              icon: _isBusy(_StockImportKind.hdfc)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.upload_file),
                              label: Text(
                                _isBusy(_StockImportKind.hdfc)
                                    ? 'Importing...'
                                    : 'Select HDFCSec Summary File',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _isImporting
                                  ? null
                                  : _confirmAndImportHDFCTransactions,
                              icon: _isBusy(_StockImportKind.hdfcTransactions)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.receipt_long),
                              label: Text(
                                _isBusy(_StockImportKind.hdfcTransactions)
                                    ? 'Importing...'
                                    : 'Select HDFCSec Transactions File',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal.shade700,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            Icon(Icons.account_balance, color: Colors.indigo),
                            SizedBox(width: 8),
                            Text(
                              'Import Zerodha',
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
                          'Upload Zerodha holdings Excel (Symbol, ISIN, Quantity Available, Average Price) or tradebook (Symbol, ISIN, Trade Date, Trade Type). Account: Zerodha.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isImporting
                                  ? null
                                  : _pickAndImportZerodhaFile,
                              icon: _isBusy(_StockImportKind.zerodha)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.upload_file),
                              label: Text(
                                _isBusy(_StockImportKind.zerodha)
                                    ? 'Importing...'
                                    : 'Select Zerodha Summary File',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _isImporting
                                  ? null
                                  : _confirmAndImportZerodhaTransactions,
                              icon:
                                  _isBusy(_StockImportKind.zerodhaTransactions)
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.receipt_long),
                              label: Text(
                                _isBusy(_StockImportKind.zerodhaTransactions)
                                    ? 'Importing...'
                                    : 'Select Zerodha Transactions File',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo.shade700,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        if (context.watch<AuthProvider>().isAdmin) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              Icon(Icons.picture_as_pdf,
                                  color: Colors.deepPurple),
                              SizedBox(width: 8),
                              Text(
                                'Import NSDL e-CAS (PDF)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Admin only. Upload the password-protected NSDL Consolidated Account Statement (password = PAN). Updates stocks and MFs under separate CAS accounts (e.g. NSDL ICICI Bank, NSDL HDFC Bank, NSDL MF Folios) — does not merge with ICICIDirect/HDFCSec Excel uploads. Does not store PAN or account numbers.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed:
                                _isImporting ? null : _pickAndImportCasFile,
                            icon: _isBusy(_StockImportKind.cas)
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.upload_file),
                            label: Text(
                              _isBusy(_StockImportKind.cas)
                                  ? 'Importing...'
                                  : 'Select NSDL e-CAS PDF',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
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
                        const SizedBox(height: 8),
                        const Text(
                          'Summary: symbol, quantity, buyPrice. Transactions: Symbol, Trade Date, Trade Type, Quantity, Price. Download a sample, fill it, then upload.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _isImporting
                                  ? null
                                  : _downloadBulkSummarySample,
                              icon: const Icon(Icons.download),
                              label: const Text('Download Summary Sample'),
                            ),
                            ElevatedButton.icon(
                              onPressed:
                                  _isImporting ? null : _pickAndImportFile,
                              icon: _isBusy(_StockImportKind.bulk)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.file_upload),
                              label: Text(
                                _isBusy(_StockImportKind.bulk)
                                    ? 'Importing...'
                                    : 'Select Summary File',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isImporting
                                  ? null
                                  : _downloadBulkTransactionsSample,
                              icon: const Icon(Icons.download),
                              label:
                                  const Text('Download Transactions Sample'),
                            ),
                            ElevatedButton.icon(
                              onPressed: _isImporting
                                  ? null
                                  : _confirmAndImportBulkTransactions,
                              icon: _isBusy(_StockImportKind.bulkTransactions)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.receipt_long),
                              label: Text(
                                _isBusy(_StockImportKind.bulkTransactions)
                                    ? 'Importing...'
                                    : 'Select Transactions File',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  color: Colors.indigo.shade50,
                  child: ExpansionTile(
                    initiallyExpanded: widget.stock != null,
                    leading:
                        Icon(Icons.edit_note, color: Colors.indigo.shade700),
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
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
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
                  constraints:
                      const BoxConstraints(maxHeight: 240, maxWidth: 480),
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
          final watchList = context.watch<AuthProvider>().useAsStockWatchList;
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
              final qty = double.tryParse(value);
              if (qty == null) {
                return 'Please enter a valid number';
              }
              if (qty < 0) {
                return 'Quantity cannot be negative';
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
          helperText:
              _buyPriceFromLtp ? 'Prefilled from Global Stocks LTP' : null,
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
          final price = double.tryParse(value);
          if (price == null) {
            return 'Please enter a valid number';
          }
          if (price < 0) {
            return 'Buy price cannot be negative';
          }
          final qty = double.tryParse(_quantityController.text) ?? 0;
          if (qty > 0 && price <= 0) {
            return 'Buy price must be greater than 0';
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
