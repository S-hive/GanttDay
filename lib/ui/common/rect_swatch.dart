import 'package:flutter/material.dart';

class RectSwatch extends StatelessWidget {
  const RectSwatch({
    super.key,
    required this.argb,
    this.selected = false,
    this.onTap,
  });

  static const double width = 60;
  static const double height = 30;

  final int argb;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color(argb),
        borderRadius: BorderRadius.zero,
      ),
    );
    final child =
        onTap == null ? box : GestureDetector(onTap: onTap, child: box);
    return Semantics(selected: selected, child: child);
  }
}
