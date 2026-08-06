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
  List<MFSchemeMapping> _items = [];
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
      final items = await ApiService.getUnmappedMFSchemes();
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

  Future<void> _editMapping(MFSchemeMapping mapping) async {
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
        title: const AppBrandTitle('Unmapped Mutual Funds'),
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
              : _items.isEmpty
                  ? const Center(
                      child: Text('All broker scheme names are mapped'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final m = _items[index];
                          return Card(
                            child: ListTile(
                              title: Text(
                                m.sourceSchemeName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    'No catalog ISIN mapped yet',
                                    style: TextStyle(
                                      color: Colors.orange.shade800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (m.sourceFormat.isNotEmpty)
                                    Text(
                                      'Source: ${m.sourceFormat}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.edit),
                              onTap: () => _editMapping(m),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
