import 'dart:async';

import 'package:flutter/gestures.dart';

class DayBarTapClassifier {
  DayBarTapClassifier({
    required this.onSingleTap,
    required this.onDoubleTap,
    this.timeout = kDoubleTapTimeout,
  });

  final void Function(String taskId) onSingleTap;
  final void Function(String taskId) onDoubleTap;
  final Duration timeout;

  String? _downId;
  String? _waitingId;
  bool _slopped = false;
  Timer? _singleTimer;

  void down(String taskId) {
    _downId = taskId;
    _slopped = false;
  }

  void movedBeyondSlop() {
    _slopped = true;
    _downId = null;
    _waitingId = null;
    _singleTimer?.cancel();
    _singleTimer = null;
  }

  void up() {
    if (_slopped || _downId == null) {
      _downId = null;
      return;
    }
    final id = _downId!;
    _downId = null;
    if (_waitingId == id) {
      _singleTimer?.cancel();
      _singleTimer = null;
      _waitingId = null;
      onDoubleTap(id);
      return;
    }
    _singleTimer?.cancel();
    _waitingId = id;
    _singleTimer = Timer(timeout, () {
      _singleTimer = null;
      _waitingId = null;
      onSingleTap(id);
    });
  }

  void dispose() {
    _singleTimer?.cancel();
    _singleTimer = null;
  }
}
