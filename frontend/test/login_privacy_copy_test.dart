import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_tracker/providers/auth_provider.dart';
import 'package:finance_tracker/screens/login_screen.dart';
import 'package:finance_tracker/screens/register_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('login landing highlights anonymous privacy', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Stay anonymous - no personal information required'), findsOneWidget);
    expect(
      find.text('Prefer privacy? Create an account with just a username.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Stay anonymous - no personal information required'));
    await tester.pumpAndSettle();

    expect(find.text('Stay anonymous'), findsWidgets);
    expect(
      find.text('Pick a username. Skip email and phone if you want.'),
      findsOneWidget,
    );
    expect(
      find.text('Stay anonymous. Your portfolio stays yours.'),
      findsOneWidget,
    );
    expect(find.text('Create an anonymous account'), findsOneWidget);
  });

  testWidgets('register screen treats username-only as the default path',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: RegisterScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Stay anonymous'), findsOneWidget);
    expect(
      find.text('Username is enough. Email and mobile are optional.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Stay anonymous with a username and password.'),
      findsOneWidget,
    );
    expect(find.textContaining('lose access to your data'), findsNothing);
  });

  testWidgets('login landing lays out on compact screens', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Stay anonymous - no personal information required'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
  });
}
