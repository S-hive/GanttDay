import 'package:flutter/material.dart' hide ColorSwatch;

import '../../domain/models/color_swatch.dart';

/// Circular swatch grid; selection reports swatch id (no custom hue slider).
class SwatchPicker extends StatelessWidget {
  const SwatchPicker({
    super.key,
    required this.swatches,
    required this.swatchId,
    required this.onChanged,
  });

  final List<ColorSwatch> swatches;
  final String swatchId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final sorted = [...swatches]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in sorted)
          InkWell(
            onTap: () => onChanged(s.id),
            customBorder: const CircleBorder(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(s.argb),
                shape: BoxShape.circle,
                border: Border.all(
                  color: s.id == swatchId
                      ? Theme.of(context).colorScheme.primary
                      : Colors.black26,
                  width: s.id == swatchId ? 2.5 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
