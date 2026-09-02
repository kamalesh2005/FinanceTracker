import 'package:flutter/material.dart';

Widget buildGoogleSignInButton({
  required BuildContext context,
  required String clientId,
  required ValueChanged<String> onIdToken,
  ValueChanged<String>? onError,
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
        'Google Sign-In is available in a web browser.',
        style: TextStyle(fontSize: 13, height: 1.35),
      ),
    ),
  );
}
