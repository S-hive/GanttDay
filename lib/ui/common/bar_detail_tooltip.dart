import 'package:flutter/material.dart';

import '../../domain/time/wall_clock.dart';
import '../day/bar_time_label.dart';

/// Desktop hover detail for week & month bars.
///
/// Intentionally avoids Material [Tooltip]: on Windows, many Tooltips inside a
/// scrollable tree corrupt the accessibility bridge (AXTree "will not be in
/// the tree" spam). A single OverlayEntry has no traversal grafting.
class BarDetailTooltip extends StatefulWidget {
  const BarDetailTooltip({
    super.key,
    required this.title,
    required this.start,
    required this.end,
    this.focusDay,
    required this.child,
  });

  final String title;
  final WallMinutes start;
  final WallMinutes end;
  final DateTime? focusDay;
  final Widget child;

  @override
  State<BarDetailTooltip> createState() => _BarDetailTooltipState();
}

class _BarDetailTooltipState extends State<BarDetailTooltip> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _hovering = false;

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _scheduleShow() {
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || !_hovering || _entry != null) return;
      _show();
    });
  }

  void _show() {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final detail = formatBarHoverDetail(
      title: widget.title,
      start: widget.start,
      end: widget.end,
      focusDay: widget.focusDay,
    );
    final lines = detail.split('\n');
    final scheme = Theme.of(context).colorScheme;

    _entry = OverlayEntry(
      builder: (context) => UnconstrainedBox(
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Material(
                elevation: 6,
                color: scheme.inverseSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: scheme.primary.withValues(alpha: 0.55),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: lines.first,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: scheme.onInverseSurface,
                              height: 1.3,
                            ),
                          ),
                          if (lines.length > 1)
                            TextSpan(
                              text: '\n${lines.sublist(1).join('\n')}',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                                color: scheme.onInverseSurface
                                    .withValues(alpha: 0.9),
                                height: 1.35,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) {
          _hovering = true;
          _scheduleShow();
        },
        onExit: (_) {
          _hovering = false;
          _removeEntry();
        },
        child: widget.child,
      ),
    );
  }
}
