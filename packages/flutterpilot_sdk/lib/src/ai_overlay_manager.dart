import 'dart:async';
import 'package:flutter/material.dart';

/// Manages temporary visual ripples and action badges on screen when AI interacts.
class AiOverlayManager {
  static bool enabled = true;

  /// Displays an animated ripple effect and action badge at [position].
  static void showAction(Offset position, String label) {
    if (!enabled) return;

    try {
      final root = WidgetsBinding.instance.rootElement;
      if (root == null) return;

      OverlayState? overlayState;
      void findOverlay(Element element) {
        if (overlayState != null) return;
        if (element is StatefulElement && element.state is OverlayState) {
          overlayState = element.state as OverlayState;
          return;
        }
        element.visitChildren(findOverlay);
      }

      findOverlay(root);
      if (overlayState == null) return;

      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) {
          return Positioned(
            left: position.dx - 40,
            top: position.dy - 40,
            child: IgnorePointer(
              child: _AiRippleWidget(
                label: label,
              ),
            ),
          );
        },
      );

      overlayState!.insert(entry);

      Timer(const Duration(milliseconds: 700), () {
        entry.remove();
      });
    } catch (_) {
      // Best-effort visual indicator; should never interrupt core automation.
    }
  }
}

class _AiRippleWidget extends StatefulWidget {
  final String label;
  const _AiRippleWidget({required this.label});

  @override
  State<_AiRippleWidget> createState() => _AiRippleWidgetState();
}

class _AiRippleWidgetState extends State<_AiRippleWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _scaleAnimation = Tween<double>(begin: 0.4, end: 1.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _opacityAnimation = Tween<double>(begin: 0.9, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x4D6366F1),
                    border: Border.all(
                      color: const Color(0xFF6366F1),
                      width: 2.0,
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -32),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B4B),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4D000000),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '🤖 ${widget.label}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
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
