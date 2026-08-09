import 'package:flutter/material.dart';

import '../../domain/gantt/color_palette.dart';

/// Palette swatches first; optional custom hue slider.
class HuePicker extends StatefulWidget {
  const HuePicker({
    super.key,
    required this.hue,
    required this.onChanged,
  });

  final int hue;
  final ValueChanged<int> onChanged;

  @override
  State<HuePicker> createState() => _HuePickerState();
}

class _HuePickerState extends State<HuePicker> {
  late bool _custom;

  @override
  void initState() {
    super.initState();
    _custom = paletteIndexForHue(widget.hue) == null;
  }

  @override
  void didUpdateWidget(HuePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hue != widget.hue && paletteIndexForHue(widget.hue) != null) {
      _custom = false;
    }
  }

  Color _preview(PaletteSwatch s) => Color(s.argb);

  Color _previewHue(int hue) {
    final swatch = swatchForHue(hue);
    if (swatch != null) return _preview(swatch);
    return HSLColor.fromAHSL(
            1, hue.toDouble(), kPalettePreviewSaturation, kPalettePreviewLightness)
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final selected = paletteIndexForHue(widget.hue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < kTaskColorPalette.length; i++)
              InkWell(
                onTap: () {
                  setState(() => _custom = false);
                  widget.onChanged(kTaskColorPalette[i].hue);
                },
                customBorder: const CircleBorder(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _preview(kTaskColorPalette[i]),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected == i && !_custom
                          ? Theme.of(context).colorScheme.primary
                          : Colors.black26,
                      width: selected == i && !_custom ? 2.5 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _custom = !_custom),
          child: Text(_custom ? '收起自定义' : '自定义…'),
        ),
        if (_custom) ...[
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _previewHue(widget.hue),
                radius: 14,
              ),
              Expanded(
                child: Slider(
                  value: widget.hue.toDouble().clamp(0, 359),
                  min: 0,
                  max: 359,
                  divisions: 359,
                  label: '${widget.hue}',
                  onChanged: (v) => widget.onChanged(v.round()),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
