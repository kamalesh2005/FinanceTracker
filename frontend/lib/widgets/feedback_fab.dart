import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/screen_tracker.dart';

/// Opens the feedback form on the app [Navigator].
///
/// No modal dimmer: the FAB sits in [MaterialApp.builder] above the navigator,
/// and a barrier/`Tooltip` overlay from that context paints a full-screen grey
/// sheet. Form opens on click only, with a transparent dismiss region.
Future<void> showFeedbackDialog(
  BuildContext context, {
  String? screenName,
}) async {
  final nav = rootNavigatorKey.currentState;
  final navContext = nav?.context ?? context;
  final controller = TextEditingController();
  var submitting = false;

  try {
    await showDialog<void>(
      context: navContext,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              backgroundColor: scheme.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 12,
              shadowColor: Colors.black38,
              title: Text(
                'Send feedback',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Your feedback',
                    hintText: 'Describe the issue or suggestion…',
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  ),
                  maxLines: 5,
                  minLines: 3,
                  textInputAction: TextInputAction.newline,
                  enabled: !submitting,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final message = controller.text.trim();
                          if (message.isEmpty) {
                            ScaffoldMessenger.of(navContext).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter feedback'),
                              ),
                            );
                            return;
                          }
                          setState(() => submitting = true);
                          try {
                            await ApiService.submitFeedback(
                              message: message,
                              screenName:
                                  screenName ?? ScreenTracker.current,
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (!navContext.mounted) return;
                            ScaffoldMessenger.of(navContext).showSnackBar(
                              const SnackBar(
                                content: Text('Feedback submitted'),
                              ),
                            );
                          } catch (e) {
                            if (!ctx.mounted) return;
                            setState(() => submitting = false);
                            ScaffoldMessenger.of(navContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceFirst('Exception: ', ''),
                                ),
                              ),
                            );
                          }
                        },
                  child: submitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

/// Thin edge tab on the right side of the screen (avoids covering page content).
///
/// No [Tooltip]: hover tooltips from this overlay context can paint a full-screen
/// grey sheet on Flutter web.
class FeedbackFab extends StatelessWidget {
  const FeedbackFab({super.key});

  static const Color _fill = Color(0xFF0F5C56);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _fill,
      elevation: 3,
      shadowColor: Colors.black38,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(8),
        bottomLeft: Radius.circular(8),
      ),
      child: InkWell(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        ),
        onTap: () => showFeedbackDialog(context),
        child: const Padding(
          // Narrow strip along the right edge; label runs vertically.
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(
              'Feedback',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
