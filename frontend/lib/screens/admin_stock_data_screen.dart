import 'package:flutter/material.dart';
import '../models/stock.dart';
import '../services/api_service.dart';
import '../widgets/auth_app_bar_actions.dart';

class AdminStockDataScreen extends StatefulWidget {
  const AdminStockDataScreen({super.key});

  @override
  State<AdminStockDataScreen> createState() => _AdminStockDataScreenState();
}

class _AdminStockDataScreenState extends State<AdminStockDataScreen> {
  final _searchController = TextEditingController();
  List<Stock> _allStocks = [];
  List<Stock> _filtered = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stocks = await ApiService.getStocks();
      if (!mounted) return;
      setState(() {
        _allStocks = stocks;
        _applyFilter(_searchController.text);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(_allStocks);
      } else {
        _filtered = _allStocks.where((s) {
          return s.symbol.toLowerCase().contains(q) ||
              s.name.toLowerCase().contains(q) ||
              s.sector.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  Future<void> _editStock(Stock stock) async {
    final nameController = TextEditingController(text: stock.name);
    final sectorController = TextEditingController(text: stock.sector);
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
                controller: sectorController,
                decoration: const InputDecoration(
                  labelText: 'Sector',
                  hintText: 'e.g. Technology, Financial Services',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) {
      nameController.dispose();
      sectorController.dispose();
      return;
    }

    try {
      await ApiService.updateStockAdminFields(
        stock.id,
        name: nameController.text.trim(),
        sector: sectorController.text.trim(),
      );
      nameController.dispose();
      sectorController.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock updated'), backgroundColor: Colors.green),
      );
      _load();
    } catch (e) {
      nameController.dispose();
      sectorController.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Stock Data'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by symbol, name, or sector…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _applyFilter('');
                  },
                ),
              ),
              onChanged: _applyFilter,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _filtered.isEmpty
                        ? const Center(child: Text('No stocks found'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) {
                                final s = _filtered[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      s.symbol,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      [
                                        if (s.name.isNotEmpty) s.name,
                                        'Sector: ${s.sector.isEmpty ? "—" : s.sector}',
                                      ].join('\n'),
                                    ),
                                    isThreeLine: s.name.isNotEmpty,
                                    trailing: const Icon(Icons.edit),
                                    onTap: () => _editStock(s),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
