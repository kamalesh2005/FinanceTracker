import 'package:flutter/material.dart';

/// Pops to the current portal dashboard (the navigator's first route).
void goToPortalDashboard(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// Circular brand mark that stays readable on light and dark app bars.
class BrandLogoMark extends StatelessWidget {
  const BrandLogoMark({
    super.key,
    required this.asset,
    this.size = 32,
  });

  final String asset;
  final double size;

  static const Color _plate = Color(0xFFFFF8E7);
  static const Color _rim = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final inner = size - 4;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _plate,
          border: Border.all(color: _rim, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: ClipOval(
          child: Image.asset(
            asset,
            width: inner,
            height: inner,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

/// AppBar title with Dhan Shanti logo and [label] text.
class AppBrandTitle extends StatelessWidget {
  const AppBrandTitle(
    this.label, {
    super.key,
    this.subtitle,
    this.onLogoTap,
    this.logoTooltip,
    this.trailing,
    this.logoAsset = dhanShantiLogoAsset,
  });

  final String label;
  final String? subtitle;
  final VoidCallback? onLogoTap;
  final String? logoTooltip;
  final Widget? trailing;
  final String logoAsset;

  static const String dhanShantiLogoAsset =
      'assets/brand/dhan_shanti_logo.png';

  static const double logoSize = 32;

  @override
  Widget build(BuildContext context) {
    Widget logo = BrandLogoMark(asset: logoAsset, size: logoSize);
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
          child: _titleText(context),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          SizedBox(
            height: logoSize,
            child: Align(
              alignment: Alignment.topCenter,
              child: trailing!,
            ),
          ),
        ],
      ],
    );
  }

  Widget _titleText(BuildContext context) {
    final title = Text(
      label,
      overflow: TextOverflow.ellipsis,
    );
    final gloss = subtitle?.trim();
    if (gloss == null || gloss.isEmpty) return title;

    final base = DefaultTextStyle.of(context).style;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 0,
      children: [
        title,
        Text(
          gloss,
          style: base.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: (base.color ?? Colors.white).withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }
}
