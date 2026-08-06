import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/auth_app_bar_actions.dart';

final _usernameFormat = RegExp(r'^[a-zA-Z0-9_]{3,64}$');

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _mobileFocus = FocusNode();

  String _originalUsername = '';
  String _originalEmail = '';
  String _originalMobile = '';

  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  bool _checkingUsername = false;
  bool _usernameAvailable = true;
  String? _usernameStatus;
  int _usernameCheckGen = 0;

  bool _checkingEmail = false;
  bool _emailAvailable = true;
  String? _emailStatus;
  int _emailCheckGen = 0;

  bool _checkingMobile = false;
  bool _mobileAvailable = true;
  String? _mobileStatus;
  int _mobileCheckGen = 0;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _originalUsername = user?.username ?? '';
    _originalEmail = user?.email ?? '';
    _originalMobile = user?.mobile ?? '';
    _usernameController.text = _originalUsername;
    _emailController.text = _originalEmail;
    _mobileController.text = _originalMobile;

    _usernameFocus.addListener(_onUsernameFocusChange);
    _emailFocus.addListener(_onEmailFocusChange);
    _mobileFocus.addListener(_onMobileFocusChange);
    _emailController.addListener(_onContactChanged);
    _mobileController.addListener(_onContactChanged);
  }

  @override
  void dispose() {
    _usernameFocus.removeListener(_onUsernameFocusChange);
    _emailFocus.removeListener(_onEmailFocusChange);
    _mobileFocus.removeListener(_onMobileFocusChange);
    _emailController.removeListener(_onContactChanged);
    _mobileController.removeListener(_onContactChanged);
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _mobileFocus.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onContactChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasContact {
    return _emailController.text.trim().isNotEmpty ||
        _mobileController.text.trim().isNotEmpty;
  }

  bool get _canSaveProfile =>
      _usernameAvailable &&
      _emailAvailable &&
      _mobileAvailable &&
      !_checkingUsername &&
      !_checkingEmail &&
      !_checkingMobile &&
      !_savingProfile;

  // --- Username availability ---

  void _invalidateUsernameCheck() {
    _usernameCheckGen++;
    setState(() {
      _usernameAvailable = false;
      _checkingUsername = false;
      _usernameStatus = null;
    });
  }

  void _onUsernameFocusChange() {
    if (_usernameFocus.hasFocus) {
      if (_usernameAvailable || _usernameStatus != null) {
        final raw = _usernameController.text.trim().toLowerCase();
        if (raw != _originalUsername.toLowerCase()) {
          _invalidateUsernameCheck();
        }
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
        _usernameStatus = 'invalid';
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
    if (raw.toLowerCase() == _originalUsername.toLowerCase()) {
      setState(() {
        _usernameAvailable = true;
        _checkingUsername = false;
        _usernameStatus = 'available';
      });
      return;
    }

    final gen = ++_usernameCheckGen;
    setState(() {
      _checkingUsername = true;
      _usernameAvailable = false;
      _usernameStatus = null;
    });

    try {
      final available = await ApiService.checkUsername(raw.toLowerCase());
      if (!mounted || gen != _usernameCheckGen) return;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = available;
        _usernameStatus = available ? 'available' : 'taken';
      });
    } catch (e) {
      if (!mounted || gen != _usernameCheckGen) return;
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

  // --- Email availability ---

  void _invalidateEmailCheck() {
    _emailCheckGen++;
    setState(() {
      _emailAvailable = false;
      _checkingEmail = false;
      _emailStatus = null;
    });
  }

  void _onEmailFocusChange() {
    if (_emailFocus.hasFocus) {
      if (_emailAvailable || _emailStatus != null) {
        final raw = _emailController.text.trim().toLowerCase();
        if (raw != _originalEmail.toLowerCase()) {
          _invalidateEmailCheck();
        }
      }
      return;
    }
    _checkEmailAvailability();
  }

  Future<void> _checkEmailAvailability() async {
    final raw = _emailController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _emailAvailable = true;
        _checkingEmail = false;
        _emailStatus = null;
      });
      return;
    }
    if (raw.toLowerCase() == _originalEmail.toLowerCase()) {
      setState(() {
        _emailAvailable = true;
        _checkingEmail = false;
        _emailStatus = 'available';
      });
      return;
    }

    final gen = ++_emailCheckGen;
    setState(() {
      _checkingEmail = true;
      _emailAvailable = false;
      _emailStatus = null;
    });

    try {
      final available = await ApiService.checkEmail(raw.toLowerCase());
      if (!mounted || gen != _emailCheckGen) return;
      setState(() {
        _checkingEmail = false;
        _emailAvailable = available;
        _emailStatus = available ? 'available' : 'taken';
      });
    } catch (e) {
      if (!mounted || gen != _emailCheckGen) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _checkingEmail = false;
        _emailAvailable = false;
        _emailStatus = 'error';
      });
      if (msg.toLowerCase().contains('too many')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  // --- Mobile availability ---

  void _invalidateMobileCheck() {
    _mobileCheckGen++;
    setState(() {
      _mobileAvailable = false;
      _checkingMobile = false;
      _mobileStatus = null;
    });
  }

  void _onMobileFocusChange() {
    if (_mobileFocus.hasFocus) {
      if (_mobileAvailable || _mobileStatus != null) {
        final raw = _normalizeMobileLocal(_mobileController.text);
        if (raw != _normalizeMobileLocal(_originalMobile)) {
          _invalidateMobileCheck();
        }
      }
      return;
    }
    _checkMobileAvailability();
  }

  String _normalizeMobileLocal(String s) {
    return s.trim().replaceAll(' ', '').replaceAll('-', '');
  }

  Future<void> _checkMobileAvailability() async {
    final raw = _normalizeMobileLocal(_mobileController.text);
    if (raw.isEmpty) {
      setState(() {
        _mobileAvailable = true;
        _checkingMobile = false;
        _mobileStatus = null;
      });
      return;
    }
    if (raw == _normalizeMobileLocal(_originalMobile)) {
      setState(() {
        _mobileAvailable = true;
        _checkingMobile = false;
        _mobileStatus = 'available';
      });
      return;
    }

    final gen = ++_mobileCheckGen;
    setState(() {
      _checkingMobile = true;
      _mobileAvailable = false;
      _mobileStatus = null;
    });

    try {
      final available = await ApiService.checkMobile(raw);
      if (!mounted || gen != _mobileCheckGen) return;
      setState(() {
        _checkingMobile = false;
        _mobileAvailable = available;
        _mobileStatus = available ? 'available' : 'taken';
      });
    } catch (e) {
      if (!mounted || gen != _mobileCheckGen) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _checkingMobile = false;
        _mobileAvailable = false;
        _mobileStatus = 'error';
      });
      if (msg.toLowerCase().contains('too many')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_canSaveProfile) return;
    if (!_profileFormKey.currentState!.validate()) return;

    setState(() => _savingProfile = true);
    final ok = await context.read<AuthProvider>().updateProfile(
          username: _usernameController.text.trim().toLowerCase(),
          email: _emailController.text.trim(),
          mobile: _mobileController.text.trim(),
        );
    if (!mounted) return;
    setState(() => _savingProfile = false);

    if (!ok) {
      final err = context.read<AuthProvider>().error ?? 'Failed to update profile';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    final user = context.read<AuthProvider>().user;
    _originalUsername = user?.username ?? '';
    _originalEmail = user?.email ?? '';
    _originalMobile = user?.mobile ?? '';
    setState(() {
      _usernameStatus = 'available';
      _emailStatus = _originalEmail.isEmpty ? null : 'available';
      _mobileStatus = _originalMobile.isEmpty ? null : 'available';
      _usernameAvailable = true;
      _emailAvailable = true;
      _mobileAvailable = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated')),
    );
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _savingPassword = true);
    final ok = await context.read<AuthProvider>().changePassword(
          currentPassword: _currentPasswordController.text,
          newPassword: _newPasswordController.text,
        );
    if (!mounted) return;
    setState(() => _savingPassword = false);

    if (!ok) {
      final err =
          context.read<AuthProvider>().error ?? 'Failed to change password';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password updated')),
    );
  }

  Widget _availabilityHelper({
    required bool checking,
    required String? status,
    required String availableLabel,
    required String takenLabel,
    String? defaultHint,
  }) {
    if (checking) {
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
    switch (status) {
      case 'available':
        return Text(
          availableLabel,
          style: TextStyle(color: Colors.green.shade700, fontSize: 12),
        );
      case 'taken':
        return Text(
          takenLabel,
          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
        );
      case 'invalid':
        return Text(
          defaultHint ?? 'Invalid value',
          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
        );
      case 'error':
        return Text(
          'Could not verify. Try again.',
          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
        );
      default:
        if (defaultHint == null) return const SizedBox.shrink();
        return Text(
          defaultHint,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle('Profile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: authAppBarActions(context),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Account details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 16),
                Form(
                  key: _profileFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _usernameController,
                        focusNode: _usernameFocus,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          final raw = _usernameController.text.trim();
                          if (raw.toLowerCase() ==
                              _originalUsername.toLowerCase()) {
                            setState(() {
                              _usernameAvailable = true;
                              _usernameStatus = 'available';
                              _checkingUsername = false;
                            });
                          } else {
                            _invalidateUsernameCheck();
                          }
                        },
                        validator: (v) {
                          final raw = (v ?? '').trim();
                          if (raw.isEmpty) return 'Required';
                          if (!_usernameFormat.hasMatch(raw)) {
                            return '3–64 characters: letters, numbers, underscores';
                          }
                          if (!_usernameAvailable) return 'Username is not available';
                          return null;
                        },
                      ),
                      const SizedBox(height: 6),
                      _availabilityHelper(
                        checking: _checkingUsername,
                        status: _usernameStatus,
                        availableLabel: 'Username available',
                        takenLabel: 'Username is taken',
                        defaultHint:
                            '3–64 characters: letters, numbers, and underscores',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        focusNode: _emailFocus,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          final raw = _emailController.text.trim();
                          if (raw.isEmpty ||
                              raw.toLowerCase() ==
                                  _originalEmail.toLowerCase()) {
                            setState(() {
                              _emailAvailable = true;
                              _emailStatus =
                                  raw.isEmpty ? null : 'available';
                              _checkingEmail = false;
                            });
                          } else {
                            _invalidateEmailCheck();
                          }
                        },
                        validator: (v) {
                          if (!_emailAvailable) return 'Email is not available';
                          return null;
                        },
                      ),
                      const SizedBox(height: 6),
                      _availabilityHelper(
                        checking: _checkingEmail,
                        status: _emailStatus,
                        availableLabel: 'Email available',
                        takenLabel: 'Email is already registered',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _mobileController,
                        focusNode: _mobileFocus,
                        decoration: const InputDecoration(
                          labelText: 'Phone number',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          final raw =
                              _normalizeMobileLocal(_mobileController.text);
                          if (raw.isEmpty ||
                              raw ==
                                  _normalizeMobileLocal(_originalMobile)) {
                            setState(() {
                              _mobileAvailable = true;
                              _mobileStatus =
                                  raw.isEmpty ? null : 'available';
                              _checkingMobile = false;
                            });
                          } else {
                            _invalidateMobileCheck();
                          }
                        },
                        validator: (v) {
                          if (!_mobileAvailable) {
                            return 'Phone number is not available';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 6),
                      _availabilityHelper(
                        checking: _checkingMobile,
                        status: _mobileStatus,
                        availableLabel: 'Phone number available',
                        takenLabel: 'Phone number is already registered',
                      ),
                      if (!_hasContact) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Text(
                            'Without email or phone, you cannot receive '
                            'notifications or recover your password via OTP.',
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _canSaveProfile ? _saveProfile : null,
                        child: _savingProfile
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save profile'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                const Divider(),
                const SizedBox(height: 24),
                Text(
                  'Change password',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 16),
                Form(
                  key: _passwordFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _currentPasswordController,
                        obscureText: _obscureCurrent,
                        decoration: InputDecoration(
                          labelText: 'Current password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureCurrent
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () => setState(
                              () => _obscureCurrent = !_obscureCurrent,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return 'Required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: _obscureNew,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureNew
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _obscureNew = !_obscureNew),
                          ),
                        ),
                        validator: (v) {
                          final raw = v ?? '';
                          if (raw.isEmpty) return 'Required';
                          if (raw.length < 6) {
                            return 'Must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if ((v ?? '') != _newPasswordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _savingPassword ? null : _changePassword,
                        child: _savingPassword
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Change password'),
                      ),
                    ],
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
