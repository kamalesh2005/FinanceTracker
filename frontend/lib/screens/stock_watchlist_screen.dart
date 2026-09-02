import 'package:flutter/material.dart';

import '../models/screener_stock.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import '../widgets/screener_stock_table.dart';
import '../utils/screen_tracker.dart';
import 'add_stock_screen.dart';
import 'stock_screener_screen.dart';

class StockWatchlistScreen extends StatefulWidget {
  const StockWatchlistScreen({super.key});

  @override
  State<StockWatchlistScreen> createState() => _StockWatchlistScreenState();
}

class _StockWatchlistScreenState extends State<StockWatchlistScreen>
    with ScreenerColumnController {
  List<ScreenerStock> _items = [];
  List<String> _labelOptions = [];
  bool _loading = true;
  String? _error;
  int? _busyStockId;

  @override
  void initState() {
    super.initState();
    loadScreenerColumns();
    _load();
    _loadLabelOptions();
  }

  Future<void> _loadLabelOptions() async {
    try {
      final opts = await ApiService.screenerOptions();
      if (!mounted) return;
      setState(() => _labelOptions = opts.labels);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ApiService.getWatchlist();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _remove(ScreenerStock stock) async {
    setState(() => _busyStockId = stock.id);
    try {
      await ApiService.removeFromWatchlist(stock.id);
      if (!mounted) return;
      setState(() {
        _items = _items.where((s) => s.id != stock.id).toList();
        _busyStockId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyStockId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _buy(ScreenerStock stock) async {
    await Navigator.push(
      context,
      appPageRoute(AddStockScreen(stock: stock.toBuyStock())),
    );
  }

  Future<void> _addLabel(ScreenerStock stock, String label) async {
    setState(() => _busyStockId = stock.id);
    try {
      final updated = await ApiService.addScreenerLabel(stock.id, label);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((s) => s.id == stock.id ? s.copyWith(labels: updated.labels) : s)
            .toList();
        _busyStockId = null;
        if (!_labelOptions.contains(label)) {
          _labelOptions = [..._labelOptions, label]..sort();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyStockId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _removeLabel(ScreenerStock stock, String label) async {
    setState(() => _busyStockId = stock.id);
    try {
      await ApiService.removeScreenerLabel(stock.id, label);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((s) => s.id == stock.id
                ? s.copyWith(
                    labels: s.labels.where((l) => l != label).toList(),
                  )
                : s)
            .toList();
        _busyStockId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyStockId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _openScreener() {
    Navigator.pushReplacement(
      context,
      appPageRoute(const StockScreenerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showTableView = MediaQuery.sizeOf(context).width >=
        ScreenerStockTable.cardViewBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('WatchList'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            if (showTableView)
              IconButton(
                icon: const Icon(Icons.view_column),
                tooltip: 'Columns',
                onPressed: showScreenerColumnDialog,
              ),
            TextButton(
              onPressed: _openScreener,
              child: const Text('Evaluate Stocks to Buy'),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ScreenerDataDisclaimer(),
            const SizedBox(height: 12),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No stocks on your WatchList yet'),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _openScreener,
              child: const Text('Evaluate Stocks to Buy'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_items.length} stock${_items.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ScreenerStockTable(
            stocks: _items,
            selectedColumns: selectedScreenerColumns,
            busyStockId: _busyStockId,
            labelOptions: _labelOptions,
            onBuy: _buy,
            onRemoveWatchlist: _remove,
            onAddLabel: _addLabel,
            onRemoveLabel: _removeLabel,
          ),
        ),
      ],
    );
  }
}
