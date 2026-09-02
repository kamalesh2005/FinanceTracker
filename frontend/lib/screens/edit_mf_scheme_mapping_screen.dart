import 'package:flutter/material.dart';

import '../models/mf_scheme_mapping.dart';
import '../services/api_service.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

class EditMFSchemeMappingScreen extends StatefulWidget {
  final MFSchemeMapping? mapping;
  final String? initialSourceSchemeName;
  final String? initialSourceFormat;

  const EditMFSchemeMappingScreen({
    super.key,
    this.mapping,
    this.initialSourceSchemeName,
    this.initialSourceFormat,
  });

  @override
  State<EditMFSchemeMappingScreen> createState() =>
      _EditMFSchemeMappingScreenState();
}

class _EditMFSchemeMappingScreenState extends State<EditMFSchemeMappingScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _sourceController;
  late TextEditingController _catalogController;
  late TextEditingController _notesController;
  final _catalogFocusNode = FocusNode();
  late String _sourceFormat;
  late String _ignore;
  bool _saving = false;

  String? _confirmedIsin;
  String? _confirmedSchemeName;

  static const _formats = [
    'ICICIDirect',
    'HDFCSec',
    'Manual Bulk Upload',
    'Zerodha',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final m = widget.mapping;
    _sourceController = TextEditingController(
      text: m?.sourceSchemeName ?? widget.initialSourceSchemeName ?? '',
    );
    _catalogController = TextEditingController(
      text: m?.mappedIsin ?? '',
    );
    if (m != null && m.mappedIsin.trim().isNotEmpty) {
      _confirmedIsin = m.mappedIsin.toUpperCase();
    }
    _notesController = TextEditingController(text: m?.notes ?? '');
    final format = m?.sourceFormat ?? widget.initialSourceFormat ?? 'Other';
    _sourceFormat = _formats.contains(format) ? format : 'Other';
    final ignoreRaw = (m?.ignore ?? 'N').trim().toUpperCase();
    _ignore = ignoreRaw == 'Y' ? 'Y' : 'N';
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _catalogController.dispose();
    _notesController.dispose();
    _catalogFocusNode.dispose();
    super.dispose();
  }

  Future<
      List<
          ({
            String isin,
            String symbol,
            String schemeName,
            double currentNav,
          })>> _searchCatalog(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      return await ApiService.searchGlobalMutualFunds(q);
    } catch (_) {
      return [];
    }
  }

  void _selectCatalogHit(
    ({
      String isin,
      String symbol,
      String schemeName,
      double currentNav,
    }) hit,
  ) {
    setState(() {
      _confirmedIsin = hit.isin.toUpperCase();
      _confirmedSchemeName = hit.schemeName;
      _catalogController.text = hit.schemeName;
      _catalogController.selection = TextSelection.collapsed(
        offset: hit.schemeName.length,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final mapping = MFSchemeMapping(
        id: widget.mapping?.id ?? 0,
        sourceSchemeName: _sourceController.text.trim(),
        mappedIsin: _confirmedIsin ?? '',
        sourceFormat: _sourceFormat,
        ignore: _ignore,
        notes: _notesController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      if (widget.mapping == null) {
        await ApiService.createMFSchemeMapping(mapping);
      } else {
        await ApiService.updateMFSchemeMapping(widget.mapping!.id, mapping);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _ignore == 'Y'
                ? 'Saved (ignored).'
                : ((_confirmedIsin == null || _confirmedIsin!.isEmpty)
                    ? 'Saved Ignore/Note.'
                    : 'Mapping saved. Re-upload the broker file to apply.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.mapping != null;
    final sourceLocked = isEdit;

    return Scaffold(
      appBar: AppBar(
        title: AppBrandTitle(
          isEdit ? 'Edit Mutual Fund Mapping' : 'Add Mutual Fund Mapping',
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _sourceController,
                enabled: !sourceLocked,
                decoration: const InputDecoration(
                  labelText: 'Broker Scheme Name *',
                  hintText: 'Exact name from broker export',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              RawAutocomplete<
                  ({
                    String isin,
                    String symbol,
                    String schemeName,
                    double currentNav,
                  })>(
                textEditingController: _catalogController,
                focusNode: _catalogFocusNode,
                displayStringForOption: (o) => o.schemeName,
                optionsBuilder: (TextEditingValue value) async {
                  final q = value.text.trim();
                  if (q.isEmpty) {
                    return const Iterable<
                        ({
                          String isin,
                          String symbol,
                          String schemeName,
                          double currentNav,
                        })>.empty();
                  }
                  await Future<void>.delayed(const Duration(milliseconds: 250));
                  if (!mounted || _catalogController.text.trim() != q) {
                    return const Iterable<
                        ({
                          String isin,
                          String symbol,
                          String schemeName,
                          double currentNav,
                        })>.empty();
                  }
                  return _searchCatalog(q);
                },
                onSelected: _selectCatalogHit,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Global Mutual Fund',
                      hintText: 'Optional — search catalog to map',
                      border: const OutlineInputBorder(),
                      helperText: _confirmedIsin != null
                          ? 'ISIN: $_confirmedIsin'
                              '${_confirmedSchemeName != null ? ' · $_confirmedSchemeName' : ''}'
                          : 'Leave empty to set Ignore/Note only',
                    ),
                    validator: (v) {
                      final text = (v ?? '').trim();
                      if (text.isEmpty) return null;
                      if (_confirmedIsin == null || _confirmedIsin!.isEmpty) {
                        return 'Select a scheme from search results';
                      }
                      return null;
                    },
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 280,
                          maxWidth: 600,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            final nav = option.currentNav > 0
                                ? ' · ${formatInr(option.currentNav)}'
                                : '';
                            return ListTile(
                              dense: true,
                              title: Text(option.schemeName),
                              subtitle: Text(
                                '${option.isin}'
                                '${option.symbol.isNotEmpty ? ' · ${option.symbol}' : ''}'
                                '$nav',
                              ),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Source Format',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _sourceFormat,
                    items: _formats
                        .map(
                          (f) => DropdownMenuItem(value: f, child: Text(f)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _sourceFormat = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _ignore,
                decoration: const InputDecoration(
                  labelText: 'Ignore',
                  helperText:
                      'Y hides this scheme from default missing-funds search',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'N', child: Text('N')),
                  DropdownMenuItem(value: 'Y', child: Text('Y')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _ignore = v);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Optional (max 200 characters)',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                maxLength: 200,
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Mapping'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
