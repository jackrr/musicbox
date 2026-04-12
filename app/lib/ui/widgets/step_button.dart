import 'package:flutter/material.dart';

/// Large step-sequencer button with active/inactive state and velocity display.
class StepButton extends StatelessWidget {
  final bool active;
  final bool isCurrentStep;
  final double velocity; // 0..1
  final Color activeColor;
  final VoidCallback onTap;
  final ValueChanged<double>? onVelocityChange;

  const StepButton({
    super.key,
    required this.active,
    required this.isCurrentStep,
    required this.onTap,
    this.velocity    = 0.8,
    this.activeColor = Colors.greenAccent,
    this.onVelocityChange,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? activeColor.withAlpha((velocity * 255).round().clamp(120, 255))
        : Colors.white10;
    final border = isCurrentStep
        ? Border.all(color: Colors.white, width: 2)
        : Border.all(color: Colors.white10, width: 1);

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onVelocityChange == null
          ? null
          : (_) {},
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: border,
        ),
      ),
    );
  }
}
