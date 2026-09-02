import 'package:flutter/material.dart';

import 'google_sign_in_impl_stub.dart'
    if (dart.library.html) 'google_sign_in_impl_web.dart' as impl;

/// Official Google Identity Services button (web). Non-web shows a short note.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.clientId,
    required this.onIdToken,
    this.onError,
  });

  final String clientId;
  final ValueChanged<String> onIdToken;
  final ValueChanged<String>? onError;

  @override
  Widget build(BuildContext context) {
    return impl.buildGoogleSignInButton(
      context: context,
      clientId: clientId,
      onIdToken: onIdToken,
      onError: onError,
    );
  }
}
