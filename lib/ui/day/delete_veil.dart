import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const int kDeleteVeilRedArgb = 0x73FF8A80;
const int kDeleteVeilGreenArgb = 0x7381C784;

class DeleteVeil extends StatelessWidget {
  const DeleteVeil({
    super.key,
    required this.onDelete,
    required this.onCancel,
  });

  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDelete,
            child: const ColoredBox(
              key: Key('delete-veil-red'),
              color: Color(kDeleteVeilRedArgb),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: const ColoredBox(
              key: Key('delete-veil-green'),
              color: Color(kDeleteVeilGreenArgb),
            ),
          ),
        ),
      ],
    );
  }
}

class DayDeleteVeilStack extends StatelessWidget {
  const DayDeleteVeilStack({
    super.key,
    required this.child,
    required this.veilOpen,
    required this.onDelete,
    required this.onCancel,
  });

  final Widget child;
  final bool veilOpen;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (veilOpen)
          const SingleActivator(LogicalKeyboardKey.escape): onCancel,
      },
      child: Focus(
        autofocus: veilOpen,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(ignoring: veilOpen, child: child),
            if (veilOpen)
              Positioned.fill(
                child: DeleteVeil(onDelete: onDelete, onCancel: onCancel),
              ),
          ],
        ),
      ),
    );
  }
}
