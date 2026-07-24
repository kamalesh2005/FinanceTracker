import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import '../models/mutual_fund.dart';
import '../widgets/auth_app_bar_actions.dart';

class AddMutualFundScreen extends StatefulWidget {
  final MutualFund? mutualFund;

  const AddMutualFundScreen({super.key, this.mutualFund});

  @override
  State<AddMutualFundScreen> createState() => _AddMutualFundScreenState();
}

class _AddMutualFundScreenState extends State<AddMutualFundScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _schemeCodeController;
  late TextEditingController _schemeNameController;
  late TextEditingController _fundHouseController;
  late TextEditingController _quantityController;
  late TextEditingController _navController;
  late TextEditingController _currentNavController;
  late DateTime _purchaseDate;

  @override
  void initState() {
    super.initState();
    _schemeCodeController = TextEditingController(text: widget.mutualFund?.schemeCode ?? '');
    _schemeNameController = TextEditingController(text: widget.mutualFund?.schemeName ?? '');
    _fundHouseController = TextEditingController(text: widget.mutualFund?.fundHouse ?? '');
    _quantityController = TextEditingController(text: widget.mutualFund?.quantity.toString() ?? '');
    _navController = TextEditingController(text: widget.mutualFund?.nav.toString() ?? '');
    _currentNavController = TextEditingController(text: widget.mutualFund?.currentNav.toString() ?? '');
    _purchaseDate = widget.mutualFund?.purchaseDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _schemeCodeController.dispose();
    _schemeNameController.dispose();
    _fundHouseController.dispose();
    _quantityController.dispose();
    _navController.dispose();
    _currentNavController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mutualFund == null ? 'Add Mutual Fund' : 'Edit Mutual Fund'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _schemeCodeController,
                decoration: const InputDecoration(
                  labelText: 'Scheme Code *',
                  hintText: 'e.g., 120503',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter scheme code';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _schemeNameController,
                decoration: const InputDecoration(
                  labelText: 'Scheme Name *',
                  hintText: 'e.g., HDFC Small Cap Fund',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter scheme name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fundHouseController,
                decoration: const InputDecoration(
                  labelText: 'Fund House',
                  hintText: 'e.g., HDFC Mutual Fund',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                decoration: const InputDecoration(
                  labelText: 'Units *',
                  hintText: 'e.g., 100',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter units';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _navController,
                decoration: const InputDecoration(
                  labelText: 'NAV (₹) *',
                  hintText: 'e.g., 50.25',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter NAV';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _currentNavController,
                decoration: const InputDecoration(
                  labelText: 'Current NAV (₹)',
                  hintText: 'e.g., 55.75',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Purchase Date'),
                subtitle: Text('${_purchaseDate.toLocal()}'.split(' ')[0]),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _purchaseDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && picked != _purchaseDate) {
                    setState(() {
                      _purchaseDate = picked;
                    });
                  }
                },
              ),
              const SizedBox(height: 24),
              Consumer<FinanceProvider>(
                builder: (context, provider, child) {
                  return ElevatedButton(
                    onPressed: provider.isLoading
                        ? null
                        : () async {
                            if (_formKey.currentState!.validate()) {
                              final mf = MutualFund(
                                id: widget.mutualFund?.id ?? 0,
                                schemeCode: _schemeCodeController.text,
                                schemeName: _schemeNameController.text,
                                fundHouse: _fundHouseController.text,
                                quantity: double.parse(_quantityController.text),
                                nav: double.parse(_navController.text),
                                currentNav: _currentNavController.text.isEmpty
                                    ? 0.0
                                    : double.parse(_currentNavController.text),
                                purchaseDate: _purchaseDate,
                                createdAt: widget.mutualFund?.createdAt ?? DateTime.now(),
                                updatedAt: DateTime.now(),
                              );

                              if (widget.mutualFund == null) {
                                await provider.addMutualFund(mf);
                              } else {
                                await provider.updateMutualFund(widget.mutualFund!.id, mf);
                              }

                              if (provider.error != null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: ${provider.error}'), backgroundColor: Colors.red),
                                  );
                                }
                                return;
                              }

                              if (context.mounted) Navigator.pop(context);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: provider.isLoading
                        ? const CircularProgressIndicator()
                        : Text(widget.mutualFund == null ? 'Add Mutual Fund' : 'Update Mutual Fund'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
