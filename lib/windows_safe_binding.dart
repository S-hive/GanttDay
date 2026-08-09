import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Windows [AccessibilityBridge] corrupts easily (AXTree "will not be in the
/// tree") and stays broken across hot restart. This binding refuses to keep
/// semantics enabled on Windows so the engine stops receiving updates.
class WindowsSafeWidgetsBinding extends WidgetsFlutterBinding {
  static WindowsSafeWidgetsBinding? _binding;

  static WidgetsBinding ensureInitialized() {
    return _binding ?? WindowsSafeWidgetsBinding();
  }

  SemanticsHandle? _platformSemanticsHandle;

  @override
  SemanticsHandle ensureSemantics() {
    final handle = super.ensureSemantics();
    if (Platform.isWindows) {
      _platformSemanticsHandle ??= handle;
    }
    return handle;
  }

  @override
  void initInstances() {
    super.initInstances();
    _binding = this;
    if (!Platform.isWindows) return;

    // Drop the handle SemanticsBinding took for Windows UIA so
    // [semanticsEnabled] becomes false and no SemanticsOwner is created.
    _platformSemanticsHandle?.dispose();
    _platformSemanticsHandle = null;

    // Ignore later platform enable/disable requests (would otherwise
    // double-dispose the dangling handle pointer inside SemanticsBinding).
    platformDispatcher.onSemanticsEnabledChanged = () {};
    platformDispatcher.setSemanticsTreeEnabled(false);
  }
}
