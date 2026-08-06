import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:web/web.dart' as web;

import 'turnstile_widget.dart';

Widget buildTurnstile({
  required BuildContext context,
  required String siteKey,
  required ValueChanged<String?> onTokenChanged,
  TurnstileController? controller,
}) {
  return _TurnstileIFrame(
    siteKey: siteKey,
    onTokenChanged: onTokenChanged,
    controller: controller,
  );
}

/// Embeds Turnstile in a same-origin iframe via srcdoc so the official
/// script + callbacks run in a normal browser document (more reliable than
/// rendering directly into a Flutter platform view).
class _TurnstileIFrame extends StatefulWidget {
  const _TurnstileIFrame({
    required this.siteKey,
    required this.onTokenChanged,
    this.controller,
  });

  final String siteKey;
  final ValueChanged<String?> onTokenChanged;
  final TurnstileController? controller;

  @override
  State<_TurnstileIFrame> createState() => _TurnstileIFrameState();
}

class _TurnstileIFrameState extends State<_TurnstileIFrame> {
  late final String _viewType;
  late final String _msgType;
  late final web.HTMLIFrameElement _iframe;
  late final JSFunction _messageHandler;
  late final VoidCallback _resetCb;

  @override
  void initState() {
    super.initState();
    _msgType = 'ft-turnstile-${identityHashCode(this)}';
    _viewType = '$_msgType-view';
    _resetCb = _reloadIFrame;
    widget.controller?.attachReset(_resetCb);

    _iframe = web.HTMLIFrameElement()
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '70px'
      ..setAttribute('scrolling', 'no');

    _messageHandler = ((web.MessageEvent event) {
      final raw = event.data.dartify()?.toString() ?? '';
      // format: <msgType>|<event>|<token?>
      final parts = raw.split('|');
      if (parts.length < 2 || parts[0] != _msgType) return;
      final kind = parts[1];
      if (kind == 'token' && parts.length >= 3) {
        final token = parts.sublist(2).join('|');
        _notifyToken(token.isEmpty ? null : token);
      } else if (kind == 'expired' || kind == 'error' || kind == 'reset') {
        _notifyToken(null);
      }
    }).toJS;

    web.window.addEventListener('message', _messageHandler);
    _reloadIFrame();

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return _iframe;
    });
  }

  @override
  void didUpdateWidget(covariant _TurnstileIFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detachReset(_resetCb);
      widget.controller?.attachReset(_resetCb);
    }
    if (oldWidget.siteKey != widget.siteKey) {
      _reloadIFrame();
    }
  }

  @override
  void dispose() {
    widget.controller?.detachReset(_resetCb);
    web.window.removeEventListener('message', _messageHandler);
    super.dispose();
  }

  /// Callbacks can land while the parent is mid-build (initState, reset from a
  /// build-triggered path), so defer to the next frame in those phases.
  void _notifyToken(String? token) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringBuild = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (duringBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onTokenChanged(token);
      });
      return;
    }
    widget.onTokenChanged(token);
  }

  void _reloadIFrame() {
    _notifyToken(null);
    final sk = widget.siteKey
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"');
    final mt = _msgType;
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    html, body { margin: 0; padding: 0; background: transparent; }
    #wrap { display: flex; justify-content: center; }
  </style>
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer></script>
</head>
<body>
  <div id="wrap"><div id="cf-turnstile" class="cf-turnstile" data-action="turnstile-spin-v2"></div></div>
  <script>
    const MSG = "$mt";
    function post(kind, token) {
      const payload = token ? (MSG + "|" + kind + "|" + token) : (MSG + "|" + kind);
      parent.postMessage(payload, "*");
    }
    function boot() {
      if (!window.turnstile) { setTimeout(boot, 50); return; }
      turnstile.render("#cf-turnstile", {
        sitekey: "$sk",
        theme: "light",
        action: "turnstile-spin-v2",
        callback: function (token) { post("token", token); },
        "expired-callback": function () { post("expired"); },
        "error-callback": function () { post("error"); }
      });
    }
    boot();
  </script>
</body>
</html>
''';
    _iframe.setAttribute('srcdoc', html);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
