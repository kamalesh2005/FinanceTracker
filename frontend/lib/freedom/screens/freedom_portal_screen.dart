import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../utils/currency_format.dart';
import '../ff_layout.dart';
import '../freedom_api.dart';
import '../freedom_provider.dart';
import '../freedom_theme.dart';
import '../models/ff_models.dart';

class FreedomPortalScreen extends StatefulWidget {
  const FreedomPortalScreen({super.key});

  @override
  State<FreedomPortalScreen> createState() => _FreedomPortalScreenState();
}

class _FreedomPortalScreenState extends State<FreedomPortalScreen> {
  bool _dirty = false;
  bool _savingAll = false;
  final Map<String, Map<String, dynamic>> _pendingUpserts = {};
  final Map<String, int> _pendingDeletes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FreedomProvider>().loadSummary();
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reload() => context.read<FreedomProvider>().loadSummary();

  void _recomputeDirty() {
    _dirty = _pendingUpserts.isNotEmpty || _pendingDeletes.isNotEmpty;
  }

  bool _isPendingDelete(String key) => _pendingDeletes.containsKey(key);

  void _queueDeleteOrClear(String key, int? existingId) {
    // Preset expenses cannot be deleted on the server; clear by upserting zeros.
    if (key.startsWith('expense:preset:')) {
      if (existingId == null) {
        setState(() {
          _pendingUpserts.remove(key);
          _pendingDeletes.remove(key);
          _recomputeDirty();
        });
        return;
      }
      final presetKey = key.substring('expense:preset:'.length);
      _queueUpsert(
        key,
        {
          'preset_key': presetKey,
          'category': presetKey,
          'amount': 0,
          'end_year': null,
        },
        existingId: existingId,
      );
      return;
    }
    setState(() {
      _pendingUpserts.remove(key);
      if (existingId != null) {
        _pendingDeletes[key] = existingId;
      } else {
        _pendingDeletes.remove(key);
      }
      _recomputeDirty();
    });
  }

  void _queueUpsert(String key, Map<String, dynamic> body, {int? existingId}) {
    final payload = Map<String, dynamic>.from(body);
    if (existingId != null) payload['_existing_id'] = existingId;
    setState(() {
      _pendingDeletes.remove(key);
      _pendingUpserts[key] = payload;
      _recomputeDirty();
    });
  }

  void _onJobPresetChanged({
    required FFJobPreset preset,
    required List<FFJobIncome> jobs,
    required double annual,
    int? endYear,
    int? startYear,
    bool isPension = false,
  }) {
    final key = 'job:preset:${preset.key}';
    final existing = _isPendingDelete(key)
        ? null
        : ffJobForPreset(jobs, preset.key);
    if (isPension) {
      if (startYear == null) {
        _queueDeleteOrClear(key, existing?.id);
        return;
      }
      _queueUpsert(
        key,
        {
          'preset_key': preset.key,
          'label': preset.label,
          'amount': annual,
          'start_year': startYear,
        },
        existingId: existing?.id,
      );
      return;
    }
    _queueUpsert(
      key,
      {
        'preset_key': preset.key,
        'label': preset.label,
        'amount': annual,
        'end_year': endYear,
      },
      existingId: existing?.id,
    );
  }

  void _onCustomJobChanged({
    required FFJobIncome job,
    required double annual,
    int? endYear,
  }) {
    final key = 'job:id:${job.id}';
    _queueUpsert(
      key,
      {
        'preset_key': job.presetKey,
        'label': job.label,
        'amount': annual,
        'end_year': endYear,
      },
      existingId: job.id,
    );
  }

  void _onExpenseRowChanged({
    required String key,
    required String category,
    String? presetKey,
    required double annual,
    int? endYear,
    int? existingId,
  }) {
    final id = _isPendingDelete(key) ? null : existingId;
    _queueUpsert(
      key,
      {
        if (presetKey != null) 'preset_key': presetKey,
        'category': category,
        'amount': annual,
        'end_year': endYear,
      },
      existingId: id,
    );
  }

