import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/google_sign_in_button.dart';
import '../widgets/turnstile_widget.dart';

final _usernameFormat = RegExp(r'^[a-zA-Z0-9_]{3,64}$');
const _turnstileSiteKeyDefault = '0x4AAAAAAEE_unN60Se7PnnB';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _turnstileController = TurnstileController();

  bool _submitting = false;
  bool _obscure = true;
  bool _checkingUsername = false;
  bool _usernameAvailable = false;
  String? _usernameStatus; // null | available | taken | error | invalid
  int _checkGeneration = 0;

  bool _captchaLoading = true;
  bool _captchaEnabled = false;
  String? _turnstileSiteKey;
  String? _turnstileToken;
  String? _captchaLoadError;
  String? _googleClientId;
  bool _googleSubmitting = false;

  @override
  void initState() {
    super.initState();
    _usernameFocus.addListener(_onUsernameFocusChange);
    _emailController.addListener(_onContactChanged);
    _mobileController.addListener(_onContactChanged);
    _loadCaptchaConfig();
  }

  @override
  void dispose() {
    _usernameFocus.removeListener(_onUsernameFocusChange);
    _emailController.removeListener(_onContactChanged);
    _mobileController.removeListener(_onContactChanged);
    _usernameFocus.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _loadCaptchaConfig() async {
    try {
      final cfg = await ApiService.captchaConfig();
      if (!mounted) return;
      final siteKey = (cfg['turnstileSiteKey'] as String?)?.trim();
      setState(() {
        _captchaLoading = false;
        _captchaEnabled = true;
        _turnstileSiteKey =
            (siteKey != null && siteKey.isNotEmpty) ? siteKey : _turnstileSiteKeyDefault;
        _captchaLoadError = null;
        final googleId = (cfg['googleClientId'] as String?)?.trim() ?? '';
        _googleClientId =
            (cfg['googleEnabled'] == true && googleId.isNotEmpty) ? googleId : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _captchaLoading = false;
        _captchaEnabled = true;
        _turnstileSiteKey = _turnstileSiteKeyDefault;
        _captchaLoadError = null;
      });
    }
  }

  void _onContactChanged() {
    if (mounted) setState(() {});
  }

  void _invalidateUsernameCheck() {
    _checkGeneration++;
    setState(() {
      _usernameAvailable = false;
      _checkingUsername = false;
      _usernameStatus = null;
    });
  }

  void _onUsernameFocusChange() {
    if (_usernameFocus.hasFocus) {
      // Re-editing: disable submit until blur recheck succeeds.
      if (_usernameAvailable || _usernameStatus != null) {
        _invalidateUsernameCheck();
      }
      return;
    }
    _checkUsernameAvailability();
  }

  Future<void> _checkUsernameAvailability() async {
    final raw = _usernameController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _usernameAvailable = false;
        _checkingUsername = false;
        _usernameStatus = null;
      });
      return;
    }
    if (!_usernameFormat.hasMatch(raw)) {
      setState(() {
        _usernameAvailable = false;
        _checkingUsername = false;
        _usernameStatus = 'invalid';
      });
      return;
    }

    final gen = ++_checkGeneration;
    setState(() {
      _checkingUsername = true;
      _usernameAvailable = false;
      _usernameStatus = null;
    });

    try {
      final available = await ApiService.checkUsername(raw.toLowerCase());
      if (!mounted || gen != _checkGeneration) return;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = available;
        _usernameStatus = available ? 'available' : 'taken';
      });
    } catch (e) {
      if (!mounted || gen != _checkGeneration) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = false;
        _usernameStatus = 'error';
      });
      if (msg.toLowerCase().contains('too many')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  bool get _hasContact {
    return _emailController.text.trim().isNotEmpty ||
        _mobileController.text.trim().isNotEmpty;
  }

  bool get _captchaOk {
    if (_captchaLoading) return false;
    if (!_captchaEnabled) return true;
    if (!kIsWeb) return false;
    return _turnstileToken != null && _turnstileToken!.isNotEmpty;
  }

  bool get _canSubmit =>
      _usernameAvailable && !_checkingUsername && !_submitting && _captchaOk;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final ok = await context.read<AuthProvider>().register(
          username: _usernameController.text.trim().toLowerCase(),
          email: _emailController.text.trim(),
          mobile: _mobileController.text.trim(),
          password: _passwordController.text,
          turnstileToken: _turnstileToken,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) {
      final err = context.read<AuthProvider>().error ?? 'Registration failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      _turnstileController.reset();
      setState(() => _turnstileToken = null);
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
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
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Widget? _usernameHelper() {
    if (_checkingUsername) {
      return Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Checking availability…',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
        ],
      );
    }
    switch (_usernameStatus) {
      case 'available':
        return Text(
          'Username available',
          style: TextStyle(color: Colors.green.shade700, fontSize: 12),
        );
      case 'taken':
        return Text(
          'Username is taken',
          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
        );
      case 'invalid':
        return Text(
          '3–64 characters: letters, numbers, and underscores only',
          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
        );
      case 'error':
        return Text(
          'Could not verify username. Try again.',
          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
        );
      default:
        return Text(
          '3–64 characters: letters, numbers, and underscores',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        );
    }
  }

  Widget _captchaSection() {
    if (_captchaLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_captchaLoadError != null && !_captchaEnabled) {
      return Text(
        _captchaLoadError!,
        style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
      );
    }
    if (!_captchaEnabled) {
      return const SizedBox.shrink();
    }
    final siteKey = _turnstileSiteKey;
    if (siteKey == null || siteKey.isEmpty) {
      return const SizedBox.shrink();
    }
    return TurnstileWidget(
      siteKey: siteKey,
      controller: _turnstileController,
      onTokenChanged: (token) {
        if (!mounted || token == _turnstileToken) return;
        setState(() => _turnstileToken = token);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppBrandTitle('Create account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_googleClientId != null && _googleClientId!.isNotEmpty) ...[
                    if (_googleSubmitting)
                      const Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      GoogleSignInButton(
                        clientId: _googleClientId!,
                        onIdToken: _submitGoogle,
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or create an account',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Stay anonymous',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Username is enough. Email and mobile are optional.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _usernameController,
                    focusNode: _usernameFocus,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _invalidateUsernameCheck(),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (!_usernameFormat.hasMatch(s)) {
                        return '3–64 characters: letters, numbers, underscores';
                      }
                      if (!_usernameAvailable) {
                        return 'Confirm username is available';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  _usernameHelper()!,
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Mobile (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (!_hasContact) ...[
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F2EF),
                        border: Border.all(
                          color: const Color(0xFF0F5C56).withValues(alpha: 0.28),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.lock_outline,
                              color: Color(0xFF0F5C56),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Stay anonymous with a username and password. '
                                'Add email or mobile for password reset and alerts. '
                                'Without them, a forgotten password cannot be recovered.',
                                style: TextStyle(
                                  color: const Color(0xFF0F5C56)
                                      .withValues(alpha: 0.9),
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 6) {
                        return 'At least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _captchaSection(),
                  if (_captchaEnabled && !_captchaLoading) ...[
                    const SizedBox(height: 8),
                    Text(
                      _turnstileToken == null || _turnstileToken!.isEmpty
                          ? 'Complete the captcha above to enable Register'
                          : 'Captcha verified — you can register',
                      style: TextStyle(
                        fontSize: 12,
                        color: _turnstileToken == null || _turnstileToken!.isEmpty
                            ? Colors.orange.shade800
                            : Colors.green.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Register'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
