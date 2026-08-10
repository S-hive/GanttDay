import 'package:flutter/material.dart';

import '../../domain/gantt/argb_color.dart';

/// Hex input + tappable color chip; chip opens an HSL picker dialog (Flutter stand-in for system picker).
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
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(initialArgb: _previewArgb),
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

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initialArgb});

  final int initialArgb;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _lightness;

  @override
  void initState() {
    super.initState();
    final hsl = ArgbColor.toHsl(widget.initialArgb);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
  }

  int get _currentArgb =>
      ArgbColor.fromHsl(_hue, _saturation, _lightness);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择颜色'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                height: 80,
                decoration: BoxDecoration(
                  color: Color(_currentArgb),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
              ),
              const SizedBox(height: 16),
              Text('色相', style: Theme.of(context).textTheme.labelMedium),
              Slider(
                value: _hue.clamp(0, 360),
                min: 0,
                max: 360,
                divisions: 360,
                label: '${_hue.round()}',
                onChanged: (v) => setState(() => _hue = v),
              ),
              Text('饱和度', style: Theme.of(context).textTheme.labelMedium),
              Slider(
                value: _saturation.clamp(0.0, 1.0),
                min: 0,
                max: 1,
                onChanged: (v) => setState(() => _saturation = v),
              ),
              Text('亮度', style: Theme.of(context).textTheme.labelMedium),
              Slider(
                value: _lightness.clamp(0.0, 1.0),
                min: 0,
                max: 1,
                onChanged: (v) => setState(() => _lightness = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _currentArgb),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
