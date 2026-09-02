import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'freedom_api.dart';
import 'freedom_theme.dart';
import 'models/ff_models.dart';
import '../utils/currency_format.dart';

/// Shared column widths so Monthly/Annual (and asset Value) line up.
class FfCols {
  static const titleFlex = 3;
  static const pct = 72.0;
  static const value = 132.0;
  static const monthly = 128.0;
  static const annual = 128.0;
  static const emi = 110.0;
  /// Months left — at most 3 digits.
  static const months = 72.0;
  static const income = 110.0;
  /// Calendar year — 4 digits (end year / expected year).
  static const year = 76.0;
  static const endYear = year;
  static const actions = 120.0;
  /// IconButton default visual size — keep empty slots the same width.
  static const actionSlot = 40.0;
}

List<TextInputFormatter> get ffMonthsFormatters => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(3),
    ];

List<TextInputFormatter> get ffYearFormatters => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(4),
    ];

/// Always occupies [FfCols.actionSlot] so field columns stay aligned across rows.
Widget ffActionSlot({
  required IconData icon,
  required String tooltip,
  VoidCallback? onPressed,
}) {
  return SizedBox(
    width: FfCols.actionSlot,
    height: FfCols.actionSlot,
    child: onPressed == null
        ? null
        : IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: FfCols.actionSlot,
              minHeight: FfCols.actionSlot,
            ),
            tooltip: tooltip,
            icon: Icon(icon, size: 22),
            onPressed: onPressed,
          ),
  );
}

List<TextInputFormatter> get ffNumFormatters => [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
    ];

List<TextInputFormatter> get ffIntFormatters => [
      FilteringTextInputFormatter.digitsOnly,
    ];

double ffParseDouble(String s) => double.tryParse(s.trim()) ?? 0;

int? ffParseIntOpt(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  return int.tryParse(t);
}

String ffTrimNum(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

Widget ffIncomeAssetsBanner(BuildContext context, {required Widget child}) {
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: freedomSeed.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: freedomSeed.withValues(alpha: 0.25)),
    ),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: freedomSeed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Enter amounts or % return post-tax as per your tax bracket.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

Widget ffExpensesBanner(BuildContext context, {required Widget child}) {
  const expenseAccent = Color(0xFFBF360C);
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: expenseAccent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: expenseAccent.withValues(alpha: 0.28)),
    ),
    padding: const EdgeInsets.all(12),
    child: Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: expenseAccent,
            ),
      ),
      child: child,
    ),
  );
}

/// Opens an in-dialog editable table for multiple asset lines of one preset.
/// Returns true if anything was saved (caller should reload).
Future<bool?> showAssetLinesDialog({
  required BuildContext context,
  required FFAssetPreset preset,
  required List<FFAsset> lines,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AssetLinesDialog(preset: preset, lines: lines),
  );
}

class _LineEditors {
  final int? id;
  final TextEditingController name;
  final TextEditingController value;
  final TextEditingController incomePct;
  final TextEditingController emi;
  final TextEditingController months;
  final TextEditingController liability;
  final TextEditingController taxPct;
  final TextEditingController startYear;
  final TextEditingController endYear;
  final bool isLiquid;

  _LineEditors({
    this.id,
    required this.name,
    required this.value,
    required this.incomePct,
    required this.emi,
    required this.months,
    required this.liability,
    required this.taxPct,
    required this.startYear,
    required this.endYear,
    required this.isLiquid,
  });

  factory _LineEditors.fromAsset(FFAsset a) {
    return _LineEditors(
      id: a.id,
      name: TextEditingController(text: a.name),
      value: TextEditingController(
        text: a.value != 0 ? ffTrimNum(a.value) : '',
      ),
      incomePct: TextEditingController(text: ffTrimNum(a.incomePct)),
      emi: TextEditingController(
        text: a.emiAmount != 0 ? ffTrimNum(a.emiAmount) : '',
      ),
      months: TextEditingController(
        text: a.emiInstallmentsLeft != 0 ? '${a.emiInstallmentsLeft}' : '',
      ),
      liability: TextEditingController(
        text: a.linkedLiability != 0 ? ffTrimNum(a.linkedLiability) : '0',
      ),
      taxPct: TextEditingController(text: ffTrimNum(a.taxPct)),
      startYear: TextEditingController(text: '${a.incomeStartYear}'),
      endYear: TextEditingController(text: a.incomeEndYear?.toString() ?? ''),
      isLiquid: a.isLiquid,
    );
  }

  factory _LineEditors.blank(FFAssetPreset preset, int index) {
    final y = DateTime.now().year;
    final label =
        index <= 1 ? preset.name : '${preset.name} #$index';
    return _LineEditors(
      name: TextEditingController(text: label),
      value: TextEditingController(),
      incomePct: TextEditingController(text: ffTrimNum(preset.incomePct)),
      emi: TextEditingController(),
      months: TextEditingController(),
      liability: TextEditingController(text: '0'),
      taxPct: TextEditingController(text: '0'),
      startYear: TextEditingController(text: '$y'),
      endYear: TextEditingController(),
      isLiquid: preset.isLiquid,
    );
  }

  void dispose() {
    name.dispose();
    value.dispose();
    incomePct.dispose();
    emi.dispose();
    months.dispose();
    liability.dispose();
    taxPct.dispose();
    startYear.dispose();
    endYear.dispose();
  }

