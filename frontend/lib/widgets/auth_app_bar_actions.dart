import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// AppBar actions for authenticated screens.
/// Order: [extra] → Logout → Help (Help is always rightmost).
List<Widget> authAppBarActions(
  BuildContext context, {
  List<Widget> extra = const [],
}) {
  return [
    ...extra,
    IconButton(
      tooltip: 'Logout',
      icon: const Icon(Icons.logout),
      onPressed: () => context.read<AuthProvider>().logout(),
    ),
    IconButton(
      tooltip: 'Help',
      icon: const Icon(Icons.help_outline),
      onPressed: () => showAppHelpDialog(context),
    ),
  ];
}

void showAppHelpDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Help'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Portfolio',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Home shows total invested, current value, and P/L across stocks and mutual funds.',
            ),
            SizedBox(height: 12),
            Text(
              'Stocks',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Open Stocks to view holdings. Use Sector, Market Cap, Account, and Recommendation filters to narrow the list. Tap the refresh icon (or pull to refresh) to update prices from Yahoo. The backend also refreshes Global_Stocks prices every 15 minutes on weekdays 09:00–15:30 IST.',
            ),
            SizedBox(height: 12),
            Text(
              'Symbol mappings',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'If a broker symbol does not match Yahoo, map it under Admin → Symbol Mappings (or Unmapped Stocks) so prices and trends can load.',
            ),
            SizedBox(height: 12),
            Text(
              'Logout',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Use the logout icon on any screen to end your session.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
