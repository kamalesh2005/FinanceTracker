import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/stock.dart';
import '../../services/api_service.dart';
import '../../utils/currency_format.dart';
import '../learner_api.dart';
import '../learner_provider.dart';
import '../learner_theme.dart';

class LearnerTradeScreen extends StatefulWidget {
  final int challengeId;
  final String? initialSymbol;
  final String initialSide;

  const LearnerTradeScreen({
    super.key,
    required this.challengeId,
    this.initialSymbol,
    this.initialSide = 'buy',
  });

  @override
  State<LearnerTradeScreen> createState() => _LearnerTradeScreenState();
}

class _LearnerTradeScreenState extends State<LearnerTradeScreen> {
  late String _side;
  final _symbol = TextEditingController();
  final _qty = TextEditingController();
  List<({String symbol, String name, double currentPrice})> _suggestions = [];
  double? _ltp;
  String _name = '';
  bool _busy = false;
  String? _error;

  static const fee = 20.0;

  @override
  void initState() {
    super.initState();
    _side = widget.initialSide;
    if (widget.initialSymbol != null) {
      _symbol.text = widget.initialSymbol!;
      _lookupSymbol(widget.initialSymbol!);
    }
  }

  @override
  void dispose() {
    _symbol.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    try {
      final rows = await ApiService.searchGlobalStocks(q);
      if (!mounted) return;
      setState(() => _suggestions = rows);
    } catch (_) {}
  }

  Future<void> _lookupSymbol(String symbol) async {
    try {
      final row = await ApiService.lookupGlobalStock(symbol);
      if (row == null) {
        setState(() => _error = 'Symbol not in catalog');
        return;
      }
      setState(() {
        _ltp = row.currentPrice;
        _name = row.name;
        _symbol.text = row.symbol;
        _suggestions = [];
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  double get _qtyVal => double.tryParse(_qty.text.trim()) ?? 0;

  double? get _gross {
    if (_ltp == null || _qtyVal <= 0) return null;
    return _qtyVal * _ltp!;
  }

  double? get _net {
    final g = _gross;
    if (g == null) return null;
    return _side == 'buy' ? g + fee : g - fee;
  }

  Future<void> _submit() async {
    final symbol = _symbol.text.trim().toUpperCase();
    if (symbol.isEmpty || _qtyVal <= 0) {
      setState(() => _error = 'Symbol and quantity are required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_side == 'buy') {
        await LearnerApi.buy(widget.challengeId, symbol: symbol, quantity: _qtyVal);
      } else {
        await LearnerApi.sell(widget.challengeId, symbol: symbol, quantity: _qtyVal);
      }
      if (!mounted) return;
      await context.read<LearnerProvider>().openChallenge(widget.challengeId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  Stock? get _holding {
    final sym = _symbol.text.trim().toUpperCase();
    for (final h in context.read<LearnerProvider>().holdings) {
      if (h.symbol.toUpperCase() == sym) return h;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final challengeName =
        context.watch<LearnerProvider>().detail?.name ?? 'Challenge';
    final cash = context.watch<LearnerProvider>().detail?.myCash ??
        context.watch<LearnerProvider>().portfolio?.cash ??
        0;
    return wrapLearnerPage(Scaffold(
      appBar: AppBar(
        title: learnerBrandTitle(context, 'LP:$challengeName : Trade'),
        actions: learnerAppBarActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'buy', label: Text('Buy'), icon: Icon(Icons.add)),
              ButtonSegment(value: 'sell', label: Text('Sell'), icon: Icon(Icons.remove)),
            ],
            selected: {_side},
            onSelectionChanged: (s) => setState(() => _side = s.first),
          ),
          const SizedBox(height: 16),
          Text('Your cash: ${formatInr(cash)}'),
          const SizedBox(height: 12),
          TextField(
            controller: _symbol,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Symbol',
              border: OutlineInputBorder(),
            ),
            onChanged: _search,
            onSubmitted: _lookupSymbol,
          ),
          ..._suggestions.map(
            (s) => ListTile(
              title: Text(s.symbol),
              subtitle: Text(s.name),
              trailing: Text(formatInr(s.currentPrice)),
              onTap: () => _lookupSymbol(s.symbol),
            ),
          ),
          if (_ltp != null) ...[
            const SizedBox(height: 8),
            Text(_name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Catalog LTP ${formatInr(_ltp!)} (locked)'),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Quantity',
              helperText: _side == 'sell' && _holding != null
                  ? 'Available ${_holding!.quantity}'
                  : 'Fee ₹20 per trade',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (_net != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gross ${formatInr(_gross!)}'),
                    const Text('Transaction fee ₹20'),
                    Text(
                      _side == 'buy'
                          ? 'Debit ${formatInr(_net!)}'
                          : 'Credit ${formatInr(_net!)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_side == 'buy' ? 'Buy at LTP' : 'Sell at LTP'),
          ),
        ],
      ),
    ));
  }
}