  Map<String, dynamic> toBody(FFAssetPreset preset) {
    final start = ffParseIntOpt(startYear.text) ?? DateTime.now().year;
    return {
      'category': preset.category,
      'preset_key': preset.key,
      'name': name.text.trim().isEmpty ? preset.name : name.text.trim(),
      'value': ffParseDouble(value.text),
      'is_liquid': isLiquid,
      'linked_liability': ffParseDouble(liability.text),
      'emi_amount': preset.allowsEmi ? ffParseDouble(emi.text) : 0,
      'emi_installments_left':
          preset.allowsEmi ? (ffParseIntOpt(months.text) ?? 0) : 0,
      'income_pct': ffParseDouble(incomePct.text),
      'income_start_year': start,
      'income_end_year': ffParseIntOpt(endYear.text),
      'tax_pct': ffParseDouble(taxPct.text),
    };
  }
}

class _AssetLinesDialog extends StatefulWidget {
  final FFAssetPreset preset;
  final List<FFAsset> lines;

  const _AssetLinesDialog({required this.preset, required this.lines});

  @override
  State<_AssetLinesDialog> createState() => _AssetLinesDialogState();
}

class _AssetLinesDialogState extends State<_AssetLinesDialog> {
  late final List<_LineEditors> _rows;
  final List<int> _deletedIds = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.lines.isEmpty) {
      _rows = [_LineEditors.blank(widget.preset, 1)];
    } else {
      _rows = widget.lines.map(_LineEditors.fromAsset).toList();
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    setState(() {
      _rows.add(_LineEditors.blank(widget.preset, _rows.length + 1));
    });
  }

  Future<void> _deleteRow(int index) async {
    final row = _rows[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${row.name.text.trim().isEmpty ? 'line' : row.name.text}?'),
        content: const Text('This cannot be undone after you save.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      if (row.id != null) _deletedIds.add(row.id!);
      row.dispose();
      _rows.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      for (final id in _deletedIds) {
        await FreedomApi.deleteAsset(id);
      }
      for (final row in _rows) {
        final body = row.toBody(widget.preset);
        if (row.id == null) {
          await FreedomApi.createAsset(body);
        } else {
          await FreedomApi.updateAsset(row.id!, body);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowsEmi = widget.preset.allowsEmi;
    final synced = widget.preset.fromPortfolio;
    return AlertDialog(
      title: Text('${widget.preset.name} — details'),
      content: SizedBox(
        width: allowsEmi ? 640 : 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (synced)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Value is synced from Stocks & Mutual Funds and cannot be '
                  'deleted. You can still adjust income %.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: allowsEmi ? 600 : 500),
                child: Column(
                  children: [
                    _headerRow(allowsEmi),
                    const Divider(height: 12),
                    if (_rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No lines. Tap Add line.'),
                      ),
                    for (var i = 0; i < _rows.length; i++)
                      _dataRow(i, allowsEmi),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        if (!synced)
          OutlinedButton.icon(
            onPressed: _saving ? null : _addLine,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add line'),
          ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _headerRow(bool allowsEmi) {
    Text style(String t) => Text(
          t,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        );
    return Row(
      children: [
        SizedBox(width: 140, child: style('Name')),
        SizedBox(width: FfCols.value, child: style('Value ₹ (in K)')),
        SizedBox(width: FfCols.pct, child: style('%')),
        SizedBox(width: FfCols.income, child: style('Income')),
        if (allowsEmi) ...[
          SizedBox(width: FfCols.emi, child: style('EMI ₹ (in K)')),
          SizedBox(width: FfCols.months, child: style('Mo. left')),
        ],
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _dataRow(int index, bool allowsEmi) {
    final row = _rows[index];
    final synced = widget.preset.fromPortfolio;
    final income =
        ffParseDouble(row.value.text) * ffParseDouble(row.incomePct.text) / 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: TextField(
              controller: row.name,
              readOnly: synced,
              style: freedomInputValueStyle(context, readOnly: synced),
              decoration: freedomFieldDecoration(context),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: FfCols.value,
            child: TextField(
              controller: row.value,
              readOnly: synced,
              style: freedomInputValueStyle(context, readOnly: synced),
              decoration: freedomFieldDecoration(context),
              keyboardType: TextInputType.number,
              inputFormatters: ffNumFormatters,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: FfCols.pct,
            child: TextField(
              controller: row.incomePct,
              decoration: freedomFieldDecoration(context),
              keyboardType: TextInputType.number,
              inputFormatters: ffNumFormatters,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: FfCols.income,
            child: Text(
              formatInrK(income),
              style: TextStyle(
                color: freedomSeed,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          if (allowsEmi) ...[
            const SizedBox(width: 4),
            SizedBox(
              width: FfCols.emi,
              child: TextField(
                controller: row.emi,
                decoration: freedomFieldDecoration(context),
                keyboardType: TextInputType.number,
                inputFormatters: ffNumFormatters,
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: FfCols.months,
              child: TextField(
                controller: row.months,
                decoration: freedomFieldDecoration(
                  context,
                  labelText: 'Mo. left',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: ffMonthsFormatters,
              ),
            ),
          ],
          if (!synced)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : () => _deleteRow(index),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}
