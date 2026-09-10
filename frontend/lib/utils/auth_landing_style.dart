import 'package:flutter/material.dart';

import '../freedom/freedom_theme.dart';
import '../learner/learner_theme.dart';
import 'flex_street_entry.dart';

/// Colors and copy for the unauthenticated landing (login / register).
class AuthLandingStyle {
  const AuthLandingStyle({
    required this.flexStreet,
    required this.primary,
    required this.accent,
    required this.cta,
    required this.mist,
    required this.wash,
    required this.logoAsset,
    required this.heroTitle,
    this.heroByline,
    required this.heroTagline,
    required this.heroLines,
    required this.portalsNavLabel,
    required this.featuresTitle,
    required this.featuresSubtitle,
    required this.features,
    required this.midTitle,
    required this.midSubtitle,
    required this.midCards,
    required this.howTitle,
    required this.howSubtitle,
    required this.howSteps,
    required this.privacyTitle,
    required this.privacyBody,
    required this.privacyExtra,
    required this.privacyCta,
    required this.createAccountLabel,
    required this.registerTitle,
    required this.registerSubtitle,
  });

  final bool flexStreet;
  final Color primary;
  final Color accent;
  final Color cta;
  final Color mist;
  final Color wash;
  final String logoAsset;
  final String heroTitle;
  final String? heroByline;
  final String heroTagline;
  final List<String> heroLines;
  final String portalsNavLabel;
  final String featuresTitle;
  final String featuresSubtitle;
  final List<(IconData, String, String)> features;
  final String midTitle;
  final String midSubtitle;
  final List<(IconData, String, String, String)> midCards;
  final String howTitle;
  final String howSubtitle;
  final List<(String, String, String)> howSteps;
  final String privacyTitle;
  final String privacyBody;
  final String privacyExtra;
  final String privacyCta;
  final String createAccountLabel;
  final String registerTitle;
  final String registerSubtitle;

  static AuthLandingStyle resolve({bool? flexStreet, Uri? uri}) {
    final useFlex = flexStreet ?? isFlexStreetEntry(uri);
    return useFlex ? flexStreetStyle : dhanShantiStyle;
  }

  static const dhanShantiStyle = AuthLandingStyle(
    flexStreet: false,
    primary: Color(0xFF0F5C56),
    accent: Color(0xFFC4A35A),
    cta: Color(0xFFC4A35A),
    mist: Color(0xFFE8F2EF),
    wash: Color(0xFFC5D9D0),
    logoAsset: 'assets/brand/dhan_shanti_logo.png',
    heroTitle: 'Dhan Shanti',
    heroTagline: 'Rules on. Noise off.',
    heroLines: [
      'Built for busy professionals.',
      'Let rules watch the market. Show up only for the decisions that count.',
    ],
    portalsNavLabel: 'FlexStreet & Horizon',
    featuresTitle: 'Top features',
    featuresSubtitle:
        'Live book for busy professionals: holdings, rules, and signals - plus research, a paper challenge, and a freedom plan.',
    features: [
      (
        Icons.account_balance_wallet_outlined,
        'Portfolio dashboard',
        'Invested value, current value, and P/L for stocks and mutual funds.',
      ),
      (
        Icons.trending_up,
        'Live prices & trends',
        'Quotes with moving averages and bullish or bearish cues.',
      ),
      (
        Icons.upload_file_outlined,
        'Broker imports',
        'Bring holdings from CSV or Excel - ICICI, HDFC Sec, Zerodha, and more.',
      ),
      (
        Icons.rule_folder_outlined,
        'Custom signal rules',
        'BUY, SELL, and Book Profit signals driven by rules and thresholds you define.',
      ),
      (
        Icons.show_chart,
        'Charts & news',
        'Price history and publicly available stock recommendations by analysts, so decisions stay grounded in context.',
      ),
      (
        Icons.manage_search_outlined,
        'Stock Research',
        'Screen the market for ideas and keep a Watch List of symbols.',
      ),
    ],
    midTitle: 'More than a portfolio',
    midSubtitle:
        'Sign in, then open these from Home. Your live holdings stay separate.',
    midCards: [
      (
        Icons.emoji_events,
        flexStreetName,
        flexStreetGloss,
        flexStreetBlurb,
      ),
      (
        Icons.park_outlined,
        horizonName,
        horizonGloss,
        horizonBlurb,
      ),
    ],
    howTitle: 'How it works',
    howSubtitle:
        'The live portfolio, in four steps. FlexStreet and Horizon wait on Home after you sign in.',
    howSteps: [
      (
        '1',
        'Stay anonymous',
        'Pick a username. Skip email and phone if you want.',
      ),
      (
        '2',
        'Add holdings',
        'Import from your broker or add stocks and funds - full portfolio or watch list.',
      ),
      (
        '3',
        'Set your rules',
        'Define buy, sell, and hold thresholds that match how you invest.',
      ),
      (
        '4',
        'Review signals',
        'See automated signals and act when it feels right.',
      ),
    ],
    privacyTitle: 'Stay anonymous. Your portfolio stays yours.',
    privacyBody:
        'Sign up with a username. Email and mobile are optional - we do '
        'not need your name, PAN, or broker login. Holdings and signal '
        'rules live in your account and are not shown to other users.',
    privacyExtra:
        'Want even less on screen? Watch List mode tracks equities '
        'without framing every symbol as a portfolio with quantities '
        'and value. Signal rules stay in-app, under thresholds you control.',
    privacyCta: 'Create an anonymous account',
    createAccountLabel: 'Create an account',
    registerTitle: 'Create account',
    registerSubtitle: 'Username is enough. Email and mobile are optional.',
  );

