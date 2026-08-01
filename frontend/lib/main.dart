import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/finance_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthProvider _authProvider;
  late final FinanceProvider _financeProvider;
  bool? _wasAuthenticated;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _financeProvider = FinanceProvider();
    ApiService.onUnauthorized = () {
      _authProvider.logout();
    };
    _authProvider.addListener(_onAuthChanged);
    _authProvider.bootstrap();
  }

  void _onAuthChanged() {
    final isAuthenticated = _authProvider.isAuthenticated;
    // Clear finance cache whenever auth session ends or a new session starts.
    if (_wasAuthenticated == true && !isAuthenticated) {
      _financeProvider.clear();
    } else if (_wasAuthenticated != true && isAuthenticated) {
      _financeProvider.clear();
      // Warm Yahoo prices/trends in the background so Stocks is fast.
      _financeProvider.warmYahooStockData();
    }
    _wasAuthenticated = isAuthenticated;
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _financeProvider),
      ],
      // Rebuild MaterialApp (and its Navigator) when auth changes so any
      // pushed routes are discarded and Login/Home replace the stack.
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            key: ValueKey<bool>(auth.isAuthenticated),
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
            home: auth.isLoading
                ? const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  )
                : auth.isAuthenticated
                    ? const HomeScreen()
                    : const LoginScreen(),
          );
        },
      ),
    );
  }
}
