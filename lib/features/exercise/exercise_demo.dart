import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../data/models/exercise_type.dart';
import 'exercise_demo_painter.dart';

/// A small looping procedural animation demonstrating how to perform one
/// exercise — shown both on the exercise-pool selection list (alarm
/// creation) and on WorkoutScreen's pre-exercise intro. See
/// exercise_demo_painter.dart for how the motion itself is generated.
class ExerciseDemo extends StatefulWidget {
  const ExerciseDemo({
    super.key,
    required this.type,
    required this.size,
    required this.color,
  });

  final ExerciseType type;
  final double size;
  final Color color;

  @override
  State<ExerciseDemo> createState() => _ExerciseDemoState();
}

class _ExerciseDemoState extends State<ExerciseDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: AppConfig.exerciseDemoLoopMs),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: ExerciseDemoPainter(
              type: widget.type,
              t: _controller.value,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}
