import 'package:flutter/material.dart';
import '../models/symbol_mapping.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import 'edit_symbol_mapping_screen.dart';

class UnmappedStocksScreen extends StatefulWidget {
  const UnmappedStocksScreen({super.key});

  @override
  State<UnmappedStocksScreen> createState() => _UnmappedStocksScreenState();
}

class _UnmappedStocksScreenState extends State<UnmappedStocksScreen> {
  List<UnmappedStock> _stocks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stocks = await ApiService.getUnmappedStocks();
      if (!mounted) return;
      setState(() {
        _stocks = stocks;
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

  Future<void> _editMapping(UnmappedStock stock) async {
    SymbolMapping? existing;
    if (stock.hasMapping) {
      final all = await ApiService.getSymbolMappings(query: stock.symbol);
      for (final m in all) {
        if (m.sourceSymbol.toUpperCase() == stock.symbol.toUpperCase()) {
          existing = m;
          break;
        }
      }
    }

    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditSymbolMappingScreen(
          mapping: existing,
          initialSourceSymbol: stock.symbol,
          initialYahooSymbol: stock.yahooSymbol.isNotEmpty ? stock.yahooSymbol : null,
          initialIsin: stock.isin.isNotEmpty ? stock.isin : null,
          initialSourceFormat: 'ICICIDirect',
        ),
      ),
    );
    if (changed == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Unmapped Stocks'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _stocks.isEmpty
                  ? const Center(
                      child: Text('All stocks have working Yahoo mappings'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _stocks.length,
                        itemBuilder: (context, index) {
                          final s = _stocks[index];
                          return Card(
                            child: ListTile(
                              title: Text(
                                s.symbol,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (s.name.isNotEmpty) Text(s.name),
                                  const SizedBox(height: 4),
                                  Text(
                                    s.reason,
                                    style: TextStyle(
                                      color: Colors.orange.shade800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    s.hasMapping
                                        ? 'Current Yahoo: ${s.yahooSymbol}'
                                        : 'No mapping yet',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (s.isin.isNotEmpty)
                                    Text(
                                      'ISIN: ${s.isin}',
                                      style: const TextStyle(fontSize: 12),
                                    )
                                  else
                                    const Text(
                                      'ISIN: not in symbol mapping — re-import ICICI file with ISIN column',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.edit),
                              onTap: () => _editMapping(s),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
