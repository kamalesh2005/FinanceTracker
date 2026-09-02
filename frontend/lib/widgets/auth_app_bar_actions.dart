import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/profile_screen.dart';
import '../screens/feedback_screen.dart';
import '../utils/screen_tracker.dart';

/// AppBar actions for authenticated screens.
/// Order: [extra] → Profile avatar menu → Help (Help is always rightmost).
List<Widget> authAppBarActions(
  BuildContext context, {
  List<Widget> extra = const [],
  VoidCallback? onHelp,
}) {
  final auth = context.watch<AuthProvider>();
  final user = auth.user;
  final initial = user?.avatarInitial ?? '?';
  final identity = user?.menuIdentity ?? 'Account';

  return [
    ...extra,
    PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 40),
      onSelected: (value) {
        if (value == 'profile') {
          final isAlreadyProfile =
              context.findAncestorWidgetOfExactType<ProfileScreen>() != null;
          if (isAlreadyProfile) return;
          Navigator.push(context, appPageRoute(const ProfileScreen()));
        } else if (value == 'feedback') {
          final isAlreadyFeedback =
              context.findAncestorWidgetOfExactType<FeedbackScreen>() != null;
          if (isAlreadyFeedback) return;
          Navigator.push(context, appPageRoute(const FeedbackScreen()));
        } else if (value == 'logout') {
          context.read<AuthProvider>().logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            identity,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'profile',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline),
            title: Text('Profile'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'feedback',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.feedback_outlined),
            title: Text('My Feedback'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Logout'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: CircleAvatar(
          radius: 14,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: Text(
            initial,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
    IconButton(
      tooltip: 'Help',
      icon: const Icon(Icons.help_outline),
      onPressed: onHelp ?? () => showAppHelpDialog(context),
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
              'Getting started',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Register with a username plus email or mobile, then sign in with '
              'email, mobile, or username. Use Forgot password on the login '
              'screen if you need an OTP reset.',
            ),
            SizedBox(height: 12),
            Text(
              'Home',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Your dashboard shows portfolio totals (invested, current value, '
              'P/L) broken down by account for stocks and mutual funds. Tap '
              'Manage on either card to open that section. Gear opens Configure; '
              'your profile avatar and Help are always in the top bar.',
            ),
            SizedBox(height: 12),
            Text(
              'Stocks',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Add stocks one by one, or import from ICICI Direct, HDFC Securities, '
              'Zerodha, or a generic CSV/Excel file. Each holding has quantity, '
              'buy price, and an Account (broker/source).\n\n'
              'Filter by Sector, Market Cap, Account, or Signal; use '
              '"Only Stocks to Action" to focus on BUY / Book Profit / SELL. '
              'Refresh prices from the top bar (or pull to refresh). On wider '
              'screens, switch card/table view and pick columns.\n\n'
              'Tap a stock to edit it; open the chart for price history. Signals '
              '(BUY, SELL, Book Profit, etc.) are computed from your Configure '
              'rules and live prices.',
            ),
            SizedBox(height: 12),
            Text(
              'Mutual funds',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Add funds with scheme details, Account, units, and NAV. Edit or '
              'delete from the list; switch card/table view on larger screens. '
              'Home shows P/L by account.',
            ),
            SizedBox(height: 12),
            Text(
              'Configure',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Stock Watch List mode treats every stock as qty 1 and shows a '
              'count-based summary instead of portfolio value.\n\n'
              'Signal Rules define when BUY, SELL, Book Profit, and similar '
              'labels appear (using fields like curr_price and avg_buy_price). '
              'Save your rules, or reset to the admin defaults.',
            ),
            SizedBox(height: 12),
            Text(
              'Typical flow',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '1. Sign in → Home\n'
              '2. Add or import stocks / mutual funds\n'
              '3. Refresh prices and review Signals\n'
              '4. Optionally tune Signal Rules or Watch List under Configure',
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
