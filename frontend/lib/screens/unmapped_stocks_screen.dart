import 'package:flutter/material.dart';
import '../models/symbol_mapping.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import '../utils/screen_tracker.dart';
import 'edit_symbol_mapping_screen.dart';

class UnmappedStocksScreen extends StatefulWidget {
  const UnmappedStocksScreen({super.key});

  @override
  State<UnmappedStocksScreen> createState() => _UnmappedStocksScreenState();
}

class _UnmappedStocksScreenState extends State<UnmappedStocksScreen> {
  final _searchController = TextEditingController();

  List<UnmappedStock> _stocks = [];
  bool _loading = true;
  String? _error;

  bool _unmappedOnly = true;
  String _ignore = 'N'; // All | N | Y

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
      final stocks = await ApiService.getUnmappedStocks(
        q: _searchController.text,
        unmapped: _unmappedOnly,
        ignore: _ignore,
      );
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
      appPageRoute(
        EditSymbolMappingScreen(
          mapping: existing,
          initialSourceSymbol: stock.symbol,
          initialYahooSymbol:
              stock.yahooSymbol.isNotEmpty ? stock.yahooSymbol : null,
          initialIsin: stock.isin.isNotEmpty ? stock.isin : null,
          initialSourceFormat: 'ICICIDirect',
          initialIndustry: stock.industry.isNotEmpty ? stock.industry : null,
          initialIgnore: stock.ignore.isNotEmpty ? stock.ignore : null,
          initialNotes: stock.notes.isNotEmpty ? stock.notes : null,
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
        title: const AppBrandTitle('Missing Stocks'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search symbol or name…',
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
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('Unmapped'),
                      selected: _unmappedOnly,
                      onSelected: (v) => setState(() => _unmappedOnly = v),
                    ),
                    SizedBox(
                      width: 120,
                      child: DropdownButtonFormField<String>(
                        value: _ignore,
                        decoration: const InputDecoration(
                          labelText: 'Ignore',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(value: 'N', child: Text('N')),
                          DropdownMenuItem(value: 'Y', child: Text('Y')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _ignore = v);
                        },
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Search'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _stocks.isEmpty
                        ? Center(
                            child: Text(
                              _unmappedOnly
                                  ? 'No stocks match these filters'
                                  : 'No stocks match these filters',
                            ),
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
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (s.name.isNotEmpty) Text(s.name),
                                        const SizedBox(height: 4),
                                        Text(
                                          s.reason,
                                          style: TextStyle(
                                            color: s.needsAttention
                                                ? Colors.orange.shade800
                                                : Colors.grey.shade700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          s.hasMapping
                                              ? 'Current Yahoo: ${s.yahooSymbol}'
                                              : 'No mapping yet',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        if (s.hasMapping)
                                          Text(
                                            'Ignore: ${s.ignore.isEmpty ? "N" : s.ignore}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        if (s.notes.isNotEmpty)
                                          Text(
                                            'Note: ${s.notes}',
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
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
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
          ),
        ],
      ),
    );
  }
}
