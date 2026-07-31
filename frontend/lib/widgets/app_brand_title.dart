import 'package:flutter/material.dart';

/// AppBar title with Dhan Shanti logo and [label] text.
class AppBrandTitle extends StatelessWidget {
  const AppBrandTitle(this.label, {super.key});

  final String label;

  static const String logoAsset = 'assets/brand/dhan_shanti_logo.png';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipOval(
          child: Image.asset(
            logoAsset,
            width: 28,
            height: 28,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
