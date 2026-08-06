import 'package:flutter/material.dart';

import 'turnstile_impl_stub.dart'
    if (dart.library.html) 'turnstile_impl_web.dart' as impl;

/// Imperative handle to reset the Turnstile challenge (tokens are single-use).
class TurnstileController {
  VoidCallback? _reset;

  void attachReset(VoidCallback reset) {
    _reset = reset;
  }

  void detachReset(VoidCallback reset) {
    if (identical(_reset, reset)) {
      _reset = null;
    }
  }

  void reset() => _reset?.call();
}

/// Cloudflare Turnstile managed widget (web). Non-web shows a short message.
class TurnstileWidget extends StatefulWidget {
  const TurnstileWidget({
    super.key,
    required this.siteKey,
    required this.onTokenChanged,
    this.controller,
  });

  final String siteKey;
  final ValueChanged<String?> onTokenChanged;
  final TurnstileController? controller;

  @override
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  @override
  Widget build(BuildContext context) {
    return impl.buildTurnstile(
      context: context,
      siteKey: widget.siteKey,
      onTokenChanged: widget.onTokenChanged,
      controller: widget.controller,
    );
  }
}
