import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/stock.dart';
import '../providers/auth_provider.dart';
import '../providers/finance_provider.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

class EditStockScreen extends StatefulWidget {
  final Stock stock;

  const EditStockScreen({super.key, required this.stock});

  @override
  State<EditStockScreen> createState() => _EditStockScreenState();
}

class _EditStockScreenState extends State<EditStockScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _symbolController;
  late TextEditingController _quantityController;
  late TextEditingController _buyPriceController;

  @override
  void initState() {
    super.initState();
    _symbolController = TextEditingController(text: widget.stock.symbol);
    _quantityController = TextEditingController(
      text: _formatNumber(widget.stock.quantity),
    );
    _buyPriceController = TextEditingController(
      text: _formatNumber(widget.stock.buyPrice),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AuthProvider>().useAsStockWatchList) {
        _quantityController.text = '1';
        setState(() {});
      }
    });
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _quantityController.dispose();
    _buyPriceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<FinanceProvider>();
    final watchList = context.read<AuthProvider>().useAsStockWatchList;
    final ok = await provider.updateStockHoldings(
      stockId: widget.stock.id,
      symbol: _symbolController.text.trim().toUpperCase(),
      quantity: watchList ? 1.0 : double.parse(_quantityController.text.trim()),
      price: double.parse(_buyPriceController.text.trim()),
    );

    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to update holdings'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final watchList = context.watch<AuthProvider>().useAsStockWatchList;
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Edit Stock'),
        actions: authAppBarActions(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.stock.name.isNotEmpty) ...[
                Text(
                  widget.stock.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _symbolController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Symbol',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter symbol';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                enabled: !watchList,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  border: const OutlineInputBorder(),
                  helperText: watchList
                      ? 'Watch list mode always saves quantity as 1'
                      : null,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter quantity';
                  }
                  final qty = double.tryParse(value.trim());
                  if (qty == null || qty <= 0) {
                    return 'Quantity must be greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _buyPriceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Buy Price',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter buy price';
                  }
                  final price = double.tryParse(value.trim());
                  if (price == null || price <= 0) {
                    return 'Buy price must be greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Consumer<FinanceProvider>(
                builder: (context, provider, _) {
                  return ElevatedButton(
                    onPressed: provider.isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: provider.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Update Stock'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
