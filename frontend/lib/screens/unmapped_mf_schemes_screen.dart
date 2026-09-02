import 'package:flutter/material.dart';

import '../models/mf_scheme_mapping.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import 'edit_mf_scheme_mapping_screen.dart';

class UnmappedMFSchemesScreen extends StatefulWidget {
  const UnmappedMFSchemesScreen({super.key});

  @override
  State<UnmappedMFSchemesScreen> createState() =>
      _UnmappedMFSchemesScreenState();
}

class _UnmappedMFSchemesScreenState extends State<UnmappedMFSchemesScreen> {
  final _searchController = TextEditingController();

  List<MFSchemeMapping> _items = [];
  bool _loading = true;
  String? _error;

  bool _unmappedOnly = true;
  String _ignore = 'N';

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
      final items = await ApiService.getUnmappedMFSchemes(
        q: _searchController.text,
        unmapped: _unmappedOnly,
        ignore: _ignore,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Missing Mutual Funds'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(
          context,
          extra: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Mapping'),
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
                    hintText: 'Search scheme name or ISIN…',
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
                    : _items.isEmpty
                        ? const Center(
                            child: Text('No schemes match these filters'),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final m = _items[index];
                                final mapped = m.isMapped;
                                return Card(
                                  child: ListTile(
                                    title: Text(
                                      m.sourceSchemeName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text(
                                          mapped
                                              ? 'Mapped ISIN: ${m.mappedIsin}'
                                              : 'No catalog ISIN mapped yet',
                                          style: TextStyle(
                                            color: mapped
                                                ? Colors.grey.shade700
                                                : Colors.orange.shade800,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (m.sourceFormat.isNotEmpty)
                                          Text(
                                            'Source: ${m.sourceFormat}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        Text(
                                          'Ignore: ${m.ignore}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        if (m.notes.isNotEmpty)
                                          Text(
                                            'Note: ${m.notes}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                    trailing: const Icon(Icons.edit),
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
