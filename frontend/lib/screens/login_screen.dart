import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/google_sign_in_button.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _featuresKey = GlobalKey();
  final _howItWorksKey = GlobalKey();
  final _privacyKey = GlobalKey();
  bool _submitting = false;
  bool _obscure = true;
  bool _googleSubmitting = false;
  String? _googleClientId;

  static const _teal = Color(0xFF0F5C56);
  static const _gold = Color(0xFFC4A35A);
  static const _mist = Color(0xFFE8F2EF);
  static const _sage = Color(0xFFC5D9D0);
  static const _loginPanelWidth = 400.0;
  static const _contentMaxWidth = 1248.0; // 1040 + 20%

  @override
  void initState() {
    super.initState();
    _loadGoogleConfig();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final ok = await context.read<AuthProvider>().login(
          _identifierController.text.trim(),
          _passwordController.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) {
      final err = context.read<AuthProvider>().error ?? 'Login failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _loadGoogleConfig() async {
    try {
      final cfg = await ApiService.captchaConfig();
      if (!mounted) return;
      final id = (cfg['googleClientId'] as String?)?.trim() ?? '';
      final enabled = cfg['googleEnabled'] == true && id.isNotEmpty;
      setState(() => _googleClientId = enabled ? id : null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _googleClientId = null);
    }
  }

  Future<void> _submitGoogle(String idToken) async {
    if (!mounted || _submitting || _googleSubmitting) return;
    setState(() => _googleSubmitting = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithGoogle(idToken);
    if (!mounted) return;
    setState(() => _googleSubmitting = false);
    if (!ok) {
      final err = auth.error ?? 'Google Sign-In failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  Widget _loginPanel() {
    return _LoginPanel(
      formKey: _formKey,
      identifierController: _identifierController,
      passwordController: _passwordController,
      submitting: _submitting,
      obscure: _obscure,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      onSubmit: _submit,
      googleClientId: _googleClientId,
      googleSubmitting: _googleSubmitting,
      onGoogleIdToken: _submitGoogle,
      onGoogleError: (msg) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _mist,
              Color(0xFFF4F8F6),
              _sage,
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: Column(
          children: [
            _LandingHeader(
              onFeatures: () => _scrollTo(_featuresKey),
              onHowItWorks: () => _scrollTo(_howItWorksKey),
              onPrivacy: () => _scrollTo(_privacyKey),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _contentMaxWidth,
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: wide ? 32 : 24,
                                  vertical: wide ? 36 : 24,
                                ),
                                child: wide
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            child: _BrandHero(
                                              wide: true,
                                              onPrivacy: () =>
                                                  _scrollTo(_privacyKey),
                                            ),
                                          ),
                                          const SizedBox(width: 40),
                                          SizedBox(
                                            width: _loginPanelWidth,
                                            child: _loginPanel(),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _BrandHero(
                                            wide: false,
                                            onPrivacy: () =>
                                                _scrollTo(_privacyKey),
                                          ),
                                          const SizedBox(height: 24),
                                          Center(
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: _loginPanelWidth,
                                              ),
                                              child: _loginPanel(),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _featuresKey,
                          child: const _FeaturesSection(),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _howItWorksKey,
                          child: const _HowItWorksSection(),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _privacyKey,
                          child: const _PrivacySection(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingHeader extends StatelessWidget {
  const _LandingHeader({
    required this.onFeatures,
    required this.onHowItWorks,
    required this.onPrivacy,
  });

  final VoidCallback onFeatures;
  final VoidCallback onHowItWorks;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: _LoginScreenState._teal,
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final horizontal = wide ? 32.0 : 24.0;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _LoginScreenState._contentMaxWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontal,
                    vertical: 4,
                  ),
                  child: SizedBox(
                    height: 48,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _NavLink(label: 'Features', onTap: onFeatures),
                            _NavLink(
                              label: 'How it works',
                              onTap: onHowItWorks,
                            ),
                            _NavLink(label: 'Privacy', onTap: onPrivacy),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero({required this.wide, required this.onPrivacy});

  final bool wide;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        ClipOval(
          child: Image.asset(
            'assets/brand/dhan_shanti_logo.png',
            width: wide ? 96 : 80,
            height: wide ? 96 : 80,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(height: wide ? 28 : 20),
        Text(
          'Dhan Shanti',
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: GoogleFonts.fraunces(
            fontSize: wide ? 52 : 40,
            fontWeight: FontWeight.w600,
            color: _LoginScreenState._teal,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Financial Peace, automated',
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: wide ? 20 : 17,
            fontWeight: FontWeight.w500,
            color: _LoginScreenState._gold,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: wide ? Alignment.centerLeft : Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _AnonymousChip(onTap: onPrivacy),
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'Put your portfolio on autopilot. Set rules and relax, let signals guide the next move when it matters.',
            textAlign: wide ? TextAlign.start : TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 16,
              height: 1.45,
              color: _LoginScreenState._teal.withValues(alpha: 0.78),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnonymousChip extends StatelessWidget {
  const _AnonymousChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const teal = _LoginScreenState._teal;
    return Semantics(
      button: true,
      label: 'Stay anonymous, no personal information required. Jump to privacy.',
      child: Material(
        color: teal.withValues(alpha: 0.08),
        elevation: 0,
        shape: StadiumBorder(
          side: BorderSide(color: teal.withValues(alpha: 0.18)),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: _LoginScreenState._gold,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Stay anonymous - no personal information required',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: teal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.formKey,
    required this.identifierController,
    required this.passwordController,
    required this.submitting,
    required this.obscure,
    required this.onToggleObscure,
    required this.onSubmit,
    this.googleClientId,
    this.googleSubmitting = false,
    this.onGoogleIdToken,
    this.onGoogleError,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController identifierController;
  final TextEditingController passwordController;
  final bool submitting;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final String? googleClientId;
  final bool googleSubmitting;
  final ValueChanged<String>? onGoogleIdToken;
  final ValueChanged<String>? onGoogleError;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _LoginScreenState._teal.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
          child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sign in',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: _LoginScreenState._teal,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Use email, mobile, or username',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: identifierController,
                style: GoogleFonts.outfit(),
                decoration: InputDecoration(
                  labelText: 'Email / Mobile / Username',
                  labelStyle: GoogleFonts.outfit(),
                  border: const OutlineInputBorder(),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _LoginScreenState._teal,
                      width: 2,
                    ),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                obscureText: obscure,
                style: GoogleFonts.outfit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: GoogleFonts.outfit(),
                  border: const OutlineInputBorder(),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _LoginScreenState._teal,
                      width: 2,
                    ),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                      color: _LoginScreenState._teal.withValues(alpha: 0.7),
                    ),
                    onPressed: onToggleObscure,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
                onFieldSubmitted: (_) => onSubmit(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordScreen(),
                      ),
                    );
                  },
                  child: Text(
                    'Forgot password?',
                    style: GoogleFonts.outfit(
                      color: _LoginScreenState._teal,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: submitting ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: _LoginScreenState._teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Sign in'),
              ),
              if (googleClientId != null &&
                  googleClientId!.isNotEmpty &&
                  onGoogleIdToken != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or',
                        style: GoogleFonts.outfit(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                  ],
                ),
                const SizedBox(height: 16),
                if (googleSubmitting)
                  const Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  GoogleSignInButton(
                    clientId: googleClientId!,
                    onIdToken: onGoogleIdToken!,
                    onError: onGoogleError,
                  ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RegisterScreen(),
                    ),
                  );
                },
                child: Text(
                  'Create an account',
                  style: GoogleFonts.outfit(
                    color: _LoginScreenState._teal,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                'Prefer privacy? Create an account with just a username.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  height: 1.35,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.fraunces(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: _LoginScreenState._teal,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  height: 1.4,
                  color: _LoginScreenState._teal.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection();

  static const _features = [
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
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.45),
      child: _SectionShell(
        title: 'Top features',
        subtitle:
            'Everything you need to calmly invest Indian equities and funds.',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 720
                ? 3
                : constraints.maxWidth >= 480
                    ? 2
                    : 1;
            return Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                for (final f in _features)
                  SizedBox(
                    width: cols == 1
                        ? constraints.maxWidth
                        : (constraints.maxWidth - (cols - 1) * 20) / cols,
                    child: _FeatureItem(
                      icon: f.$1,
                      title: f.$2,
                      body: f.$3,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _LoginScreenState._gold, size: 28),
        const SizedBox(height: 12),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _LoginScreenState._teal,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: GoogleFonts.outfit(
            fontSize: 14,
            height: 1.4,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }
}

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  static const _steps = [
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
  ];

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      title: 'How it works',
      subtitle:
          'Four steps from an anonymous account to calm, rule-based guidance.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 700;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(
                    child: _StepItem(
                      number: _steps[i].$1,
                      title: _steps[i].$2,
                      body: _steps[i].$3,
                    ),
                  ),
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                if (i > 0) const SizedBox(height: 20),
                _StepItem(
                  number: _steps[i].$1,
                  title: _steps[i].$2,
                  body: _steps[i].$3,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: GoogleFonts.fraunces(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: _LoginScreenState._gold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _LoginScreenState._teal,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: GoogleFonts.outfit(
            fontSize: 14,
            height: 1.4,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _LoginScreenState._teal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stay anonymous. Your portfolio stays yours.',
                  style: GoogleFonts.fraunces(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Sign up with a username. Email and mobile are optional - we do '
                  'not need your name, PAN, or broker login. Holdings and signal '
                  'rules live in your account and are not shown to other users.',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Want even less on screen? Watch List mode tracks equities '
                  'without framing every symbol as a portfolio with quantities '
                  'and value. Signal rules stay in-app, under thresholds you control.',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      color: _LoginScreenState._gold,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Username-only accounts. Email and mobile optional.',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _LoginScreenState._gold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegisterScreen(),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _LoginScreenState._gold,
                    foregroundColor: _LoginScreenState._teal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    textStyle: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Create an anonymous account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
