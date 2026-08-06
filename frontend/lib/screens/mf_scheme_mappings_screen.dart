import 'package:flutter/material.dart';

import '../models/mf_scheme_mapping.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import 'edit_mf_scheme_mapping_screen.dart';

class MFSchemeMappingsScreen extends StatefulWidget {
  const MFSchemeMappingsScreen({super.key});

  @override
  State<MFSchemeMappingsScreen> createState() => _MFSchemeMappingsScreenState();
}

class _MFSchemeMappingsScreenState extends State<MFSchemeMappingsScreen> {
  final _searchController = TextEditingController();
  List<MFSchemeMapping> _mappings = [];
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
      final mappings = await ApiService.getMFSchemeMappings(query: query);
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

  Future<void> _openEditor({MFSchemeMapping? mapping}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditMFSchemeMappingScreen(mapping: mapping),
      ),
    );
    if (changed == true) {
      _load(query: _searchController.text.trim());
    }
  }

  Future<void> _delete(MFSchemeMapping mapping) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete mapping?'),
        content: Text('Remove mapping for "${mapping.sourceSchemeName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.deleteMFSchemeMapping(mapping.id);
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
        title: const AppBrandTitle('Mutual Fund Scheme Mappings'),
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
                hintText: 'Search scheme name or ISIN…',
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
                            onRefresh: () =>
                                _load(query: _searchController.text.trim()),
                            child: ListView.builder(
                              itemCount: _mappings.length,
                              itemBuilder: (context, index) {
                                final m = _mappings[index];
                                final mapped = m.isMapped
                                    ? m.mappedIsin
                                    : '(unmapped)';
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      m.sourceSchemeName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      [
                                        '→ $mapped',
                                        if (m.sourceFormat.isNotEmpty)
                                          m.sourceFormat,
                                        if (m.notes.isNotEmpty) m.notes,
                                      ].join(' · '),
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _openEditor(mapping: m);
                                        }
                                        if (value == 'delete') _delete(m);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
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
