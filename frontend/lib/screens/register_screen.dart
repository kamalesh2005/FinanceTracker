import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';

final _usernameFormat = RegExp(r'^[a-zA-Z0-9_]{3,64}$');

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

  bool _submitting = false;
  bool _obscure = true;
  bool _checkingUsername = false;
  bool _usernameAvailable = false;
  String? _usernameStatus; // null | available | taken | error | invalid
  int _checkGeneration = 0;

  @override
  void initState() {
    super.initState();
    _usernameFocus.addListener(_onUsernameFocusChange);
    _emailController.addListener(_onContactChanged);
    _mobileController.addListener(_onContactChanged);
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
    } catch (_) {
      if (!mounted || gen != _checkGeneration) return;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = false;
        _usernameStatus = 'error';
      });
    }
  }

  bool get _hasContact {
    return _emailController.text.trim().isNotEmpty ||
        _mobileController.text.trim().isNotEmpty;
  }

  bool get _canSubmit =>
      _usernameAvailable && !_checkingUsername && !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final ok = await context.read<AuthProvider>().register(
          username: _usernameController.text.trim().toLowerCase(),
          email: _emailController.text.trim(),
          mobile: _mobileController.text.trim(),
          password: _passwordController.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) {
      final err = context.read<AuthProvider>().error ?? 'Registration failed';
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
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade700),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber.shade900,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Without email or mobile, notifications will not be available. '
                                'If you forget your password, you will lose access to your data.',
                                style: TextStyle(
                                  color: Colors.amber.shade900,
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
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
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
