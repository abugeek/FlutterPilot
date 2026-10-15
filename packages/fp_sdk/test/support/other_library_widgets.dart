import 'package:flutter/widgets.dart';

/// Stand-ins for the widgets of the separate material_ui package: classes
/// with Flutter's names and fields that are not Flutter's classes, so
/// `is Tooltip` and `is Slider` do not match them.
class Tooltip extends StatelessWidget {
  const Tooltip({super.key, this.message, required this.child});
  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class Slider extends StatelessWidget {
  const Slider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
  });
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (d) {
      // Same 24 px track padding as Flutter's slider.
      final width = context.size!.width - 48;
      final t = ((d.localPosition.dx - 24) / width).clamp(0.0, 1.0);
      onChanged(min + t * (max - min));
    },
    child: const SizedBox(width: 248, height: 48),
  );
}

class InputDecoration {
  const InputDecoration({this.labelText, this.hintText});
  final String? labelText;
  final String? hintText;
}

class TextField extends StatelessWidget {
  const TextField({super.key, required this.label, this.suffix});
  final String label;
  final Widget? suffix;

  InputDecoration get decoration => InputDecoration(labelText: label);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label),
      ?suffix,
      EditableText(
        controller: TextEditingController(),
        focusNode: FocusNode(),
        style: const TextStyle(),
        cursorColor: const Color(0xFF000000),
        backgroundCursorColor: const Color(0xFF000000),
      ),
    ],
  );
}
