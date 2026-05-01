import 'dart:math';

import 'package:flutter/material.dart';

class ScreenShake extends StatefulWidget {
  const ScreenShake({super.key, required this.controller, required this.child});

  final ShakeController controller;
  final Widget child;

  @override
  State<ScreenShake> createState() => _ScreenShakeState();
}

class _ScreenShakeState extends State<ScreenShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    widget.controller._attach(_trigger);
  }

  void _trigger() {
    _ctrl
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    widget.controller._detach();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (final BuildContext context, final Widget? child) {
        if (_ctrl.value == 0) return child!;
        final double decay = 1 - _ctrl.value;
        final double mag = 14 * decay;
        final double dx = (_rng.nextDouble() - 0.5) * mag;
        final double dy = (_rng.nextDouble() - 0.5) * mag;
        return Transform.translate(offset: Offset(dx, dy), child: child);
      },
      child: widget.child,
    );
  }
}

class ShakeController {
  void Function()? _trigger;
  void _attach(final void Function() fn) => _trigger = fn;
  void _detach() => _trigger = null;
  void shake() => _trigger?.call();
}
