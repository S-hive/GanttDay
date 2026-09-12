import 'package:flutter/material.dart';

/// Equal-thirds day/week/month switcher: icon-only, full-height hit targets.
class ViewNavBar extends StatelessWidget {
  const ViewNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const double height = 56;

  static const _destinations = <(IconData, String)>[
    (Icons.view_day_outlined, '日'),
    (Icons.view_week_outlined, '周'),
    (Icons.calendar_month_outlined, '月'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedColor = scheme.primary;
    final unselectedColor = scheme.onSurface.withValues(alpha: 0.45);

    return Material(
      color: Theme.of(context).navigationBarTheme.backgroundColor ??
          scheme.surfaceContainer,
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _destinations.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onDestinationSelected(i),
                  child: Semantics(
                    button: true,
                    selected: selectedIndex == i,
                    label: _destinations[i].$2,
                    child: Center(
                      child: Icon(
                        _destinations[i].$1,
                        color: selectedIndex == i
                            ? selectedColor
                            : unselectedColor,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
