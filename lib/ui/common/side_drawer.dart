import 'dart:ui';

import 'package:flutter/material.dart';

const double kSideDrawerMinWidth = 360;
const double kSideDrawerMaxWidth = 480;
const double kSideDrawerWidthFraction = 0.4;

double sideDrawerWidthFor(double screenWidth) =>
    (screenWidth * kSideDrawerWidthFraction)
        .clamp(kSideDrawerMinWidth, kSideDrawerMaxWidth);

/// Right-side panel with blurred scrim.
/// Barrier tap / system back pops (task form intercepts to save-then-close).
Future<T?> showSideDrawer<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // Nearly clear so hits still register; visual blur is painted below.
    barrierColor: Colors.black.withValues(alpha: 0.01),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      final width = sideDrawerWidthFor(MediaQuery.sizeOf(ctx).width);
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Theme.of(ctx).colorScheme.surface,
          elevation: 8,
          borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: builder(ctx),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: FadeTransition(
                opacity: curved,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        ],
      );
    },
  );
}
