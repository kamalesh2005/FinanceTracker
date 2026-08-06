import 'package:flutter/material.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';
import 'symbol_mappings_screen.dart';
import 'unmapped_stocks_screen.dart';
import 'mf_scheme_mappings_screen.dart';
import 'unmapped_mf_schemes_screen.dart';
import 'admin_stock_data_screen.dart';
import 'admin_mutual_fund_data_screen.dart';
import 'admin_users_screen.dart';
import 'admin_app_settings_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Admin'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Admin Activities',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Manage users, app defaults, stock and mutual fund mappings, and catalog data.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 24),
          _AdminTile(
            icon: Icons.people_outline,
            color: Colors.indigo,
            title: 'Users',
            subtitle: 'View users and enable or disable accounts',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
            ),
          ),
          _AdminTile(
            icon: Icons.tune,
            color: Colors.deepPurple,
            title: 'App Settings',
            subtitle:
                'Default fluctuation to ignore signals post any buy/sell',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminAppSettingsScreen()),
            ),
          ),
          _AdminTile(
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
            title: 'Unmapped Stocks',
            subtitle:
                'Broker symbols missing Yahoo data or with incorrect mappings',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UnmappedStocksScreen()),
            ),
          ),
          _AdminTile(
            icon: Icons.warning_amber_rounded,
            color: Colors.deepOrange,
            title: 'Unmapped Mutual Funds',
            subtitle:
                'Broker scheme names missing catalog ISIN or with incorrect mappings',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UnmappedMFSchemesScreen(),
              ),
            ),
          ),
          _AdminTile(
            icon: Icons.map_outlined,
            color: Colors.blue,
            title: 'Stock Symbol Mappings',
            subtitle:
                'View, search, add or edit broker → Yahoo symbol mappings',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SymbolMappingsScreen()),
            ),
          ),
          _AdminTile(
            icon: Icons.account_tree_outlined,
            color: Colors.cyan,
            title: 'Mutual Fund Scheme Mappings',
            subtitle:
                'View, search, add or edit broker → catalog ISIN mappings',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MFSchemeMappingsScreen(),
              ),
            ),
          ),
          _AdminTile(
            icon: Icons.edit_note,
            color: Colors.teal,
            title: 'Update Stock Data',
            subtitle:
                'Browse catalog, edit name/industry, upload NSE or ETF CSV',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminStockDataScreen()),
            ),
          ),
          _AdminTile(
            icon: Icons.account_balance,
            color: Colors.brown,
            title: 'Update Mutual Fund Data',
            subtitle:
                'Browse catalog, upload NSCCL xlsx/csv or MF_VAR NAV CSV',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminMutualFundDataScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