  static const flexStreetStyle = AuthLandingStyle(
    flexStreet: true,
    primary: learnerSeed,
    accent: learnerAccent,
    cta: learnerCta,
    mist: learnerMist,
    wash: learnerWash,
    logoAsset: flexStreetLogoAsset,
    heroTitle: flexStreetName,
    heroByline: flexStreetByline,
    heroTagline: flexStreetGloss,
    heroLines: [
      flexStreetBlurb,
      'Paper trades only. Your live DhanShanti portfolio stays untouched.',
    ],
    portalsNavLabel: 'The challenge',
    featuresTitle: 'Built for the challenge',
    featuresSubtitle:
        'Virtual cash, live catalog prices, and a leaderboard. Same start for everyone.',
    features: [
      (
        Icons.savings_outlined,
        'Same starting cash',
        'Everyone begins with the same paper money. Skill, not bankroll, decides the ranking.',
      ),
      (
        Icons.ssid_chart,
        'Real last traded prices',
        'Buys and sells fill at live catalog LTP, with a small fee on every trade.',
      ),
      (
        Icons.leaderboard_outlined,
        'Leaderboard',
        'Rank by challenge net worth — cash plus holdings versus that shared starting cash.',
      ),
      (
        Icons.flag_outlined,
        'Create or join',
        'Host a challenge with duration and starting cash, or enter with an invite code.',
      ),
      (
        Icons.groups_outlined,
        'Teams',
        'The host manages the roster. Pending invites can be claimed by email or phone.',
      ),
      (
        Icons.insights_outlined,
        'Challenge book',
        'Holdings, charts, notes, and thresholds on paper positions only.',
      ),
    ],
    midTitle: 'The challenge',
    midSubtitle:
        'An investment challenge with virtual money and real stocks. Separate from your live portfolio.',
    midCards: [
      (
        Icons.emoji_events,
        flexStreetName,
        flexStreetGloss,
        flexStreetBlurb,
      ),
    ],
    howTitle: 'How it works',
    howSubtitle:
        'Four steps from an anonymous username to the leaderboard.',
    howSteps: [
      (
        '1',
        'Stay anonymous',
        'Pick a username. Skip email and phone if you want.',
      ),
      (
        '2',
        'Create or join',
        'Host a challenge or enter with an invite code.',
      ),
      (
        '3',
        'Trade paper',
        'Buy and sell at live LTP while the challenge is open.',
      ),
      (
        '4',
        'Climb the board',
        'Ranking uses cash plus holdings versus the same starting cash.',
      ),
    ],
    privacyTitle: 'Stay anonymous. Your challenge stays yours.',
    privacyBody:
        'Sign up with a username. Email and mobile are optional - we do '
        'not need your name, PAN, or broker login. Challenge holdings '
        'stay separate in FlexStreet and are not shown as a live portfolio.',
    privacyExtra:
        'This is paper money. FlexStreet trades never change your real '
        'DhanShanti holdings, quantities, or value.',
    privacyCta: 'Join FlexStreet',
    createAccountLabel: 'Join FlexStreet',
    registerTitle: 'Join FlexStreet',
    registerSubtitle:
        'Username is enough to enter the challenge. Email and mobile are optional.',
  );
}
