import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:web/web.dart' as web;

const _gisSrc = 'https://accounts.google.com/gsi/client';

Future<void>? _gisLoading;

Future<void> _ensureGisScript() {
  _gisLoading ??= _loadGisScript();
  return _gisLoading!;
}

Future<void> _loadGisScript() async {
  if (_googleAccountsId() != null) return;

  if (web.document.querySelector('script[src="$_gisSrc"]') == null) {
    final script = web.HTMLScriptElement()
      ..src = _gisSrc
      ..async = true;
    web.document.head!.append(script);
  }

  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (DateTime.now().isBefore(deadline)) {
    if (_googleAccountsId() != null) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Google Identity Services failed to load');
}

JSObject? _googleAccountsId() {
  final google = globalContext.getProperty('google'.toJS);
  if (google is! JSObject) return null;
  final accounts = google.getProperty('accounts'.toJS);
  if (accounts is! JSObject) return null;
  final id = accounts.getProperty('id'.toJS);
  if (id is! JSObject) return null;
  return id;
}

final List<ValueChanged<String>> _tokenListeners = [];
String? _initializedClientId;

void _pushTokenListener(ValueChanged<String> listener) {
  _tokenListeners.add(listener);
}

void _removeTokenListener(ValueChanged<String> listener) {
  _tokenListeners.remove(listener);
}

void _dispatchToken(String token) {
  if (_tokenListeners.isEmpty) return;
  _tokenListeners.last(token);
}

void _ensureInitialized(String clientId) {
  final id = _googleAccountsId();
  if (id == null) return;
  if (_initializedClientId == clientId) return;

  final config = JSObject();
  config.setProperty('client_id'.toJS, clientId.toJS);
  config.setProperty('ux_mode'.toJS, 'popup'.toJS);
  config.setProperty('auto_select'.toJS, false.toJS);
  config.setProperty('callback'.toJS, ((JSObject resp) {
    final cred = resp.getProperty('credential'.toJS)?.dartify();
    if (cred is String && cred.isNotEmpty) {
      _dispatchToken(cred);
    }
  }).toJS);
  id.callMethod('initialize'.toJS, config);
  _initializedClientId = clientId;
}

Widget buildGoogleSignInButton({
  required BuildContext context,
  required String clientId,
  required ValueChanged<String> onIdToken,
  ValueChanged<String>? onError,
}) {
  return _GoogleSignInOverlay(
    clientId: clientId,
    onIdToken: onIdToken,
    onError: onError,
  );
}

/// Renders GIS into a real `document.body` overlay (page origin), not a
/// srcdoc/platform-view iframe. Google OAuth rejects those with origin=null.
class _GoogleSignInOverlay extends StatefulWidget {
  const _GoogleSignInOverlay({
    required this.clientId,
    required this.onIdToken,
    this.onError,
  });

  final String clientId;
  final ValueChanged<String> onIdToken;
  final ValueChanged<String>? onError;

  @override
  State<_GoogleSignInOverlay> createState() => _GoogleSignInOverlayState();
}

class _GoogleSignInOverlayState extends State<_GoogleSignInOverlay> {
  final GlobalKey _anchorKey = GlobalKey();
  late final Zone _zone;
  late final web.HTMLDivElement _overlay;
  late final ValueChanged<String> _listener;
  bool _syncing = false;
  bool _ready = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _zone = Zone.current;
    _listener = _notifyToken;
    _overlay = web.HTMLDivElement()
      ..style.position = 'fixed'
      ..style.zIndex = '1000000'
      ..style.display = 'none'
      ..style.overflow = 'hidden'
      ..style.pointerEvents = 'auto';
    web.document.body?.append(_overlay);
    _pushTokenListener(_listener);
    _boot();
    _startSync();
  }

  @override
  void didUpdateWidget(covariant _GoogleSignInOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId) {
      _initializedClientId = null;
      _boot();
    }
  }

  @override
  void dispose() {
    _syncing = false;
    _removeTokenListener(_listener);
    try {
      _overlay.remove();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await _ensureGisScript();
      if (!mounted) return;
      _ensureInitialized(widget.clientId);
      _renderButton();
      setState(() {
        _ready = true;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _loadError = 'Google Sign-In failed to load';
      });
      widget.onError?.call('Google Sign-In failed to load');
    }
  }

  void _renderButton() {
    final id = _googleAccountsId();
    if (id == null) return;
    while (_overlay.firstChild != null) {
      _overlay.removeChild(_overlay.firstChild!);
    }
    final opts = JSObject();
    opts.setProperty('theme'.toJS, 'outline'.toJS);
    opts.setProperty('size'.toJS, 'large'.toJS);
    opts.setProperty('text'.toJS, 'signin_with'.toJS);
    opts.setProperty('shape'.toJS, 'rectangular'.toJS);
    opts.setProperty('width'.toJS, 320.toJS);
    id.callMethod('renderButton'.toJS, _overlay, opts);
  }

  void _startSync() {
    _syncing = true;
    void tick(Duration _) {
      if (!_syncing || !mounted) return;
      _syncPosition();
      WidgetsBinding.instance.addPostFrameCallback(tick);
    }

    WidgetsBinding.instance.addPostFrameCallback(tick);
  }

  void _syncPosition() {
    final route = ModalRoute.of(context);
    final onTop = route == null || route.isCurrent;
    if (!onTop || !_ready) {
      _overlay.style.display = 'none';
      return;
    }
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) {
      _overlay.style.display = 'none';
      return;
    }
    final offset = box.localToGlobal(Offset.zero);
    _overlay.style.display = 'flex';
    _overlay.style.justifyContent = 'center';
    _overlay.style.alignItems = 'center';
    _overlay.style.left = '${offset.dx}px';
    _overlay.style.top = '${offset.dy}px';
    _overlay.style.width = '${box.size.width}px';
    _overlay.style.height = '${box.size.height}px';
  }

  void _notifyToken(String token) {
    _zone.run(() {
      final binding = WidgetsBinding.instance;
      binding.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onIdToken(token);
      });
      binding.ensureVisualUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Text(
        _loadError!,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.red.shade700),
      );
    }
    return SizedBox(
      key: _anchorKey,
      height: 44,
      child: _ready
          ? null
          : const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
    );
  }
}