  Future<void> _saveAll() async {
    if (_savingAll || !_dirty) return;
    setState(() => _savingAll = true);
    try {
      for (final entry in _pendingDeletes.entries) {
        final key = entry.key;
        final id = entry.value;
        if (key.startsWith('job:')) {
          await FreedomApi.deleteJobIncome(id);
        } else if (key.startsWith('expense:')) {
          if (key.startsWith('expense:preset:')) {
            final presetKey = key.substring('expense:preset:'.length);
            await FreedomApi.updateExpense(id, {
              'preset_key': presetKey,
              'category': presetKey,
              'amount': 0,
              'end_year': null,
            });
            continue;
          }
          await FreedomApi.deleteExpense(id);
        } else if (key.startsWith('onetime:')) {
          await FreedomApi.deleteOneTime(id);
        }
      }
      _pendingDeletes.clear();

      for (final entry in _pendingUpserts.entries) {
        final key = entry.key;
        final body = Map<String, dynamic>.from(entry.value);
        final existingId = body.remove('_existing_id') as int?;
        if (key.startsWith('asset:')) {
          if (existingId != null) {
            await FreedomApi.updateAsset(existingId, body);
          } else {
            await FreedomApi.createAsset(body);
          }
        } else if (key.startsWith('job:')) {
          if (existingId != null) {
            await FreedomApi.updateJobIncome(existingId, body);
          } else {
            await FreedomApi.createJobIncome(body);
          }
        } else if (key.startsWith('expense:')) {
          if (existingId != null) {
            await FreedomApi.updateExpense(existingId, body);
          } else {
            await FreedomApi.createExpense(body);
          }
        } else if (key.startsWith('onetime:')) {
          if (existingId != null) {
            await FreedomApi.updateOneTime(existingId, body);
          } else {
            await FreedomApi.createOneTime(body);
          }
        }
      }
      _pendingUpserts.clear();
      _dirty = false;
      await _reload();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingAll = false);
    }
  }

  Future<void> _confirmDelete(
    String label,
    Future<void> Function() action, {
    Iterable<String>? pendingKeys,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $label?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (pendingKeys != null) {
        setState(() {
          for (final k in pendingKeys) {
            _pendingUpserts.remove(k);
            _pendingDeletes.remove(k);
          }
          _recomputeDirty();
        });
      }
      await action();
      await _reload();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FreedomProvider>();
    return wrapFreedomPage(Scaffold(
      appBar: AppBar(
        title: freedomBrandTitle(
          context,
          horizonName,
          subtitle: horizonGloss,
        ),
        actions: [
          IconButton(
            tooltip: 'Main portal',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => goToMainPortal(context),
          ),
          ...freedomAppBarActions(context),
        ],
      ),
      body: provider.isLoading && provider.summary == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (provider.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        provider.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: freedomSeed,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'All amounts are in ₹ thousands (K = 1,000). '
                              'Example: enter 500 for ₹5,00,000.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.gavel_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Disclaimer: Please consult your Wealth Manager for '
                              'better financial planning based on individual profiles.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _MetricsRow(metrics: provider.metrics),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final sideBySide = constraints.maxWidth >= 1100;
                      final incomeAssets = _buildIncomeAssetsSection(provider);
                      final expenses = _buildExpensesSection(provider);
                      if (sideBySide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: incomeAssets),
                            const SizedBox(width: 16),
                            Expanded(child: expenses),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          incomeAssets,
                          const SizedBox(height: 20),
                          expenses,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _RetireSimulationTable(rows: provider.retireSimulation),
                  const SizedBox(height: 20),
                  _LiveWellCalculationCard(
                    detail: provider.liveWellDetail,
                    metrics: provider.metrics,
                    assets: provider.assets,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    ));
  }

  Widget _buildJobPresetRow(FreedomProvider provider, FFJobPreset preset) {
    final key = 'job:preset:${preset.key}';
    final pending = _isPendingDelete(key);
    final job =
        pending ? null : ffJobForPreset(provider.jobIncome, preset.key);
    final hasRow =
        job != null || _pendingUpserts.containsKey(key) || pending;
    return _MonthlyAnnualRow(
      key: ValueKey('job-${preset.key}-${job?.id ?? 0}-$pending'),
      title: preset.label,
      annualAmount: job?.amount ?? 0,
      endYear: ffJobDisplayEndYear(job),
      showEndYear: true,
      onChanged: (annual, {endYear, startYear}) => _onJobPresetChanged(
        preset: preset,
        jobs: provider.jobIncome,
        annual: annual,
        endYear: endYear,
      ),
      onDelete: hasRow ? () => _queueDeleteOrClear(key, job?.id) : null,
    );
  }

  Widget _buildCustomJobRow(FFJobIncome job) {
    final key = 'job:id:${job.id}';
    final pending = _isPendingDelete(key);
    return _MonthlyAnnualRow(
      key: ValueKey('job-custom-${job.id}-$pending'),
      title: job.label,
      annualAmount: pending ? 0 : job.amount,
      endYear: pending ? null : ffJobDisplayEndYear(job),
      showEndYear: true,
      onChanged: (annual, {endYear, startYear}) =>
          _onCustomJobChanged(job: job, annual: annual, endYear: endYear),
      onDelete: () => _queueDeleteOrClear(key, job.id),
    );
  }

  Widget _buildPensionRow(FreedomProvider provider) {
    final key = 'job:preset:$ffJobPensionPresetKey';
    final pending = _isPendingDelete(key);
    final job = pending
        ? null
        : ffJobForPreset(provider.jobIncome, ffJobPensionPresetKey);
    final hasRow =
        job != null || _pendingUpserts.containsKey(key) || pending;
    return _MonthlyAnnualRow(
      key: ValueKey('job-pension-${job?.id ?? 0}-$pending'),
      title: ffJobPensionPreset.label,
      annualAmount: job?.amount ?? 0,
      startYear: job?.startYear,
      showStartYear: true,
      titleColor: freedomPensionAccent,
      onChanged: (annual, {endYear, startYear}) => _onJobPresetChanged(
        preset: ffJobPensionPreset,
        jobs: provider.jobIncome,
        annual: annual,
        startYear: startYear,
        isPension: true,
      ),
      onDelete: hasRow ? () => _queueDeleteOrClear(key, job?.id) : null,
    );
  }

  Widget _buildExpensePresetRow(
    FreedomProvider provider,
    FFExpensePreset preset,
  ) {
    final key = 'expense:preset:${preset.key}';
    final pending = _isPendingDelete(key);
    final row =
        pending ? null : ffExpenseForPreset(provider.expenses, preset.key);
    final hasRow =
        row != null || _pendingUpserts.containsKey(key) || pending;
    return _MonthlyAnnualRow(
      key: ValueKey('exp-${preset.key}-${row?.id ?? 0}-$pending'),
      title: preset.label,
      annualAmount: row?.amount ?? 0,
      endYear: row?.endYear,
      showEndYear: ffExpenseShowsEndYear(preset.category),
      endYearRequired: false,
      onChanged: (annual, {endYear, startYear}) => _onExpenseRowChanged(
        key: key,
        category: preset.category,
        presetKey: preset.key,
        annual: annual,
        endYear: endYear,
        existingId: row?.id,
      ),
      onDelete: hasRow ? () => _queueDeleteOrClear(key, row?.id) : null,
    );
  }

  Widget _buildCustomExpenseRow(FFExpense e) {
    final key = 'expense:id:${e.id}';
    final pending = _isPendingDelete(key);
    return _MonthlyAnnualRow(
      key: ValueKey('exp-custom-${e.id}-$pending'),
      title: ffExpenseCategoryLabels[e.category] ?? e.category,
      annualAmount: pending ? 0 : e.amount,
      endYear: pending ? null : e.endYear,
      showEndYear: ffExpenseShowsEndYear(e.category),
      endYearRequired: false,
      onChanged: (annual, {endYear, startYear}) => _onExpenseRowChanged(
        key: key,
        category: e.category,
        presetKey: e.presetKey,
        annual: annual,
        endYear: endYear,
        existingId: e.id,
      ),
      onDelete: () => _queueDeleteOrClear(key, e.id),
    );
  }

  void _onOneTimeChanged({
    required String key,
    required Map<String, dynamic> body,
    FFOneTimeExpense? existing,
  }) {
    final year = body['expected_year'];
    if (year == null) {
      _queueDeleteOrClear(key, existing?.id);
      return;
    }
    _queueUpsert(key, body, existingId: existing?.id);
  }

  Widget _buildOneTimePresetRow(
    FreedomProvider provider,
    FFOneTimePreset preset,
  ) {
    final key = 'onetime:preset:${preset.key}';
    final pending = _isPendingDelete(key);
    final existing = pending
        ? null
        : ffOneTimeForPreset(provider.oneTimeExpenses, preset.key);
    final hasRow =
        existing != null || _pendingUpserts.containsKey(key) || pending;
    return _OneTimeValueRow(
      key: ValueKey('ot-preset-${preset.key}-${existing?.id ?? 0}-$pending'),
      name: preset.name,
      presetKey: preset.key,
      existing: existing,
      onChanged: (body, {existing}) => _onOneTimeChanged(
        key: existing != null
            ? 'onetime:id:${existing.id}'
            : key,
        body: body,
        existing: existing,
      ),
      onDelete: hasRow ? () => _queueDeleteOrClear(key, existing?.id) : null,
    );
  }

  Widget _buildCustomOneTimeRow(FFOneTimeExpense o) {
    final key = 'onetime:id:${o.id}';
    final pending = _isPendingDelete(key);
    return _OneTimeValueRow(
      key: ValueKey('ot-custom-${o.id}-$pending'),
      name: o.name,
      existing: pending ? null : o,
      onChanged: (body, {existing}) => _onOneTimeChanged(
        key: key,
        body: body,
        existing: o,
      ),
      onDelete: () => _queueDeleteOrClear(key, o.id),
    );
  }

  Widget _buildIncomeAssetsSection(FreedomProvider provider) {
    return ffIncomeAssetsBanner(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupCard(
            title: 'Income from Salary/Profession',
            onAdd: () => _editJob(null),
            onSave: _saveAll,
            canSave: _dirty,
            saving: _savingAll,
            children: [
              for (final preset in ffJobPresets)
                _buildJobPresetRow(provider, preset),
              for (final j in ffCustomJobIncome(provider.jobIncome))
                _buildCustomJobRow(j),
              const Divider(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: freedomPensionAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: freedomPensionAccent.withValues(alpha: 0.28),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: _buildPensionRow(provider),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Assets',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Digital Gold, SGBs, ETFs + Index Funds, Direct Stocks — Domestic, '
                      'and Mutual Funds sync automatically from Stocks & Mutual Funds '
                      '(Current Amount → ₹ in K) and cannot be deleted.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _resetAssetIncomeDefaults,
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Reset default %'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...FFAssetCategory.order.map((cat) {
            return _AssetCategoryBlock(
              category: cat,
              assets: provider.assets,
              onChanged: (body, {existing}) => _queueUpsert(
                existing != null
                    ? 'asset:id:${existing.id}'
                    : 'asset:preset:${body['preset_key']}',
                body,
                existingId: existing?.id,
              ),
              onOpenDetails: (assetPreset, lines) async {
                final saved = await showAssetLinesDialog(
                  context: context,
                  preset: assetPreset,
                  lines: lines,
                );
                if (saved == true) await _reload();
              },
              onDelete: (a) => _confirmDelete(
                a.name,
                () => FreedomApi.deleteAsset(a.id),
                pendingKeys: [
                  'asset:id:${a.id}',
                  if (a.presetKey != null && a.presetKey!.isNotEmpty)
                    'asset:preset:${a.presetKey}',
                ],
              ),
              onAddCustom: () => _editAsset(
                null,
                defaultCategory: cat,
              ),
              onSave: _saveAll,
              canSave: _dirty,
              saving: _savingAll,
            );
          }),
          ...provider.assets
              .where((a) => !FFAssetCategory.order.contains(a.category))
              .map(
                (a) => _AssetTile(
                  asset: a,
                  onEdit: () => _editAsset(a),
                  onDelete: () => _confirmDelete(
                    a.name,
                    () => FreedomApi.deleteAsset(a.id),
                    pendingKeys: [
                      'asset:id:${a.id}',
                      if (a.presetKey != null && a.presetKey!.isNotEmpty)
                        'asset:preset:${a.presetKey}',
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildExpensesSection(FreedomProvider provider) {
    return ffExpensesBanner(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupCard(
            title: 'Expenses',
            onAdd: () => _editExpense(null),
            onSave: _saveAll,
            canSave: _dirty,
            saving: _savingAll,
            children: [
              for (final preset in ffExpensePresets)
                _buildExpensePresetRow(provider, preset),
              for (final e in ffCustomExpenses(provider.expenses))
                _buildCustomExpenseRow(e),
            ],
          ),
          _GroupCard(
            title: 'Major one-time expenses',
            subtitle:
                'Amounts are in today\'s value (₹ in K), used as entered in '
                'Ready to Retire.',
            onAdd: () => _editOneTime(null),
            onSave: _saveAll,
            canSave: _dirty,
            saving: _savingAll,
            children: [
              for (final preset in ffOneTimePresets)
                _buildOneTimePresetRow(provider, preset),
              for (final o
                  in ffCustomOneTimeExpenses(provider.oneTimeExpenses))
                _buildCustomOneTimeRow(o),
            ],
          ),
        ],
      ),
    );
  }


  Future<void> _resetAssetIncomeDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset default return %?'),
        content: const Text(
          'Restore the default return % for every preset asset type. '
          'Custom assets (added without a preset) are unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final updated = await FreedomApi.resetAssetIncomeDefaults();
      setState(() {
        _pendingUpserts.removeWhere((key, _) => key.startsWith('asset:'));
        _recomputeDirty();
      });
      await _reload();
      _snack(
        updated == 0
            ? 'Return % already at defaults'
            : 'Reset return % on $updated asset${updated == 1 ? '' : 's'}',
      );
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _saveAssetRow(Map<String, dynamic> body, {FFAsset? existing}) async {
    try {
      if (existing == null) {
        await FreedomApi.createAsset(body);
      } else {
        await FreedomApi.updateAsset(existing.id, body);
      }
      await _reload();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editAsset(
    FFAsset? existing, {
    String? defaultCategory,
    FFAssetPreset? preset,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AssetFormDialog(
        existing: existing,
        defaultCategory: defaultCategory,
        preset: preset,
      ),
    );
    if (result == null) return;
    await _saveAssetRow(result, existing: existing);
  }

  Future<void> _saveJobRow(
    Map<String, dynamic> body, {
    FFJobIncome? existing,
  }) async {
    try {
      if (existing == null) {
        await FreedomApi.createJobIncome(body);
      } else {
        await FreedomApi.updateJobIncome(existing.id, body);
      }
      await _reload();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editJob(FFJobIncome? existing, {FFJobPreset? preset}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _JobFormDialog(existing: existing, preset: preset),
    );
    if (result == null) return;
    await _saveJobRow(result, existing: existing);
  }

  Future<void> _saveExpenseRow(
    Map<String, dynamic> body, {
    FFExpense? existing,
  }) async {
    try {
      if (existing == null) {
        await FreedomApi.createExpense(body);
      } else {
        await FreedomApi.updateExpense(existing.id, body);
      }
      await _reload();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editExpense(
    FFExpense? existing, {
    FFExpensePreset? preset,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ExpenseFormDialog(existing: existing, preset: preset),
    );
    if (result == null) return;
    await _saveExpenseRow(result, existing: existing);
  }

  Future<void> _saveOneTimeRow(
    Map<String, dynamic> body, {
    FFOneTimeExpense? existing,
  }) async {
    try {
      if (existing == null) {
        await FreedomApi.createOneTime(body);
      } else {
        await FreedomApi.updateOneTime(existing.id, body);
      }
      await _reload();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editOneTime(
    FFOneTimeExpense? existing, {
    FFOneTimePreset? preset,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _OneTimeFormDialog(existing: existing, preset: preset),
    );
    if (result == null) return;
    await _saveOneTimeRow(result, existing: existing);
  }
}

/// Whole months, or "Y yr M mo" when longer than a year.
String _formatBreakMonths(double? months) {
  if (months == null) return '—';
  final total = months.floor();
  if (total <= 12) return '$total';
  final years = total ~/ 12;
  final rem = total % 12;
  if (rem == 0) return '$years yr';
  return '$years yr $rem mo';
}

String _formatBreakResult(double? months) {
  if (months == null) return '—';
  if (months.floor() <= 12) return '${months.floor()} months';
  return _formatBreakMonths(months);
}

bool _isBreakLiquidAsset(FFAsset a) {
  if (a.category == FFAssetCategory.liquidCash ||
      a.category == FFAssetCategory.marketEquity) {
    return true;
  }
  return a.presetKey == 'digital_gold' || a.presetKey == 'sgb';
}

bool _skipLiquidityExtraIncome(FFAsset a) {
  if (a.category == FFAssetCategory.pfBonds) return true;
  return a.presetKey == 'physical_gold';
}

bool _assetIncomeActive(FFAsset a, int year) {
  if (a.incomeStartYear > year) return false;
  if (a.incomeEndYear != null && year > a.incomeEndYear!) return false;
  return true;
}

class _MetricsRow extends StatelessWidget {
  final FFMetrics? metrics;

  const _MetricsRow({this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final retire = m?.retirementYear == null
        ? 'Not reachable (50y)'
        : m!.yearsToRetire == 0
            ? 'Now (${m.retirementYear})'
            : '${m.yearsToRetire} yr (${m.retirementYear})';
    final enjoy = formatInrK(m?.annualEnjoymentFund ?? 0);
    final term = formatInrK(m?.termInsuranceNeed ?? 0);
    final liveWellZero = m != null && (m.annualEnjoymentFund ?? 0) <= 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 720 ? 3 : 2;
        final cards = [
          _MetricCard(
            title: 'Active Income',
            value: formatInrK(m?.activeIncome ?? 0),
            subtitle: 'Salary / profession (through end year) + pension (from start year)',
          ),
          _MetricCard(
            title: 'Passive Income',
            value: formatInrK(m?.passiveIncome ?? 0),
            subtitle: 'Effective return from assets',
          ),
          _MetricCard(
            title: 'Regular Expenses',
            value: formatInrK(m?.regularExpenses ?? 0),
            subtitle: 'Recurring expenses (current year)',
          ),
          _MetricCard(
            title: 'Ready to Retire ( Years )',
            value: retire,
            subtitle:
                'Adj. passive + active ≥ recurring + EMI at horizon end (simulated)',
          ),
          liveWellZero
              ? _MetricCard(
                  title: 'Liquidity For Break',
                  titleSuffix:
                      (m?.liquidityForBreakMonths?.floor() ?? 0) > 12
                          ? null
                          : 'months',
                  value: _formatBreakMonths(m?.liquidityForBreakMonths),
                  subtitle:
                      'Liquid + market + digital gold + SGB last this many months if salary/profession income is zero',
                )
              : _MetricCard(
                  title: 'Live Well Fund',
                  titleSuffix: 'for the year',
                  value: enjoy,
                  subtitle: 'Half of Surplus -> Enjoy it with loved ones',
                ),
          _MetricCard(
            title: 'Term Insurance Needs',
            value: term,
            subtitle: '15/75 Rule — Cover = Debt + 15 yrs of 75% Expenses − Investments',
          ),
        ];
        final rows = (cards.length / cols).ceil();
        return Column(
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var col = 0; col < cols; col++) ...[
                      if (col > 0) const SizedBox(width: 12),
                      Expanded(
                        child: row * cols + col < cards.length
                            ? cards[row * cols + col]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String? titleSuffix;
  final String value;
  final String subtitle;

  const _MetricCard({
    required this.title,
    this.titleSuffix,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (titleSuffix != null)
                    Text(
                      titleSuffix!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: freedomSeed,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeaderActions extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onSave;
  final bool canSave;
  final bool saving;

  const _SectionHeaderActions({
    required this.onAdd,
    required this.onSave,
    required this.canSave,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          style: freedomOutlinedActionStyle(context),
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: (!canSave || saving) ? null : onSave,
          child: saving
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
}

class _GroupCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onAdd;
  final VoidCallback onSave;
  final bool canSave;
  final bool saving;
  final List<Widget> children;

  const _GroupCard({
    required this.title,
    this.subtitle,
    required this.onAdd,
    required this.onSave,
    required this.canSave,
    required this.saving,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                _SectionHeaderActions(
                  onAdd: onAdd,
                  onSave: onSave,
                  canSave: canSave,
                  saving: saving,
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _AssetCategoryBlock extends StatelessWidget {
  final String category;
  final List<FFAsset> assets;
  final void Function(Map<String, dynamic> body, {FFAsset? existing}) onChanged;
  final Future<void> Function(FFAssetPreset preset, List<FFAsset> lines)
      onOpenDetails;
  final void Function(FFAsset asset) onDelete;
  final VoidCallback onAddCustom;
  final VoidCallback onSave;
  final bool canSave;
  final bool saving;

  const _AssetCategoryBlock({
    required this.category,
    required this.assets,
    required this.onChanged,
    required this.onOpenDetails,
    required this.onDelete,
    required this.onAddCustom,
    required this.onSave,
    required this.canSave,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    final presets = ffPresetsForCategory(category);
    final customs = ffCustomAssetsForCategory(assets, category);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    FFAssetCategory.labels[category] ?? category,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                _SectionHeaderActions(
                  onAdd: onAddCustom,
                  onSave: onSave,
                  canSave: canSave,
                  saving: saving,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final preset in presets) ...[
              Builder(
                builder: (context) {
                  final lines = ffAssetsForPreset(assets, preset.key);
                  final summary = FFAssetPresetSummary.fromAssets(
                    lines,
                    defaultIncomePct: preset.incomePct,
                  );
                  return _AssetValueRow(
                    key: ValueKey(
                      'preset-${preset.key}-${lines.map((l) => l.id).join('-')}',
                    ),
                    name: preset.name,
                    incomePct: summary.count > 0
                        ? summary.incomePct
                        : preset.incomePct,
                    lines: lines,
                    summary: summary,
                    preset: preset,
                    category: category,
                    allowsEmi: preset.allowsEmi,
                    onChanged: onChanged,
                    onOpenDetails: () => onOpenDetails(preset, lines),
                    onDelete: (preset.fromPortfolio || lines.isEmpty)
                        ? null
                        : lines.length == 1
                            ? () => onDelete(lines.first)
                            : null,
                  );
                },
              ),
            ],
            for (final custom in customs) ...[
              Builder(
                builder: (context) {
                  final lines = [custom];
                  final summary = FFAssetPresetSummary.fromAssets(
                    lines,
                    defaultIncomePct: custom.incomePct,
                  );
                  return _AssetValueRow(
                    key: ValueKey('custom-${custom.id}'),
                    name: custom.name,
                    incomePct: custom.incomePct,
                    lines: lines,
                    summary: summary,
                    category: category,
                    allowsEmi: category == FFAssetCategory.realEstateGold,
                    onChanged: onChanged,
                    onDelete: () => onDelete(custom),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssetValueRow extends StatefulWidget {
  final String name;
  final double incomePct;
  final List<FFAsset> lines;
  final FFAssetPresetSummary summary;
  final FFAssetPreset? preset;
  final String category;
  final bool allowsEmi;
  final void Function(Map<String, dynamic> body, {FFAsset? existing}) onChanged;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onDelete;

  const _AssetValueRow({
    super.key,
    required this.name,
    required this.incomePct,
    required this.lines,
    required this.summary,
    this.preset,
    required this.category,
    this.allowsEmi = false,
    required this.onChanged,
    this.onOpenDetails,
    this.onDelete,
  });

  bool get fromPortfolio => preset?.fromPortfolio ?? false;

  @override
  State<_AssetValueRow> createState() => _AssetValueRowState();
}

class _AssetValueRowState extends State<_AssetValueRow> {
  late final TextEditingController _value;
  late final TextEditingController _incomePct;
  late final TextEditingController _emi;
  late final TextEditingController _emiLeft;

  bool get _aggregated => widget.summary.count > 1;
  FFAsset? get _singleLine =>
      widget.summary.count == 1 ? widget.lines.first : null;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _value.addListener(() => setState(() {}));
    _incomePct.addListener(() => setState(() {}));
  }

  void _initControllers() {
    final s = widget.summary;
    final e = _singleLine;
    _value = TextEditingController(
      text: s.count > 0 && s.totalValue != 0
          ? _trimNum(_aggregated ? s.totalValue : e!.value)
          : '',
    );
    _incomePct = TextEditingController(
      text: _trimNum(s.count > 0 ? s.incomePct : widget.incomePct),
    );
    _emi = TextEditingController(
      text: s.count > 0 && s.totalEmi != 0
          ? _trimNum(_aggregated ? s.totalEmi : e!.emiAmount)
          : '',
    );
    _emiLeft = TextEditingController(
      text: s.count > 0 && s.maxMonthsLeft != 0
          ? (_aggregated ? s.maxMonthsLeft : e!.emiInstallmentsLeft).toString()
          : '',
    );
  }

  @override
  void didUpdateWidget(covariant _AssetValueRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary.count != widget.summary.count ||
        oldWidget.summary.totalValue != widget.summary.totalValue ||
        oldWidget.summary.totalEmi != widget.summary.totalEmi ||
        oldWidget.summary.maxMonthsLeft != widget.summary.maxMonthsLeft) {
      _value.text = widget.summary.count > 0 && widget.summary.totalValue != 0
          ? _trimNum(
              _aggregated
                  ? widget.summary.totalValue
                  : _singleLine!.value,
            )
          : '';
      _incomePct.text = _trimNum(
        widget.summary.count > 0
            ? widget.summary.incomePct
            : widget.incomePct,
      );
      _emi.text = widget.summary.count > 0 && widget.summary.totalEmi != 0
          ? _trimNum(
              _aggregated
                  ? widget.summary.totalEmi
                  : _singleLine!.emiAmount,
            )
          : '';
      _emiLeft.text = widget.summary.count > 0 &&
              widget.summary.maxMonthsLeft != 0
          ? (_aggregated
                  ? widget.summary.maxMonthsLeft
                  : _singleLine!.emiInstallmentsLeft)
              .toString()
          : '';
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _incomePct.dispose();
    _emi.dispose();
    _emiLeft.dispose();
    super.dispose();
  }

  double get _valueNum => _parseDouble(_value.text);
  double get _pctNum => _parseDouble(_incomePct.text);
  double get _calcIncome => _aggregated
      ? widget.summary.totalCalculatedIncome
      : _valueNum * _pctNum / 100;

  void _notifyChanged() {
    if (_aggregated) return;
    final e = _singleLine;
    final y = e?.incomeStartYear ?? DateTime.now().year;
    final emiAmount = widget.allowsEmi ? _parseDouble(_emi.text) : 0.0;
    final emiLeft =
        widget.allowsEmi ? (_parseIntOpt(_emiLeft.text) ?? 0) : 0;
    final body = <String, dynamic>{
      'category': widget.category,
      'preset_key': widget.preset?.key ?? e?.presetKey,
      'name': widget.name,
      'value': _valueNum,
      'is_liquid': e?.isLiquid ?? widget.preset?.isLiquid ?? false,
      'linked_liability': e?.linkedLiability ?? 0,
      'emi_amount': emiAmount,
      'emi_installments_left': emiLeft,
      'income_pct': _pctNum,
      'income_start_year': y,
      'income_end_year': e?.incomeEndYear,
      'tax_pct': e?.taxPct ?? 0,
    };
    widget.onChanged(body, existing: e);
  }

  Widget _buildFieldRow({required bool narrow}) {
    final readOnly = _aggregated || widget.fromPortfolio;
    final incomeLabel = _value.text.trim().isEmpty
        ? (narrow ? 'Passive income —' : 'Income —')
        : (narrow
            ? 'Passive income ${formatInrK(_calcIncome)}'
            : formatInrK(_calcIncome));

    final title = Expanded(
      flex: FfCols.titleFlex,
      child: Text(
        widget.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
    );

    final pctField = SizedBox(
      width: FfCols.pct,
      child: TextField(
        controller: _incomePct,
        readOnly: _aggregated,
        style: freedomInputValueStyle(context, readOnly: _aggregated),
        decoration: freedomFieldDecoration(context, labelText: '%'),
        keyboardType: TextInputType.number,
        inputFormatters: _numFormatters,
        onChanged: (_) => _notifyChanged(),
      ),
    );

    final valueField = SizedBox(
      width: FfCols.value,
      child: TextField(
        controller: _value,
        readOnly: readOnly,
        style: freedomInputValueStyle(context, readOnly: readOnly),
        decoration: freedomFieldDecoration(
          context,
          labelText: widget.fromPortfolio
              ? 'Value ₹ (in K, synced)'
              : 'Value ₹ (in K)',
        ),
        keyboardType: TextInputType.number,
        inputFormatters: _numFormatters,
        onChanged: (_) => _notifyChanged(),
      ),
    );

    final emiField = widget.allowsEmi
        ? SizedBox(
            width: FfCols.emi,
            child: TextField(
              controller: _emi,
              readOnly: readOnly,
              style: freedomInputValueStyle(context, readOnly: readOnly),
              decoration: freedomFieldDecoration(
                context,
                labelText: 'EMI ₹ (in K)',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: _numFormatters,
              onChanged: (_) => _notifyChanged(),
            ),
          )
        : null;

    final monthsField = widget.allowsEmi
        ? SizedBox(
            width: FfCols.months,
            child: TextField(
              controller: _emiLeft,
              readOnly: readOnly,
              style: freedomInputValueStyle(context, readOnly: readOnly),
              decoration: freedomFieldDecoration(
                context,
                labelText: 'Mo. left',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: ffMonthsFormatters,
              onChanged: (_) => _notifyChanged(),
            ),
          )
        : null;

    final incomeDisplay = SizedBox(
      width: FfCols.income,
      child: Text(
        incomeLabel,
        style: TextStyle(
          color: freedomSeed,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    // Always reserve both slots so % / Value columns stay aligned across rows.
    final actionBar = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ffActionSlot(
          icon: Icons.list_alt_outlined,
          tooltip: 'Details',
          onPressed: widget.onOpenDetails,
        ),
        ffActionSlot(
          icon: Icons.delete_outline,
          tooltip: 'Delete',
          onPressed: widget.onDelete,
        ),
      ],
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(
            children: [
              pctField,
              const SizedBox(width: 8),
              Expanded(child: valueField),
              actionBar,
            ],
          ),
          if (widget.allowsEmi) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: emiField!),
                const SizedBox(width: 8),
                monthsField!,
                SizedBox(width: FfCols.actionSlot * 2),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: incomeDisplay),
              SizedBox(width: FfCols.actionSlot * 2),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        title,
        pctField,
        const SizedBox(width: 8),
        valueField,
        if (emiField != null) ...[
          const SizedBox(width: 8),
          emiField,
        ],
        if (monthsField != null) ...[
          const SizedBox(width: 8),
          monthsField,
        ],
        const SizedBox(width: 8),
        incomeDisplay,
        actionBar,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;
          return _buildFieldRow(narrow: narrow);
        },
      ),
    );
  }
}

String _trimNum(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

class _AssetTile extends StatelessWidget {
  final FFAsset asset;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AssetTile({
    required this.asset,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(asset.name),
        subtitle: Text(
          '${formatInrK(asset.value)} · ${asset.incomePct}% → ${formatInrK(asset.calculatedIncome)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

List<TextInputFormatter> get _numFormatters => [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
    ];

double _parseDouble(String s) => double.tryParse(s.trim()) ?? 0;
int? _parseIntOpt(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  return int.tryParse(t);
}

class _AssetFormDialog extends StatefulWidget {
  final FFAsset? existing;
  final String? defaultCategory;
  final FFAssetPreset? preset;

  const _AssetFormDialog({
    this.existing,
    this.defaultCategory,
    this.preset,
  });

  @override
  State<_AssetFormDialog> createState() => _AssetFormDialogState();
}

class _AssetFormDialogState extends State<_AssetFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _value;
  late final TextEditingController _incomePct;
  late final String _category;
  late final bool _isLiquid;
  late final double _linkedLiability;
  late final double _emiAmount;
  late final int _emiInstallmentsLeft;
  late final int _incomeStartYear;
  late final int? _incomeEndYear;
  late final double _taxPct;
  String? _presetKey;

  String get _categoryLabel =>
      FFAssetCategory.labels[_category] ?? _category;

  double get _calcIncome =>
      _parseDouble(_value.text) * _parseDouble(_incomePct.text) / 100;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final p = widget.preset;
    final y = DateTime.now().year;
    _category = e?.category ??
        widget.defaultCategory ??
        p?.category ??
        FFAssetCategory.liquidCash;
    _presetKey = e?.presetKey ?? p?.key;
    _name = TextEditingController(text: e?.name ?? p?.name ?? '');
    _value = TextEditingController(
      text: e != null && e.value != 0 ? _trimNum(e.value) : '',
    );
    _incomePct = TextEditingController(
      text: _trimNum(e?.incomePct ?? p?.incomePct ?? 0),
    );
    _isLiquid = e?.isLiquid ??
        p?.isLiquid ??
        (_category == FFAssetCategory.liquidCash);
    _linkedLiability = e?.linkedLiability ?? 0;
    _emiAmount = e?.emiAmount ?? 0;
    _emiInstallmentsLeft = e?.emiInstallmentsLeft ?? 0;
    _incomeStartYear = e?.incomeStartYear ?? y;
    _incomeEndYear = e?.incomeEndYear;
    _taxPct = e?.taxPct ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _incomePct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdd = widget.existing == null;
    return AlertDialog(
      title: Text(isAdd ? 'Add — $_categoryLabel' : 'Edit asset'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  _categoryLabel,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                autofocus: isAdd,
                readOnly: widget.preset != null,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: _incomePct,
                decoration: const InputDecoration(labelText: 'Return %'),
                keyboardType: TextInputType.number,
                inputFormatters: _numFormatters,
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _value,
                decoration: const InputDecoration(labelText: 'Value ₹ (in K)'),
                keyboardType: TextInputType.number,
                inputFormatters: _numFormatters,
                onChanged: (_) => setState(() {}),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Passive income: ${formatInrK(_calcIncome)}',
                  style: TextStyle(
                    color: freedomSeed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, {
              'category': _category,
              'preset_key': _presetKey,
              'name': name,
              'value': _parseDouble(_value.text),
              'is_liquid': _isLiquid,
              'linked_liability': _linkedLiability,
              'emi_amount': _emiAmount,
              'emi_installments_left': _emiInstallmentsLeft,
              'income_pct': _parseDouble(_incomePct.text),
              'income_start_year': _incomeStartYear,
              'income_end_year': _incomeEndYear,
              'tax_pct': _taxPct,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _MonthlyAnnualRow extends StatefulWidget {
  final String title;
  final double annualAmount;
  final int? endYear;
  final int? startYear;
  final bool showEndYear;
  final bool showStartYear;
  final bool endYearRequired;
  final Color? titleColor;
  final void Function(double annual, {int? endYear, int? startYear}) onChanged;
  final VoidCallback? onDelete;

  const _MonthlyAnnualRow({
    super.key,
    required this.title,
    required this.annualAmount,
    this.endYear,
    this.startYear,
    this.showEndYear = false,
    this.showStartYear = false,
    this.endYearRequired = false,
    this.titleColor,
    required this.onChanged,
    this.onDelete,
  });

  @override
  State<_MonthlyAnnualRow> createState() => _MonthlyAnnualRowState();
}

class _MonthlyAnnualRowState extends State<_MonthlyAnnualRow> {
  late final TextEditingController _monthly;
  late final TextEditingController _annual;
  late final TextEditingController _endYear;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final annual = widget.annualAmount;
    _annual = TextEditingController(
      text: annual != 0 ? _trimNum(annual) : '',
    );
    _monthly = TextEditingController(
      text: annual != 0 ? _trimNum(annual / 12) : '',
    );
    _endYear = TextEditingController(
      text: widget.showStartYear
          ? (widget.startYear?.toString() ?? '')
          : (widget.endYear?.toString() ?? ''),
    );
  }

  @override
  void dispose() {
    _monthly.dispose();
    _annual.dispose();
    _endYear.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    if (widget.showStartYear) {
      final start = _parseIntOpt(_endYear.text);
      widget.onChanged(
        _parseDouble(_annual.text),
        startYear: start,
      );
      return;
    }
    final end = _parseIntOpt(_endYear.text);
    widget.onChanged(
      _parseDouble(_annual.text),
      endYear: end,
    );
  }

  void _fromMonthly(String raw) {
    if (_syncing) return;
    _syncing = true;
    final m = _parseDouble(raw);
    _annual.text = raw.trim().isEmpty ? '' : _trimNum(m * 12);
    _syncing = false;
    _notifyChanged();
  }

  void _fromAnnual(String raw) {
    if (_syncing) return;
    _syncing = true;
    final a = _parseDouble(raw);
    _monthly.text = raw.trim().isEmpty ? '' : _trimNum(a / 12);
    _syncing = false;
    _notifyChanged();
  }

  @override
  void didUpdateWidget(covariant _MonthlyAnnualRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.annualAmount != widget.annualAmount ||
        oldWidget.endYear != widget.endYear ||
        oldWidget.startYear != widget.startYear) {
      final annual = widget.annualAmount;
      _annual.text = annual != 0 ? _trimNum(annual) : '';
      _monthly.text = annual != 0 ? _trimNum(annual / 12) : '';
      _endYear.text = widget.showStartYear
          ? (widget.startYear?.toString() ?? '')
          : (widget.endYear?.toString() ?? '');
    }
  }

  Widget _buildFieldRow({required bool narrow}) {
    final title = Expanded(
      flex: FfCols.titleFlex,
      child: Text(
        widget.title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: widget.titleColor,
        ),
      ),
    );

    final monthlyField = SizedBox(
      width: FfCols.monthly,
      child: TextField(
        controller: _monthly,
        decoration: freedomFieldDecoration(
          context,
          labelText: 'Monthly ₹ (in K)',
        ),
        keyboardType: TextInputType.number,
        inputFormatters: _numFormatters,
        onChanged: _fromMonthly,
      ),
    );

    final annualField = SizedBox(
      width: FfCols.annual,
      child: TextField(
        controller: _annual,
        decoration: freedomFieldDecoration(
          context,
          labelText: 'Annual ₹ (in K)',
        ),
        keyboardType: TextInputType.number,
        inputFormatters: _numFormatters,
        onChanged: _fromAnnual,
      ),
    );

    final endYearField = widget.showEndYear || widget.showStartYear
        ? SizedBox(
            width: FfCols.year,
            child: TextField(
              controller: _endYear,
              decoration: freedomFieldDecoration(
                context,
                labelText: widget.showStartYear
                    ? 'Start year'
                    : widget.endYearRequired
                        ? 'End year*'
                        : 'End year',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: ffYearFormatters,
              onChanged: (_) => _notifyChanged(),
            ),
          )
        : null;

    final deleteSlot = ffActionSlot(
      icon: Icons.delete_outline,
      tooltip: 'Delete',
      onPressed: widget.onDelete,
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: widget.titleColor,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: monthlyField),
              const SizedBox(width: 8),
              Expanded(child: annualField),
              deleteSlot,
            ],
          ),
          if (endYearField != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                endYearField,
                const Spacer(),
                SizedBox(width: FfCols.actionSlot),
              ],
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        title,
        monthlyField,
        const SizedBox(width: 8),
        annualField,
        if (endYearField != null) ...[
          const SizedBox(width: 8),
          endYearField,
        ] else ...[
          // Keep Annual aligned with rows that show End year.
          const SizedBox(width: 8),
          SizedBox(width: FfCols.year),
        ],
        deleteSlot,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;
          return _buildFieldRow(narrow: narrow);
        },
      ),
    );
  }
}

class _JobFormDialog extends StatefulWidget {
  final FFJobIncome? existing;
  final FFJobPreset? preset;

  const _JobFormDialog({this.existing, this.preset});

  @override
  State<_JobFormDialog> createState() => _JobFormDialogState();
}

class _JobFormDialogState extends State<_JobFormDialog> {
  late final TextEditingController _label;
  late final TextEditingController _monthly;
  late final TextEditingController _annual;
  late final TextEditingController _endYear;
  String? _presetKey;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final p = widget.preset;
    _presetKey = e?.presetKey ?? p?.key;
    _label = TextEditingController(text: e?.label ?? p?.label ?? 'Salary');
    final annual = e?.amount ?? 0;
    _annual = TextEditingController(text: annual != 0 ? _trimNum(annual) : '');
    _monthly = TextEditingController(
      text: annual != 0 ? _trimNum(annual / 12) : '',
    );
    _endYear = TextEditingController(
      text: ffJobDisplayEndYear(e)?.toString() ??
          (e == null ? (DateTime.now().year + 10).toString() : ''),
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _monthly.dispose();
    _annual.dispose();
    _endYear.dispose();
    super.dispose();
  }

  void _fromMonthly(String raw) {
    if (_syncing) return;
    _syncing = true;
    final m = _parseDouble(raw);
    _annual.text = raw.trim().isEmpty ? '' : _trimNum(m * 12);
    _syncing = false;
    setState(() {});
  }

  void _fromAnnual(String raw) {
    if (_syncing) return;
    _syncing = true;
    final a = _parseDouble(raw);
    _monthly.text = raw.trim().isEmpty ? '' : _trimNum(a / 12);
    _syncing = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.preset != null ||
        (widget.existing?.presetKey != null &&
            widget.existing!.presetKey!.isNotEmpty);
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Add salary/profession income'
          : 'Edit salary/profession income'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              readOnly: locked,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            TextField(
              controller: _monthly,
              decoration: const InputDecoration(
                labelText: 'Monthly amount ₹ (in K)',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: _numFormatters,
              onChanged: _fromMonthly,
            ),
            TextField(
              controller: _annual,
              decoration: const InputDecoration(
                labelText: 'Annual amount ₹ (in K)',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: _numFormatters,
              onChanged: _fromAnnual,
            ),
            TextField(
              controller: _endYear,
              decoration: const InputDecoration(labelText: 'Expected end year'),
              keyboardType: TextInputType.number,
              inputFormatters: ffYearFormatters,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final end = _parseIntOpt(_endYear.text);
            Navigator.pop(context, {
              'preset_key': _presetKey,
              'label': _label.text.trim().isEmpty ? 'Salary' : _label.text.trim(),
              'amount': _parseDouble(_annual.text),
              'end_year': end,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ExpenseFormDialog extends StatefulWidget {
  final FFExpense? existing;
  final FFExpensePreset? preset;

  const _ExpenseFormDialog({this.existing, this.preset});

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  late String _category;
  String? _presetKey;
  late final TextEditingController _categoryLabel;
  late final TextEditingController _monthly;
  late final TextEditingController _annual;
  late final TextEditingController _endYear;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final p = widget.preset;
    _category = e?.category ?? p?.category ?? '';
    _presetKey = e?.presetKey ?? p?.key;
    _categoryLabel = TextEditingController(
      text: e != null
          ? (ffExpenseCategoryLabels[e.category] ?? e.category)
          : (p != null ? p.label : ''),
    );
    final annual = e?.amount ?? 0;
    _annual = TextEditingController(text: annual != 0 ? _trimNum(annual) : '');
    _monthly = TextEditingController(
      text: annual != 0 ? _trimNum(annual / 12) : '',
    );
    _endYear = TextEditingController(text: e?.endYear?.toString() ?? '');
  }

  @override
  void dispose() {
    _categoryLabel.dispose();
    _monthly.dispose();
    _annual.dispose();
    _endYear.dispose();
    super.dispose();
  }

  void _fromMonthly(String raw) {
    if (_syncing) return;
    _syncing = true;
    final m = _parseDouble(raw);
    _annual.text = raw.trim().isEmpty ? '' : _trimNum(m * 12);
    _syncing = false;
    setState(() {});
  }

  void _fromAnnual(String raw) {
    if (_syncing) return;
    _syncing = true;
    final a = _parseDouble(raw);
    _monthly.text = raw.trim().isEmpty ? '' : _trimNum(a / 12);
    _syncing = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lockedCat = widget.preset != null ||
        (widget.existing?.presetKey != null &&
            widget.existing!.presetKey!.isNotEmpty);
    final customCategory = !lockedCat;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add expense' : 'Edit expense'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (customCategory)
              TextField(
                controller: _categoryLabel,
                decoration: const InputDecoration(labelText: 'Category'),
                textCapitalization: TextCapitalization.sentences,
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                isExpanded: true,
                items: ffExpenseCategoryLabels.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: null,
              ),
            TextField(
              controller: _monthly,
              decoration: const InputDecoration(
                labelText: 'Monthly amount ₹ (in K)',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: _numFormatters,
              onChanged: _fromMonthly,
            ),
            TextField(
              controller: _annual,
              decoration: const InputDecoration(
                labelText: 'Annual amount ₹ (in K)',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: _numFormatters,
              onChanged: _fromAnnual,
            ),
            TextField(
              controller: _endYear,
              decoration: const InputDecoration(
                labelText: 'End year (optional)',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: ffYearFormatters,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final end = _parseIntOpt(_endYear.text);
            final category = customCategory
                ? _categoryLabel.text.trim()
                : _category;
            if (category.isEmpty) return;
            Navigator.pop(context, {
              'preset_key': _presetKey,
              'category': category,
              'amount': _parseDouble(_annual.text),
              'end_year': end,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _OneTimeValueRow extends StatefulWidget {
  final String name;
  final String? presetKey;
  final FFOneTimeExpense? existing;
  final void Function(Map<String, dynamic> body, {FFOneTimeExpense? existing})
      onChanged;
  final VoidCallback? onDelete;

  const _OneTimeValueRow({
    super.key,
    required this.name,
    this.presetKey,
    required this.existing,
    required this.onChanged,
    this.onDelete,
  });

  @override
  State<_OneTimeValueRow> createState() => _OneTimeValueRowState();
}

class _OneTimeValueRowState extends State<_OneTimeValueRow> {
  late final TextEditingController _amount;
  late final TextEditingController _year;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(
      text: e != null && e.amount != 0 ? _trimNum(e.amount) : '',
    );
    _year = TextEditingController(
      text: e != null
          ? e.expectedYear.toString()
          : (DateTime.now().year + 1).toString(),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _year.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    final year = _parseIntOpt(_year.text);
    widget.onChanged(
      {
        'preset_key': widget.presetKey ?? widget.existing?.presetKey,
        'name': widget.name,
        'amount': _parseDouble(_amount.text),
        'expected_year': year,
      },
      existing: widget.existing,
    );
  }

  @override
  void didUpdateWidget(covariant _OneTimeValueRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final e = widget.existing;
    if (oldWidget.existing?.id != e?.id ||
        oldWidget.existing?.amount != e?.amount ||
        oldWidget.existing?.expectedYear != e?.expectedYear) {
      _amount.text = e != null && e.amount != 0 ? _trimNum(e.amount) : '';
      _year.text = e != null ? e.expectedYear.toString() : '';
    }
  }

  Widget _buildFieldRow({required bool narrow}) {
    final title = Expanded(
      flex: FfCols.titleFlex,
      child: Text(
        widget.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
    );

    final amountField = SizedBox(
      width: FfCols.value,
      child: TextField(
        controller: _amount,
        decoration: freedomFieldDecoration(
          context,
          labelText: 'Amount ₹ (in K)',
        ),
        keyboardType: TextInputType.number,
        inputFormatters: _numFormatters,
        onChanged: (_) => _notifyChanged(),
      ),
    );

    final yearField = SizedBox(
      width: FfCols.year,
      child: TextField(
        controller: _year,
        decoration: freedomFieldDecoration(
          context,
          labelText: 'Year',
        ),
        keyboardType: TextInputType.number,
        inputFormatters: ffYearFormatters,
        onChanged: (_) => _notifyChanged(),
      ),
    );

    final deleteSlot = ffActionSlot(
      icon: Icons.delete_outline,
      tooltip: 'Delete',
      onPressed: widget.onDelete,
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: amountField),
              const SizedBox(width: 8),
              yearField,
              deleteSlot,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        title,
        amountField,
        const SizedBox(width: 8),
        yearField,
        deleteSlot,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;
          return _buildFieldRow(narrow: narrow);
        },
      ),
    );
  }
}

class _OneTimeFormDialog extends StatefulWidget {
  final FFOneTimeExpense? existing;
  final FFOneTimePreset? preset;

  const _OneTimeFormDialog({this.existing, this.preset});

  @override
  State<_OneTimeFormDialog> createState() => _OneTimeFormDialogState();
}

class _OneTimeFormDialogState extends State<_OneTimeFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _year;
  String? _presetKey;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final p = widget.preset;
    _presetKey = e?.presetKey ?? p?.key;
    _name = TextEditingController(text: e?.name ?? p?.name ?? '');
    _amount = TextEditingController(
      text: e != null && e.amount != 0 ? _trimNum(e.amount) : '',
    );
    _year = TextEditingController(
      text: e != null
          ? e.expectedYear.toString()
          : (DateTime.now().year + 1).toString(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lockedName = widget.preset != null ||
        (widget.existing?.presetKey != null &&
            widget.existing!.presetKey!.isNotEmpty);
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Add one-time expense' : 'Edit one-time expense',
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              readOnly: lockedName,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _amount,
              decoration: const InputDecoration(
                labelText: 'Amount ₹ (in K)',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: _numFormatters,
            ),
            TextField(
              controller: _year,
              decoration: const InputDecoration(labelText: 'Expected year'),
              keyboardType: TextInputType.number,
              inputFormatters: ffYearFormatters,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final year = _parseIntOpt(_year.text);
            if (name.isEmpty || year == null) return;
            Navigator.pop(context, {
              'preset_key': _presetKey,
              'name': name,
              'amount': _parseDouble(_amount.text),
              'expected_year': year,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _RetireSimulationTable extends StatelessWidget {
  final List<FFRetireSimRow> rows;

  const _RetireSimulationTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ready to Retire — year-by-year simulation',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'End-of-year values (₹ in K) after surplus reinvestment and one-time '
              'drawdowns. Passive income is inflation-adjusted (return% − 6%) except '
              'Real Estate & Gold. Inc ≥ Exp compares income to recurring expenses '
              'plus asset EMI (one-time excluded from the flag; still in Total Exp).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text(
                'No simulation rows yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        headingRowHeight: 40,
                        dataRowMinHeight: 36,
                        dataRowMaxHeight: 44,
                        columnSpacing: 20,
                        columns: const [
                          DataColumn(label: Text('Year')),
                          DataColumn(label: Text('Corpus')),
                          DataColumn(label: Text('Adj. Passive')),
                          DataColumn(label: Text('P/Corpus %')),
                          DataColumn(label: Text('Active')),
                          DataColumn(label: Text('Total Exp')),
                          DataColumn(label: Text('One-time')),
                          DataColumn(label: Text('Inc vs Exp')),
                          DataColumn(label: Text('Inc ≥ Exp')),
                          DataColumn(label: Text('Ready')),
                        ],
                        rows: rows.map((r) {
                          final meets = r.incomeMeetsExpense;
                          final ready = r.ready;
                          final pct = r.corpus > 0
                              ? r.passivePct.toStringAsFixed(1)
                              : '0.0';
                          final incVsExp =
                              '${formatInrK(r.endIncome)} ${meets ? '≥' : '<'} ${formatInrK(r.flagExpenses)}';
                          Color? rowColor;
                          if (ready) {
                            rowColor = freedomSeed.withValues(alpha: 0.12);
                          }
                          return DataRow(
                            color: rowColor != null
                                ? WidgetStateProperty.all(rowColor)
                                : null,
                            cells: [
                              DataCell(Text('${r.year}')),
                              DataCell(Text(formatInrK(r.corpus))),
                              DataCell(Text(formatInrK(r.passiveIncome))),
                              DataCell(Text('$pct%')),
                              DataCell(Text(formatInrK(r.activeIncome))),
                              DataCell(Text(formatInrK(r.totalExpenses))),
                              DataCell(Text(
                                r.oneTimeExpense > 0
                                    ? formatInrK(r.oneTimeExpense)
                                    : '—',
                              )),
                              DataCell(Text(incVsExp)),
                              DataCell(Text(
                                meets ? 'Yes' : 'No',
                                style: TextStyle(
                                  color: meets
                                      ? freedomSeed
                                      : theme.colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              )),
                              DataCell(Text(
                                ready ? 'Yes' : '—',
                                style: TextStyle(
                                  color: ready ? freedomSeed : null,
                                  fontWeight:
                                      ready ? FontWeight.bold : FontWeight.normal,
                                ),
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveWellCalculationCard extends StatelessWidget {
  final FFLiveWellDetail? detail;
  final FFMetrics? metrics;
  final List<FFAsset> assets;

  const _LiveWellCalculationCard({
    required this.detail,
    this.metrics,
    this.assets = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (metrics == null && detail == null) {
      return const SizedBox.shrink();
    }
    final fund = metrics?.annualEnjoymentFund ?? detail?.amount ?? 0;
    if (fund <= 0) {
      return _buildLiquidityCard(context);
    }
    return _buildLiveWellCard(context);
  }

  Widget _buildLiquidityCard(BuildContext context) {
    final theme = Theme.of(context);
    final year = metrics?.currentYear ?? DateTime.now().year;
    var liquidCash = 0.0;
    var marketEquity = 0.0;
    var digitalGold = 0.0;
    var sgb = 0.0;
    var extraIncome = 0.0;
    for (final a in assets) {
      if (_isBreakLiquidAsset(a)) {
        if (a.presetKey == 'digital_gold') {
          digitalGold += a.value;
        } else if (a.presetKey == 'sgb') {
          sgb += a.value;
        } else if (a.category == FFAssetCategory.liquidCash) {
          liquidCash += a.value;
        } else if (a.category == FFAssetCategory.marketEquity) {
          marketEquity += a.value;
        }
      } else if (!_skipLiquidityExtraIncome(a) && _assetIncomeActive(a, year)) {
        extraIncome += a.effectiveIncome;
      }
    }
    final combined = liquidCash + marketEquity + digitalGold + sgb;
    final annual = metrics?.regularExpenses ?? 0;
    final netAnnual = annual - extraIncome;
    final monthly = netAnnual / 12;
    final months = metrics?.liquidityForBreakMonths;

    String summary;
    if (annual <= 0) {
      summary =
          'Regular expenses are ₹0, so months of cover cannot be calculated.';
    } else if (netAnnual <= 0) {
      summary =
          'Other investment income covers regular expenses, so months of cover cannot be calculated.';
    } else {
      summary =
          'Combined ${formatInrK(combined)} ÷ monthly ${formatInrK(monthly)} = ${_formatBreakResult(months)}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  'Liquidity For Break',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'months',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '— calculation',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              detail?.message?.isNotEmpty == true
                  ? '${detail!.message!} This card shows how long liquid + market + digital gold + SGB last if salary/profession income is zero.'
                  : 'Live Well Fund is ₹0, so this shows how long liquid + market + digital gold + SGB last if salary/profession income is zero.',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: freedomSeed,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Liquid assets = Liquid & Cash + Market & Equity + Digital Gold + SGB. '
              'Months = liquid assets ÷ ((regular expenses − extra income) ÷ 12). '
              'Extra income is rental and similar returns — not PF/bonds or physical gold.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowHeight: 40,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 44,
                      columnSpacing: 20,
                      columns: const [
                        DataColumn(label: Text('Item')),
                        DataColumn(label: Text('Amount')),
                      ],
                      rows: [
                        DataRow(cells: [
                          const DataCell(Text('Liquid & Cash Assets')),
                          DataCell(Text(formatInrK(liquidCash))),
                        ]),
                        DataRow(cells: [
                          const DataCell(Text('Market & Equity Investments')),
                          DataCell(Text(formatInrK(marketEquity))),
                        ]),
                        DataRow(cells: [
                          const DataCell(Text('Digital Gold')),
                          DataCell(Text(formatInrK(digitalGold))),
                        ]),
                        DataRow(cells: [
                          const DataCell(Text('Sovereign Gold Bonds')),
                          DataCell(Text(formatInrK(sgb))),
                        ]),
                        DataRow(cells: [
                          const DataCell(Text('Combined liquid assets')),
                          DataCell(Text(formatInrK(combined))),
                        ]),
                        DataRow(cells: [
                          const DataCell(Text('Regular expenses (annual)')),
                          DataCell(Text(formatInrK(annual))),
                        ]),
                        DataRow(cells: [
                          const DataCell(Text('Extra income (other investments)')),
                          DataCell(Text(formatInrK(extraIncome))),
                        ]),
                        DataRow(cells: [
                          const DataCell(Text('Net expenses (annual)')),
                          DataCell(Text(
                            netAnnual <= 0 ? '—' : formatInrK(netAnnual),
                          )),
                        ]),
                        DataRow(cells: [
                          const DataCell(Text('Monthly net expenses')),
                          DataCell(Text(
                            netAnnual <= 0 ? '—' : formatInrK(monthly),
                          )),
                        ]),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Result: ${_formatBreakResult(months)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: freedomSeed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveWellCard(BuildContext context) {
    final theme = Theme.of(context);
    final d = detail;
    if (d == null) {
      return const SizedBox.shrink();
    }

    String summary;
    if (d.amount > 0 && d.todaySurplus > 0) {
      final discountNote = d.discountYears > 0
          ? ' → today ${formatInrK(d.todaySurplus)}'
          : '';
      summary =
          'Surplus ${formatInrK(d.totalSavings)} (year ${d.targetYear})$discountNote '
          '÷ 2 = ${formatInrK(d.amount)}';
    } else {
      summary = d.message?.isNotEmpty == true
          ? d.message!
          : 'Live Well Fund is ₹0.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  'Live Well Fund',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'for the year',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '— calculation',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
              Text(
                'Scenario: ${d.scenarioLabel}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: freedomSeed,
                ),
              ),
              if (d.lastOneTimeYear > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Last one-time expense: ${d.lastOneTimeYear}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Target year: ${d.targetYear} — surplus = end income − total expenses. '
                'Discount to today using P/Corpus % from the retire simulation'
                '${d.discountYears > 0 ? ' (${d.discountYears} yr)' : ''}, '
                'then divide by 2.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (d.yearRows.isEmpty)
                Text(
                  d.message ?? 'No year rows to display.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minWidth: constraints.maxWidth),
                        child: DataTable(
                          headingRowHeight: 40,
                          dataRowMinHeight: 36,
                          dataRowMaxHeight: 44,
                          columnSpacing: 20,
                          columns: const [
                            DataColumn(label: Text('Year')),
                            DataColumn(label: Text('End income')),
                            DataColumn(label: Text('Total exp')),
                            DataColumn(label: Text('Surplus')),
                            DataColumn(label: Text('P/Corpus %')),
                            DataColumn(label: Text('Today surplus')),
                          ],
                          rows: d.yearRows.map((r) {
                            return DataRow(
                              cells: [
                                DataCell(Text('${r.year}')),
                                DataCell(Text(formatInrK(r.endIncome))),
                                DataCell(Text(formatInrK(r.totalExpenses))),
                                DataCell(Text(formatInrK(r.savings))),
                                DataCell(Text('${r.passivePct.toStringAsFixed(1)}%')),
                                DataCell(Text(formatInrK(r.todaySavings))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              Text(
                summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Result: ${formatInrK(d.amount)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: freedomSeed,
                ),
              ),
            ],
          ),
        ),
    );
  }
}
