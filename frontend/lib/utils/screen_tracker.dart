import 'package:flutter/material.dart';

/// Tracks the current screen name for implicit feedback context.
class ScreenTracker {
  ScreenTracker._();

  static String current = 'Unknown';

  static void update(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      current = trimmed;
    }
  }
}

/// Observes navigation and keeps [ScreenTracker.current] in sync.
class ScreenTrackerRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _sync(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _sync(previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _sync(newRoute);
    }
  }

  void _sync(Route<dynamic> route) {
    ScreenTracker.update(route.settings.name);
  }
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final ScreenTrackerRouteObserver screenTrackerRouteObserver =
    ScreenTrackerRouteObserver();

/// Derives a stable screen label from a widget type (e.g. StocksScreen → Stocks).
String appPageName(Widget page) {
  final type = page.runtimeType.toString();
  if (type.endsWith('Screen')) {
    return type.substring(0, type.length - 'Screen'.length);
  }
  return type;
}

/// MaterialPageRoute with [RouteSettings.name] for screen tracking.
Route<T> appPageRoute<T>(Widget page) {
  return MaterialPageRoute<T>(
    settings: RouteSettings(name: appPageName(page)),
    builder: (_) => page,
  );
}

/// Wraps a portal home screen so [ScreenTracker] knows the initial route.
class TrackedScreen extends StatefulWidget {
  final Widget child;

  const TrackedScreen({super.key, required this.child});

  @override
  State<TrackedScreen> createState() => _TrackedScreenState();
}

class _TrackedScreenState extends State<TrackedScreen> {
  @override
  void initState() {
    super.initState();
    ScreenTracker.update(appPageName(widget.child));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
