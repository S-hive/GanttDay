/// Pixel gap between vertically adjacent week task bars (shared by abutting
/// ends: each bar insets by half).
const double weekVerticalBarGap = 3;

typedef WeekBarVerticalRect = ({double top, double height});

/// Maps day-fraction geometry to painted bar top/height with uniform vertical
/// inset. Does not change schedule semantics — only pixels.
WeekBarVerticalRect weekBarVerticalRect({
  required double topFrac,
  required double heightFrac,
  required double dayHeight,
  double minHeight = 18,
  double verticalBarGap = weekVerticalBarGap,
}) {
  final top = topFrac * dayHeight + verticalBarGap / 2;
  var height = heightFrac * dayHeight - verticalBarGap;
  if (height < minHeight) height = minHeight;
  return (top: top, height: height);
}
