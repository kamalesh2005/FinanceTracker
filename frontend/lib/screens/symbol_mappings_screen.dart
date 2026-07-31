import 'package:flutter/material.dart';
import '../models/symbol_mapping.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import 'edit_symbol_mapping_screen.dart';

class SymbolMappingsScreen extends StatefulWidget {
  const SymbolMappingsScreen({super.key});

  @override
  State<SymbolMappingsScreen> createState() => _SymbolMappingsScreenState();
}

class _SymbolMappingsScreenState extends State<SymbolMappingsScreen> {
  final _searchController = TextEditingController();
  List<SymbolMapping> _mappings = [];
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

  Future<void> _load({String? query}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mappings = await ApiService.getSymbolMappings(query: query);
      if (!mounted) return;
      setState(() {
        _mappings = mappings;
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

  Future<void> _openEditor({SymbolMapping? mapping}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditSymbolMappingScreen(mapping: mapping),
      ),
    );
    if (changed == true) {
      _load(query: _searchController.text.trim());
    }
  }

  Future<void> _delete(SymbolMapping mapping) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete mapping?'),
        content: Text(
          'Remove ${mapping.sourceSymbol} → ${mapping.yahooSymbol}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.deleteSymbolMapping(mapping.id);
      _load(query: _searchController.text.trim());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Symbol Mappings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Mapping'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search source or Yahoo symbol…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _load();
                  },
                ),
              ),
              onSubmitted: (value) => _load(query: value.trim()),
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _mappings.isEmpty
                        ? const Center(child: Text('No mappings found'))
                        : RefreshIndicator(
                            onRefresh: () => _load(query: _searchController.text.trim()),
                            child: ListView.builder(
                              itemCount: _mappings.length,
                              itemBuilder: (context, index) {
                                final m = _mappings[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  child: ListTile(
                                    title: Text(
                                      '${m.sourceSymbol}  →  ${m.yahooSymbol}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      [
                                        if (m.isin.isNotEmpty) m.isin,
                                        if (m.sourceFormat.isNotEmpty) m.sourceFormat,
                                        if (m.notes.isNotEmpty) m.notes,
                                      ].join(' · '),
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') _openEditor(mapping: m);
                                        if (value == 'delete') _delete(m);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                                      ],
                                    ),
                                    onTap: () => _openEditor(mapping: m),
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
