import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/user.dart';
import 'learner/learner_provider.dart';
import 'learner/screens/learner_portal_screen.dart';
import 'freedom/freedom_provider.dart';
import 'freedom/screens/freedom_portal_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/finance_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'utils/screen_tracker.dart';
import 'widgets/feedback_fab.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final AuthProvider _authProvider;
  late final FinanceProvider _financeProvider;
  late final LearnerProvider _learnerProvider;
  late final FreedomProvider _freedomProvider;
  bool? _wasAuthenticated;
  String? _wasPortal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authProvider = AuthProvider();
    _financeProvider = FinanceProvider();
    _learnerProvider = LearnerProvider();
    _freedomProvider = FreedomProvider();
    ApiService.onUnauthorized = () {
      _authProvider.handleUnauthorized();
    };
    _authProvider.addListener(_onAuthChanged);
    _authProvider.bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _authProvider.onAppResumed();
    }
  }

  void _onAuthChanged() {
    final isAuthenticated = _authProvider.isAuthenticated;
    final portal = _authProvider.activePortal;
    final sessionChanged = _wasAuthenticated != isAuthenticated;
    final portalChanged =
        isAuthenticated && _wasPortal != null && _wasPortal != portal;
    try {
      // Clear finance cache whenever auth session ends or a new session starts.
      if (_wasAuthenticated == true && !isAuthenticated) {
        _financeProvider.clear();
        _learnerProvider.clear();
        _freedomProvider.clear();
      } else if (_wasAuthenticated != true && isAuthenticated) {
        _financeProvider.clear();
        _learnerProvider.clear();
        _freedomProvider.clear();
        // Warm Yahoo prices/trends in the background so Stocks is fast.
        _financeProvider.warmYahooStockData();
      }
      // Only reset the stack on login/logout/portal switch — not on every
      // AuthProvider notify (Stocks calls loadPreferences, which would
      // otherwise pop Manage right back to the dashboard).
      if (sessionChanged || portalChanged) {
        final nav = rootNavigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.popUntil((route) => route.isFirst);
        }
      }
    } catch (_) {
      // Never block the login→dashboard rebuild if cache warm-up fails.
    }
    _wasAuthenticated = isAuthenticated;
    _wasPortal = portal;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authProvider.removeListener(_onAuthChanged);
    _authProvider.dispose();
    super.dispose();
  }

  Widget _homeFor(AuthProvider auth) {
    if (auth.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.isAuthenticated) {
      return const LoginScreen();
    }
    if (auth.activePortal == AppPortal.learner) {
      return TrackedScreen(
        child: LearnerPortalScreen(
          initialInviteCode: auth.pendingLearnerInvite,
        ),
      );
    }
    if (auth.activePortal == AppPortal.freedom) {
      return const TrackedScreen(child: FreedomPortalScreen());
    }
    return const TrackedScreen(child: HomeScreen());
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _financeProvider),
        ChangeNotifierProvider.value(value: _learnerProvider),
        ChangeNotifierProvider.value(value: _freedomProvider),
      ],
      // Keep MaterialApp (and navigatorKey) stable. Swapping Login/Home happens
      // inside the home widget so a successful login can actually mount the
      // dashboard on Flutter web.
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        navigatorObservers: [screenTrackerRouteObserver],
        title: 'Dhan Shanti',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0F5C56),
          ),
          useMaterial3: true,
          cardTheme: CardThemeData(
            color: const Color(0xFFE8F2EF),
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: const Color(0xFF0F5C56).withValues(alpha: 0.08),
              ),
            ),
          ),
        ),
        // Thin Feedback tab on the right edge (does not cover bottom-right content).
        builder: (context, child) {
          return Consumer<AuthProvider>(
            builder: (context, auth, _) {
              final content = child ?? const SizedBox.shrink();
              if (!auth.isAuthenticated || auth.isLoading) {
                return content;
              }
              return Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  content,
                  const Align(
                    alignment: Alignment.centerRight,
                    child: FeedbackFab(),
                  ),
                ],
              );
            },
          );
        },
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) => _homeFor(auth),
        ),
      ),
    );
  }
}
