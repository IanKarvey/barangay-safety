import 'package:flutter/material.dart';

class AppAnimations {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 480);

  // Spring-based curves — feel physical, not robotic
  static const Curve spring = Curves.easeOutBack;
  static const Curve smooth = Curves.easeOutCubic;
  static const Curve snappy = Curves.easeOutQuart;

  // Index-based stagger delay — items enter sequentially, not all at once
  static Duration stagger(int index, {int base = 60, int step = 55}) =>
      Duration(milliseconds: base + (index * step).clamp(0, 500));
}
