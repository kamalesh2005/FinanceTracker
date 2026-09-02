import 'package:flutter/material.dart';

/// Pops to the current portal dashboard (the navigator's first route).
void goToPortalDashboard(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// AppBar title with Dhan Shanti logo and [label] text.
class AppBrandTitle extends StatelessWidget {
  const AppBrandTitle(
    this.label, {
    super.key,
    this.onLogoTap,
    this.logoTooltip,
    this.trailing,
  });

  final String label;
  final VoidCallback? onLogoTap;
  final String? logoTooltip;
  final Widget? trailing;

  static const String logoAsset = 'assets/brand/dhan_shanti_logo.png';

  @override
  Widget build(BuildContext context) {
    Widget logo = ClipOval(
      child: Image.asset(
        logoAsset,
        width: 28,
        height: 28,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
    logo = Tooltip(
      message: logoTooltip ?? 'Go to dashboard',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onLogoTap ?? () => goToPortalDashboard(context),
          child: logo,
        ),
      ),
    );
    return Row(
      children: [
        logo,
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.topCenter,
              child: trailing!,
            ),
          ),
        ],
      ],
    );
  }
}
