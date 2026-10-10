import 'dart:math';
import 'package:flutter/material.dart';

class Loading extends StatelessWidget {
  const Loading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: ShapeShifterLoader(),
    );
  }
}

class ShapeShifterLoader extends StatefulWidget {
  final double size;
  const ShapeShifterLoader({super.key, this.size = 42});

  @override
  State<ShapeShifterLoader> createState() => _ShapeShifterLoaderState();
}

class _ShapeShifterLoaderState extends State<ShapeShifterLoader>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _morphController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _morphController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: Listenable.merge(
          [_rotationController, _morphController, _pulseController]),
      builder: (context, child) {
        return SizedBox(
          width: widget.size * 1.3,
          height: widget.size * 1.3,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Outer dynamic glow
              Container(
                width: widget.size * (1.1 + (_pulseController.value * 0.2)),
                height: widget.size * (1.1 + (_pulseController.value * 0.2)),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.15),
                      blurRadius: 20,
                      spreadRadius: 5 * _pulseController.value,
                    ),
                    BoxShadow(
                      color: cs.tertiary.withValues(alpha: 0.1),
                      blurRadius: 15,
                      spreadRadius: 2 * _pulseController.value,
                    ),
                  ],
                ),
              ),
              // The Shape-Shifter
              Transform.rotate(
                angle: _rotationController.value * 2 * pi,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      widget.size * (0.1 + (_morphController.value * 0.4)),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary,
                        cs.tertiary,
                        cs.secondary,
                      ],
                      stops: [
                        0.0,
                        0.5 * _morphController.value,
                        1.0,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
