import 'package:flutter/material.dart';
import '../models/symbol_mapping.dart';
import '../services/api_service.dart';

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
  late String _sourceFormat;
  bool _saving = false;

  static const _formats = ['ICICIDirect', 'NSE', 'Manual', 'Other'];

  @override
  void initState() {
    super.initState();
    final m = widget.mapping;
    _sourceController = TextEditingController(
      text: m?.sourceSymbol ?? widget.initialSourceSymbol ?? '',
    );
    _yahooController = TextEditingController(
      text: m?.yahooSymbol ?? widget.initialYahooSymbol ?? '',
    );
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
    super.dispose();
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
        title: Text(isEdit ? 'Edit Mapping' : 'Add Mapping'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
              TextFormField(
                controller: _yahooController,
                decoration: const InputDecoration(
                  labelText: 'Yahoo / NSE Symbol *',
                  hintText: 'e.g. HEROMOTOCO, AXISBANK, M&M',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
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
