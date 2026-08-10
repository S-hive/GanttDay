import 'dart:math' as math;

import 'package:flutter/material.dart' hide ColorSwatch;
import 'package:uuid/uuid.dart';

import '../../domain/gantt/swatch_resolve.dart';
import '../../domain/models/color_swatch.dart';
import '../common/argb_color_field.dart';

class SwatchInlineHost extends StatefulWidget {
  const SwatchInlineHost({
    super.key,
    required this.swatches,
    required this.defaultArgb,
    required this.onUpsert,
    required this.onSetDefault,
    required this.onDelete,
  });

  final List<ColorSwatch> swatches;
  final int defaultArgb;
  final Future<void> Function(ColorSwatch swatch) onUpsert;
  final Future<void> Function(ColorSwatch swatch) onSetDefault;
  final Future<void> Function(ColorSwatch swatch) onDelete;

  @override
  State<SwatchInlineHost> createState() => _SwatchInlineHostState();
}

class _SwatchInlineHostState extends State<SwatchInlineHost> {
  /// null = closed; `'create'` = new swatch; otherwise editing swatch id.
  String? _openTarget;
  Key _pickerKey = UniqueKey();
  bool _saving = false;

  bool get _isCreateOpen => _openTarget == 'create';

  ColorSwatch? get _editingSwatch {
    if (_openTarget == null || _openTarget == 'create') return null;
    for (final s in widget.swatches) {
      if (s.id == _openTarget) return s;
    }
    return null;
  }

  void _close() => setState(() => _openTarget = null);

  void _openCreate() {
    setState(() {
      if (_isCreateOpen) {
        _openTarget = null;
      } else {
        _openTarget = 'create';
        _pickerKey = UniqueKey();
      }
    });
  }

  void _openEdit(String id) {
    setState(() {
      if (_openTarget == id) {
        _openTarget = null;
      } else {
        _openTarget = id;
        _pickerKey = UniqueKey();
      }
    });
  }

  int get _initialArgb {
    if (_isCreateOpen) return widget.defaultArgb;
    return _editingSwatch?.argb ?? widget.defaultArgb;
  }

  Future<void> _onConfirm(int argb) async {
    if (_saving) return;

    final ColorSwatch swatch;
    if (_isCreateOpen) {
      final maxSort = widget.swatches.isEmpty
          ? -1
          : widget.swatches.map((s) => s.sortOrder).reduce(math.max);
      swatch = colorSwatchFromArgb(
        id: const Uuid().v4(),
        name: '',
        argb: argb,
        sortOrder: maxSort + 1,
        isDefault: false,
      );
    } else {
      final existing = _editingSwatch;
      if (existing == null) {
        _close();
        return;
      }
      swatch = colorSwatchFromArgb(
        id: existing.id,
        name: existing.name,
        argb: argb,
        sortOrder: existing.sortOrder,
        isDefault: existing.isDefault,
        slate: existing.slate,
      );
    }
    setState(() => _saving = true);
    try {
      await widget.onUpsert(swatch);
      if (mounted) _close();
    } catch (_) {
      // upsert failed; keep panel open for retry
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = widget.swatches.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('色卡', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: _openCreate,
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in widget.swatches)
              _SwatchChip(
                key: ValueKey('swatch-${s.id}'),
                argb: s.argb,
                isDefault: s.isDefault,
                isEditing: _openTarget == s.id,
                onTap: () => _openEdit(s.id),
              ),
          ],
        ),
        if (_openTarget != null) ...[
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final svSize = constraints.maxWidth.clamp(120.0, 240.0);
              return ArgbColorPickerPanel(
                key: _pickerKey,
                initialArgb: _initialArgb,
                svSize: svSize,
                onConfirm: _onConfirm,
                onCancel: _close,
                onDelete: (!_isCreateOpen &&
                        canDelete &&
                        _editingSwatch != null)
                    ? () async {
                        final swatch = _editingSwatch!;
                        await widget.onDelete(swatch);
                        if (mounted &&
                            !widget.swatches.any((s) => s.id == swatch.id)) {
                          _close();
                        }
                      }
                    : null,
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Nameless circular swatch. Tap = edit color.
class _SwatchChip extends StatelessWidget {
  const _SwatchChip({
    super.key,
    required this.argb,
    required this.isDefault,
    required this.isEditing,
    required this.onTap,
  });

  final int argb;
  final bool isDefault;
  final bool isEditing;
  final VoidCallback onTap;

  Color _borderColor(BuildContext context) {
    if (isEditing) return Theme.of(context).colorScheme.primary;
    if (isDefault) return const Color(0xFFE53935);
    return Colors.black26;
  }

  double get _borderWidth => (isEditing || isDefault) ? 2.5 : 1;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isDefault ? '默认色卡' : '点击改色',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(argb),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _borderColor(context),
                  width: _borderWidth,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
