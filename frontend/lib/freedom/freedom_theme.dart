import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

const Color freedomSeed = Color(0xFF1B5E20);

/// Post-retirement pension income rows in the income section.
const Color freedomPensionAccent = Color(0xFF1565C0);

/// Synced / locked input values only.
TextStyle freedomReadonlyValueStyle(BuildContext context) =>
    GoogleFonts.ibmPlexMono(
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
      height: 1.2,
    );

/// In-field labels only (e.g. "Monthly ₹ (in K)").
TextStyle freedomFieldLabelStyle(BuildContext context) {
  final base = Theme.of(context).colorScheme.onSurfaceVariant;
  return GoogleFonts.fraunces(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    color: base.withValues(alpha: 0.9),
    height: 1.1,
  );
}

TextStyle? freedomInputValueStyle(
  BuildContext context, {
  required bool readOnly,
}) =>
    readOnly ? freedomReadonlyValueStyle(context) : null;

InputDecoration freedomFieldDecoration(
  BuildContext context, {
  String? labelText,
  bool isDense = true,
}) {
  final label = freedomFieldLabelStyle(context);
  return InputDecoration(
    labelText: labelText,
    isDense: isDense,
    border: const OutlineInputBorder(),
    labelStyle: label,
    floatingLabelStyle: label,
  );
}

final ThemeData freedomThemeData = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: freedomSeed),
  useMaterial3: true,
  appBarTheme: const AppBarTheme(
    backgroundColor: freedomSeed,
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
    color: const Color(0xFFE8F5E9),
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: freedomSeed.withValues(alpha: 0.10),
      ),
    ),
  ),
);

void goToMainPortal(BuildContext context) {
  context.read<AuthProvider>().openPortal(AppPortal.main);
}

Widget freedomBrandTitle(BuildContext context, String label, {Widget? trailing}) {
  return AppBrandTitle(
    label,
    onLogoTap: () => goToMainPortal(context),
    logoTooltip: 'Main portal',
    trailing: trailing,
  );
}

Widget wrapFreedomPage(Widget child) {
  return Theme(data: freedomThemeData, child: child);
}

List<Widget> freedomAppBarActions(BuildContext context) {
  return authAppBarActions(
    context,
    onHelp: () => showFreedomHelpDialog(context),
  );
}

ButtonStyle freedomOutlinedActionStyle(BuildContext context) {
  final color = Theme.of(context).colorScheme.primary;
  return OutlinedButton.styleFrom(
    foregroundColor: color,
    side: BorderSide(color: color),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    visualDensity: VisualDensity.compact,
  );
}

void showFreedomHelpDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Financial Freedom Portal'),
      content: const Text(
        'Track assets (with income and tax), income from salary/profession, '
        'recurring expenses, and major one-time costs.\n\n'
        'Active Income: sum of salary/profession income for the current year '
        '(through each row\'s end year) plus pension from its start year onward.\n\n'
        'Passive Income: effective return from assets for the current year.\n\n'
        'Regular Expenses: total recurring expenses for the current year.\n\n'
        'Major one-time expenses: enter amounts in today\'s value (₹ in K); '
        'Ready to Retire uses them as entered.\n\n'
        'Ready to Retire (Years): year-by-year simulation through the latest of '
        'last one-time year + 1, salary end year + 1, or pension start year + 1. '
        'Passive income is inflation-adjusted (return% − 6%) for all assets except '
        'Real Estate & Gold (full return%). Expenses and one-times are not inflated. '
        'Each year-end, surplus (adj. passive + salary/pension − recurring − asset EMI) '
        'is reinvested; one-time costs reduce the corpus when due and are included in '
        'Total Exp. Inc ≥ Exp compares end income to recurring expenses plus asset EMI '
        'only (one-time excluded). If the last simulated year fails, retirement is not '
        'reachable; otherwise walk back to the latest NO year — ready is that year + 1 '
        '(now if every year passes). Corpus wipes to zero if a one-time exceeds assets.\n\n'
        'Live Well Fund for the year: take end income minus total expenses in the '
        'first year after the last scheduled one-time expense (current year if none). '
        'Discount that surplus to today\'s money using each simulated year\'s P/Corpus % '
        'from the Ready to Retire table, then divide by 2. Floored at zero.\n\n'
        'Term Insurance Needs (15/75 Rule):\n'
        'Cover = Debt + 15 years of 75% of annual living expenses − Investments.\n'
        'Debt: remaining EMIs — asset EMI × months left, plus expense EMI × years left through end year.\n'
        'Living expenses: regular expenses excluding the EMI category; 75% of that annual amount × 15 years.\n'
        'Investments: sum of all asset values except Primary Residence and Physical Gold.\n'
        'The result is the suggested term insurance cover (floored at zero).',
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
