import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/gantt/argb_color.dart';

/// Opens a color dialog: SV square + hue slider on top, HEX field below.
/// Both paths update the same color. Returns ARGB or null if cancelled.
Future<int?> showArgbColorPicker(
  BuildContext context, {
  required int initialArgb,
}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _ColorPickerDialog(initialArgb: initialArgb),
  );
}

/// Hex input + tappable color chip; chip opens [showArgbColorPicker].
class ArgbColorField extends StatefulWidget {
  const ArgbColorField({
    super.key,
    required this.argb,
    required this.onChanged,
  });

  final int argb;
  final ValueChanged<int> onChanged;

  @override
  State<ArgbColorField> createState() => _ArgbColorFieldState();
}

class _ArgbColorFieldState extends State<ArgbColorField> {
  late TextEditingController _hexCtrl;
  late int _previewArgb;

  @override
  void initState() {
    super.initState();
    _previewArgb = widget.argb;
    _hexCtrl = TextEditingController(text: ArgbColor.toHex(widget.argb));
  }

  @override
  void didUpdateWidget(ArgbColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.argb != widget.argb && widget.argb != _previewArgb) {
      _previewArgb = widget.argb;
      _hexCtrl.text = ArgbColor.toHex(widget.argb);
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  Future<void> _openPicker() async {
    final result = await showArgbColorPicker(
      context,
      initialArgb: _previewArgb,
    );
    if (result == null) return;
    setState(() {
      _previewArgb = result;
      _hexCtrl.text = ArgbColor.toHex(result);
    });
    widget.onChanged(result);
  }

  void _onHexChanged(String raw) {
    final parsed = ArgbColor.parseHex(raw);
    if (parsed == null) return;
    setState(() => _previewArgb = parsed);
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: _openPicker,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(_previewArgb),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _hexCtrl,
            decoration: const InputDecoration(
              labelText: '颜色',
              hintText: '#RRGGBB',
            ),
            onChanged: _onHexChanged,
          ),
        ),
      ],
    );
  }
}

class ArgbColorPickerPanel extends StatefulWidget {
  const ArgbColorPickerPanel({
    super.key,
    required this.initialArgb,
    required this.onConfirm,
    required this.onCancel,
    this.onDelete,
    this.svSize = 240.0,
  });

  final int initialArgb;
  final ValueChanged<int> onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;
  final double svSize;

  @override
  State<ArgbColorPickerPanel> createState() => _ArgbColorPickerPanelState();
}

class _ArgbColorPickerPanelState extends State<ArgbColorPickerPanel> {
  late HSVColor _hsv;
  late TextEditingController _hexCtrl;
  late int _argb;

  @override
  void initState() {
    super.initState();
    _argb = widget.initialArgb;
    _hsv = HSVColor.fromColor(Color(_argb));
    _hexCtrl = TextEditingController(text: ArgbColor.toHex(_argb));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _applyHsv(HSVColor hsv) {
    final c = hsv.toColor();
    final argb = (0xFF << 24) |
        (((c.r * 255.0).round() & 0xFF) << 16) |
        (((c.g * 255.0).round() & 0xFF) << 8) |
        ((c.b * 255.0).round() & 0xFF);
    final hex = ArgbColor.toHex(argb);
    setState(() {
      _hsv = hsv;
      _argb = argb;
      if (_hexCtrl.text.toUpperCase() != hex) {
        _hexCtrl.value = TextEditingValue(
          text: hex,
          selection: TextSelection.collapsed(offset: hex.length),
        );
      }
    });
  }

  void _onHexChanged(String raw) {
    final parsed = ArgbColor.parseHex(raw);
    if (parsed == null) return;
    setState(() {
      _argb = parsed;
      _hsv = HSVColor.fromColor(Color(parsed));
    });
  }

  void _onSvLocal(Offset local) {
    final svSize = widget.svSize;
    final s = (local.dx / svSize).clamp(0.0, 1.0);
    final v = (1.0 - local.dy / svSize).clamp(0.0, 1.0);
    _applyHsv(_hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    final svSize = widget.svSize;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: svSize,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onPanDown: (d) => _onSvLocal(d.localPosition),
                onPanUpdate: (d) => _onSvLocal(d.localPosition),
                child: SizedBox(
                  width: svSize,
                  height: svSize,
                  child: CustomPaint(
                    painter: _SvSquarePainter(hue: _hsv.hue),
                    child: Stack(
                      children: [
                        Positioned(
                          left: _hsv.saturation * svSize - 8,
                          top: (1 - _hsv.value) * svSize - 8,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(_argb),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(blurRadius: 2, color: Colors.black38),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(_argb),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 24,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 10,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: const SizedBox(
                                height: 12,
                                width: double.infinity,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFFF0000),
                                        Color(0xFFFFFF00),
                                        Color(0xFF00FF00),
                                        Color(0xFF00FFFF),
                                        Color(0xFF0000FF),
                                        Color(0xFFFF00FF),
                                        Color(0xFFFF0000),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Slider(
                              value: _hsv.hue.clamp(0, 359.9),
                              min: 0,
                              max: 359.9,
                              onChanged: (h) => _applyHsv(_hsv.withHue(h)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hexCtrl,
                decoration: const InputDecoration(
                  labelText: 'HEX',
                  hintText: '#RRGGBB',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[#a-fA-F0-9]')),
                  LengthLimitingTextInputFormatter(7),
                ],
                onChanged: _onHexChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (widget.onDelete != null)
              TextButton(
                onPressed: widget.onDelete,
                child: const Text('删除'),
              ),
            const Spacer(),
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => widget.onConfirm(_argb),
              child: const Text('确定'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorPickerDialog extends StatelessWidget {
  const _ColorPickerDialog({required this.initialArgb});

  final int initialArgb;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      content: ArgbColorPickerPanel(
        initialArgb: initialArgb,
        onConfirm: (argb) => Navigator.pop(context, argb),
        onCancel: () => Navigator.pop(context),
      ),
    );
  }
}

class _SvSquarePainter extends CustomPainter {
  _SvSquarePainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final huePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white,
          HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, huePaint);

    final blackPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, blackPaint);
  }

  @override
  bool shouldRepaint(_SvSquarePainter oldDelegate) => oldDelegate.hue != hue;
}
