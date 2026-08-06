import 'package:flutter/material.dart';

import 'turnstile_widget.dart';

Widget buildTurnstile({
  required BuildContext context,
  required String siteKey,
  required ValueChanged<String?> onTokenChanged,
  TurnstileController? controller,
}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      border: Border.all(color: Colors.grey.shade400),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Padding(
      padding: EdgeInsets.all(12),
      child: Text(
        'Please open this app in a web browser to complete registration.',
        style: TextStyle(fontSize: 13, height: 1.35),
      ),
    ),
  );
}
