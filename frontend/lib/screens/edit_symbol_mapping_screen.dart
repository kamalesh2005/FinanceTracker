import 'package:flutter/material.dart';
import '../models/symbol_mapping.dart';
import '../services/api_service.dart';
import '../utils/currency_format.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

class EditSymbolMappingScreen extends StatefulWidget {
  final SymbolMapping? mapping;
  final String? initialSourceSymbol;
  final String? initialYahooSymbol;
  final String? initialIsin;
  final String? initialSourceFormat;

  const EditSymbolMappingScreen({
    super.key,
    this.mapping,
    this.initialSourceSymbol,
    this.initialYahooSymbol,
    this.initialIsin,
    this.initialSourceFormat,
  });

  @override
  State<EditSymbolMappingScreen> createState() => _EditSymbolMappingScreenState();
}

class _EditSymbolMappingScreenState extends State<EditSymbolMappingScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _sourceController;
  late TextEditingController _yahooController;
  late TextEditingController _isinController;
  late TextEditingController _notesController;
  final _yahooFocusNode = FocusNode();
  late String _sourceFormat;
  bool _saving = false;

  /// Catalog symbol confirmed via autocomplete selection or initial prefill.
  String? _confirmedYahooSymbol;
  String? _confirmedYahooName;

  static const _formats = ['ICICIDirect', 'NSE', 'Manual', 'Other'];

  @override
  void initState() {
    super.initState();
    final m = widget.mapping;
    _sourceController = TextEditingController(
      text: m?.sourceSymbol ?? widget.initialSourceSymbol ?? '',
    );
    final yahoo = (m?.yahooSymbol ?? widget.initialYahooSymbol ?? '').trim();
    _yahooController = TextEditingController(text: yahoo);
    if (yahoo.isNotEmpty) {
      _confirmedYahooSymbol = yahoo.toUpperCase();
    }
    _isinController = TextEditingController(
      text: m?.isin ?? widget.initialIsin ?? '',
    );
    _notesController = TextEditingController(text: m?.notes ?? '');
    final format = m?.sourceFormat ?? widget.initialSourceFormat ?? 'Manual';
    _sourceFormat = _formats.contains(format) ? format : 'Other';
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _yahooController.dispose();
    _isinController.dispose();
    _notesController.dispose();
    _yahooFocusNode.dispose();
    super.dispose();
  }

  Future<List<({String symbol, String name, double currentPrice})>>
      _searchCatalog(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      return await ApiService.searchGlobalStocks(q);
    } catch (_) {
      return [];
    }
  }

  void _selectCatalogHit(
    ({String symbol, String name, double currentPrice}) hit,
  ) {
    final symbol = hit.symbol.toUpperCase();
    setState(() {
      _yahooController.text = symbol;
      _yahooController.selection =
          TextSelection.collapsed(offset: symbol.length);
      _confirmedYahooSymbol = symbol;
      _confirmedYahooName = hit.name;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final mapping = SymbolMapping(
        id: widget.mapping?.id ?? 0,
        sourceSymbol: _sourceController.text.trim().toUpperCase(),
        yahooSymbol: _yahooController.text.trim(),
        isin: _isinController.text.trim().toUpperCase(),
        sourceFormat: _sourceFormat,
        notes: _notesController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      if (widget.mapping == null) {
        await ApiService.createSymbolMapping(mapping);
      } else {
        await ApiService.updateSymbolMapping(widget.mapping!.id, mapping);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mapping saved. Refresh stock prices to pull Yahoo data.'),
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
    return Scaffold(
      appBar: AppBar(
        title: AppBrandTitle(isEdit ? 'Edit Mapping' : 'Add Mapping'),
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
                decoration: const InputDecoration(
                  labelText: 'Source Symbol *',
                  hintText: 'e.g. HERHON, AXIBAN',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              RawAutocomplete<({String symbol, String name, double currentPrice})>(
                textEditingController: _yahooController,
                focusNode: _yahooFocusNode,
                displayStringForOption: (o) => o.symbol,
                optionsBuilder: (TextEditingValue value) async {
                  final q = value.text.trim();
                  if (q.isEmpty) {
                    return const Iterable<
                        ({String symbol, String name, double currentPrice})>.empty();
                  }
                  await Future<void>.delayed(const Duration(milliseconds: 250));
                  if (!mounted || _yahooController.text.trim() != q) {
                    return const Iterable<
                        ({String symbol, String name, double currentPrice})>.empty();
                  }
                  return _searchCatalog(q);
                },
                onSelected: _selectCatalogHit,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Yahoo / NSE Symbol *',
                      hintText: 'Start typing to search catalog',
                      border: const OutlineInputBorder(),
                      helperText: _confirmedYahooName != null &&
                              _confirmedYahooName!.isNotEmpty
                          ? _confirmedYahooName
                          : 'Choose a symbol from the NSE catalog',
                    ),
                    onChanged: (_) {
                      if (_confirmedYahooSymbol != null &&
                          _confirmedYahooSymbol !=
                              controller.text.trim().toUpperCase()) {
                        setState(() {
                          _confirmedYahooSymbol = null;
                          _confirmedYahooName = null;
                        });
                      }
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      final sym = value.trim().toUpperCase();
                      if (_confirmedYahooSymbol == null ||
                          _confirmedYahooSymbol != sym) {
                        return 'Select a symbol from the catalog suggestions';
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
                          maxHeight: 240,
                          maxWidth: 480,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            final price = option.currentPrice > 0
                                ? ' · ${formatInr(option.currentPrice)}'
                                : '';
                            return ListTile(
                              dense: true,
                              title: Text(
                                option.symbol,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${option.name}$price',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
              TextFormField(
                controller: _isinController,
                decoration: const InputDecoration(
                  labelText: 'ISIN',
                  hintText: 'e.g. INE081A01020',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _sourceFormat,
                decoration: const InputDecoration(
                  labelText: 'Source Format',
                  border: OutlineInputBorder(),
                ),
                items: _formats
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _sourceFormat = v);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Optional',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_saving ? 'Saving…' : 'Save Mapping'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
