import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../widgets/app_brand_title.dart';
import '../../widgets/auth_app_bar_actions.dart';
import '../../providers/auth_provider.dart';

const Color learnerSeed = Color(0xFF170B48);
const Color learnerAccent = Color(0xFF886AFF);
const Color learnerCta = Color(0xFFFED100);
const Color learnerMist = Color(0xFFF0EDFB);
const Color learnerWash = Color(0xFFD2CAF3);
const String dhanShantiPortalName = 'DhanShanti Portal';
const String flexStreetName = 'FlexStreet';
const String flexStreetByline = 'by DhanShanti';
const String flexStreetGloss = 'An investment challenge';
const String flexStreetBlurb =
    'Virtual money, real stocks. Same starting cash. Leaderboard decides the Alpha.';
const String flexStreetLogoAsset = 'assets/brand/flex_street_logo.png';

/// FlexStreet "Make default" control. Hidden in the UI for now; keep wired.
const bool showFlexStreetMakeDefault = false;

final ThemeData learnerThemeData = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: learnerSeed),
  useMaterial3: true,
  appBarTheme: const AppBarTheme(
    backgroundColor: learnerSeed,
    foregroundColor: Colors.white,
    elevation: 0,
    iconTheme: IconThemeData(color: Colors.white),
    actionsIconTheme: IconThemeData(color: Colors.white),
    titleTextStyle: TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.w500,
    ),
  ),
  cardTheme: CardThemeData(
    color: learnerMist,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: learnerSeed.withValues(alpha: 0.10),
      ),
    ),
  ),
);

void goToMainPortal(BuildContext context) {
  context.read<AuthProvider>().openPortal(AppPortal.main);
}

ButtonStyle learnerOutlinedActionStyle(BuildContext context) {
  final color = Theme.of(context).colorScheme.primary;
  return OutlinedButton.styleFrom(
    foregroundColor: color,
    side: BorderSide(color: color),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    visualDensity: VisualDensity.compact,
  );
}

Widget learnerBrandTitle(
  BuildContext context,
  String label, {
  String? subtitle,
  Widget? trailing,
}) {
  return AppBrandTitle(
    label,
    subtitle: subtitle,
    logoAsset: flexStreetLogoAsset,
    onLogoTap: () => goToPortalDashboard(context),
    logoTooltip: '$flexStreetName home',
    trailing: trailing,
  );
}

Widget wrapLearnerPage(Widget child) {
  return Theme(data: learnerThemeData, child: child);
}

List<Widget> learnerAppBarActions(
  BuildContext context, {
  List<Widget> extra = const [],
}) {
  return authAppBarActions(
    context,
    extra: extra,
    onHelp: () => showLearnerHelpDialog(context),
  );
}

void showLearnerHelpDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Help on $flexStreetName'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'What this is',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '$flexStreetName is an investment challenge with virtual money '
              'and real stocks. Same starting cash. Leaderboard decides the Alpha. '
              'It is separate from your real portfolio on the $dhanShantiPortalName. '
              'Each member gets their own cash and holdings for the challenge.',
            ),
            SizedBox(height: 12),
            Text(
              'Create or join',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Host a challenge with a name, starting cash per person, duration, '
              'and optional teammates. You are added automatically as host.\n\n'
              'Join with an invite code (or a shared invite link). Pending slots '
              'can be claimed by matching email or phone.',
            ),
            SizedBox(height: 12),
            Text(
              'Team',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Only the host manages the roster: add existing users by userid, '
              'email, or phone, or add a pending invite with name/email/phone. '
              'Copy the invite code from the top bar or Team screen.',
            ),
            SizedBox(height: 12),
            Text(
              'Paper trades',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Buy and sell only while the challenge is open. Price is always '
              'the live catalog last traded price (LTP).\n\n'
              'Buy costs qty × LTP + ₹20. Sell credits qty × LTP − ₹20. Trades '
              'are rejected if cash is short, quantity is short, LTP is 0, or '
              'sell proceeds would not cover the fee.',
            ),
            SizedBox(height: 12),
            Text(
              'Holdings and signals',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Open Holdings to review your challenge stocks, signals, notes, '
              'and thresholds. Tap a symbol for the 1-year chart. These books '
              'do not change your main-portal stocks.',
            ),
            SizedBox(height: 12),
            Text(
              'Leaderboard',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Ranking uses each member’s challenge net worth (cash + holdings) '
              'versus the same starting cash.',
            ),
            SizedBox(height: 12),
            Text(
              'When trading stops',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'The clock starts when the challenge is created and ends after '
              'the duration you set. After that the challenge is view-only.',
            ),
            if (showFlexStreetMakeDefault) ...[
              SizedBox(height: 12),
              Text(
                'Default dashboard',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Use Make default in the top bar so the next login '
                'opens this portal instead of $dhanShantiPortalName.',
              ),
            ],
            SizedBox(height: 12),
            Text(
              'Back to $dhanShantiPortalName',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Tap the FlexStreet logo in the top bar to return to this '
              'portal’s dashboard. Use the DhanShanti logo to open your real '
              'portfolio on $dhanShantiPortalName.',
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
