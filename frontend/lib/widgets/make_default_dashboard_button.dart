import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../learner/learner_theme.dart';
import '../freedom/freedom_theme.dart';

class MakeDefaultDashboardButton extends StatefulWidget {
  final String portal;

  const MakeDefaultDashboardButton({super.key, required this.portal});

  @override
  State<MakeDefaultDashboardButton> createState() =>
      _MakeDefaultDashboardButtonState();
}

class _MakeDefaultDashboardButtonState
    extends State<MakeDefaultDashboardButton> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isDefaultPortal(widget.portal)) {
      return const SizedBox.shrink();
    }
    final onBar = Theme.of(context).appBarTheme.foregroundColor;
    return Tooltip(
      message: 'Make this your default dashboard',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: _saving ? null : _save,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: _saving
                ? const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Make default',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: onBar,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.setDefaultPortal(widget.portal);
    if (!mounted) return;
    setState(() => _saving = false);
    final name = widget.portal == AppPortal.learner
        ? flexStreetName
        : widget.portal == AppPortal.freedom
            ? horizonName
            : 'DhanShanti Portal';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '$name is now your default dashboard'
              : (auth.error ?? 'Could not save default dashboard'),
        ),
      ),
    );
  }
}
