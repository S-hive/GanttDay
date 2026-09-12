import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/time/wall_clock.dart';
import 'bar_time_label.dart';

/// Anchored "新任务" title prompt — sits under [anchorGlobal] like a sticky
/// card next to the dragged selection (not a centered AlertDialog).
Future<String?> showCreateTaskPopup({
  required BuildContext context,
  required Rect anchorGlobal,
  required WallMinutes start,
  required WallMinutes end,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.12),
    builder: (ctx) => _CreateTaskPopup(
      anchorGlobal: anchorGlobal,
      start: start,
      end: end,
    ),
  );
}

class _CreateTaskPopup extends StatefulWidget {
  const _CreateTaskPopup({
    required this.anchorGlobal,
    required this.start,
    required this.end,
  });

  final Rect anchorGlobal;
  final WallMinutes start;
  final WallMinutes end;

  @override
  State<_CreateTaskPopup> createState() => _CreateTaskPopupState();
}

class _CreateTaskPopupState extends State<_CreateTaskPopup> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    const popupW = 300.0;
    const gap = 8.0;
    const estimatedH = 168.0;
    final anchor = widget.anchorGlobal;

    var left = anchor.left;
    var top = anchor.bottom + gap;
    left = left.clamp(8.0, media.size.width - popupW - 8);
    if (top + estimatedH > media.size.height - 8) {
      top = anchor.top - estimatedH - gap;
    }
    top = top.clamp(8.0, media.size.height - estimatedH - 8);

    final bar = SizedBox(
      height: anchor.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
          border: Border.all(
            color: theme.colorScheme.primary,
            width: 1.5,
          ),
        ),
      ),
    );

    return Stack(
      children: [
        // Keep the dragged range visible while naming the task.
        Positioned(
          left: anchor.left,
          top: anchor.top,
          width: math.max(anchor.width, 2),
          height: anchor.height,
          child: IgnorePointer(child: bar),
        ),
        Positioned(
          left: left,
          top: top,
          width: popupW,
          child: Material(
            elevation: 10,
            shadowColor: Colors.black26,
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '新任务',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatBarTimeLabel(widget.start, widget.end),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '任务名',
                      isDense: true,
                    ),
                    onSubmitted: (v) => Navigator.of(context).pop(v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(_controller.text),
                        child: const Text('创建'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
