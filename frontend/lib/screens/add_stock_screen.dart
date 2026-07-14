import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import '../providers/finance_provider.dart';
import '../models/stock.dart';

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

  @override
  void initState() {
    super.initState();
    _symbolController = TextEditingController(text: widget.stock?.symbol ?? '');
    _nameController = TextEditingController(text: widget.stock?.name ?? '');
    _quantityController = TextEditingController(text: widget.stock?.quantity.toString() ?? '');
    _buyPriceController = TextEditingController(text: widget.stock?.buyPrice.toString() ?? '');
    _currentPriceController = TextEditingController(text: widget.stock?.currentPrice.toString() ?? '');
    _transactionDate = DateTime.now();
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

  Future<void> _pickAndImportFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _isImporting = true;
        });

        final file = File(result.files.single.path!);
        final extension = result.files.single.extension?.toLowerCase();

        List<Stock> stocks = [];

        if (extension == 'csv') {
          stocks = await _parseCSV(file);
        } else if (extension == 'xlsx' || extension == 'xls') {
          stocks = await _parseExcel(file);
        }

        setState(() {
          _importedStocks = stocks;
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
          ),
        );
      }
    }
  }

  Future<List<Stock>> _parseCSV(File file) async {
    final input = await file.readAsString();
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

  Future<List<Stock>> _parseExcel(File file) async {
    final bytes = await file.readAsBytes();
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

  Future<void> _saveImportedStocks() async {
    if (_importedStocks.isEmpty) return;

    final provider = context.read<FinanceProvider>();
    await provider.addStocksBulk(_importedStocks);

    if (provider.error != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${provider.error}'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    setState(() {
      _importedStocks = [];
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
        title: Text(widget.stock == null ? 'Add Stock' : 'Edit Stock'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
                        Row(
                          children: [
                            const Icon(Icons.upload_file, color: Colors.blue),
                            const SizedBox(width: 8),
                            const Text(
                              'Import from CSV/Excel',
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
                                    '${stock.quantity} @ ₹${stock.buyPrice.toStringAsFixed(2)}',
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
                                    });
                                  },
                                  child: const Text('Clear'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
              TextFormField(
                controller: _quantityController,
                decoration: const InputDecoration(
                  labelText: 'Quantity *',
                  hintText: 'e.g., 10',
                  border: OutlineInputBorder(),
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
                          _buildInfoRow('6th Highest Price', '₹${widget.stock!.sixthHighestPrice.toStringAsFixed(2)}'),
                        if (widget.stock!.sixthLowestPrice > 0)
                          _buildInfoRow('6th Lowest Price', '₹${widget.stock!.sixthLowestPrice.toStringAsFixed(2)}'),
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
                              final stock = Stock(
                                id: widget.stock?.id ?? 0,
                                symbol: _symbolController.text.toUpperCase(),
                                name: _nameController.text,
                                quantity: double.parse(_quantityController.text),
                                buyPrice: double.parse(_buyPriceController.text),
                                currentPrice: _currentPriceController.text.isEmpty
                                    ? 0.0
                                    : double.parse(_currentPriceController.text),
                                createdAt: widget.stock?.createdAt ?? DateTime.now(),
                                updatedAt: DateTime.now(),
                              );

                              if (widget.stock == null) {
                                await provider.addStock(stock);
                              } else {
                                await provider.updateStock(widget.stock!.id, stock);
                              }

                              if (provider.error != null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: ${provider.error}'), backgroundColor: Colors.red),
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
            ],
          ),
        ),
      ),
    );
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
