// lib/core/extensions.dart

import 'package:flutter/material.dart';

extension DurationFormatting on Duration {
  /// Returns "MM:SS" or "Overtime" when duration is zero.
  String toCountdownString() {
    if (inSeconds <= 0) return 'Overtime';
    final m = inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

extension ColorWithAlpha on Color {
  /// Convenience wrapper for withValues(alpha:) — matches withOpacity semantics.
  Color withAlphaRatio(double opacity) =>
      withValues(alpha: opacity.clamp(0.0, 1.0));
}

extension IterableSafeFirst<T> on Iterable<T> {
  /// Returns the first element matching [test], or null if none found.
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
