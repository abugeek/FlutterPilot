import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'source_locator.dart';

/// "Why is this widget this size?" (ROADMAP §5.4): the constraints each
/// render box got and the size it chose, from a widget up its ancestors,
/// and what that means (a Row that overflows and which children fill it,
/// a width of 0 and which ancestor passed it down).
class LayoutExplorer {
  /// Boxes listed, target first.
  static const int maxBoxes = 12;

  /// Layout of [element]'s render box and its ancestors, plus issues found.
  static Map<String, dynamic> describe(Element element) {
    final start = _renderBoxOf(element);
    if (start == null) {
      return {
        'issues': [
          '${element.widget.runtimeType} has no laid-out box (it is off '
              'screen, not laid out yet, or not a box widget like a sliver).',
        ],
      };
    }

    final chain = <RenderBox>[];
    for (RenderObject? ro = start; ro != null; ro = ro.parent) {
      if (ro is RenderBox && ro.hasSize) chain.add(ro);
      if (chain.length > 60) break;
    }

    // Consecutive wrappers (Padding-free proxies, Semantics, ...) that got
    // the same constraints and size say nothing new: fold them.
    final lines = <String>[];
    var folded = 0;
    RenderBox? previous;
    for (final box in chain) {
      if (lines.length >= maxBoxes) break;
      final same =
          previous != null &&
          previous.constraints == box.constraints &&
          previous.size == box.size &&
          box is! RenderFlex &&
          box.parentData is! FlexParentData;
      if (same) {
        folded++;
        continue;
      }
      lines.add(_line(box));
      previous = box;
    }
    final issues = <String>[];
    for (final box in chain.take(40)) {
      if (box is RenderFlex) {
        final overflow = _flexOverflow(box);
        if (overflow != null) issues.add(overflow);
      }
    }
    final zero = _zeroSize(chain);
    if (zero != null) issues.add(zero);

    return {
      'layout': lines,
      if (folded > 0)
        'folded':
            '$folded wrappers with the same constraints and size '
            'as the box below them are left out.',
      if (issues.isNotEmpty) 'issues': issues,
    };
  }

  static RenderBox? _renderBoxOf(Element element) {
    final ro = element.renderObject;
    if (ro is RenderBox && ro.hasSize && ro.attached) return ro;
    return null;
  }

  /// `Row lib/ui/tile.dart:30  400×20  w 0–400 · h 0–∞  Expanded(flex 1)`.
  static String _line(RenderBox box) {
    final parts = <String>[_name(box), _size(box.size), _constraints(box)];
    final data = box.parentData;
    if (data is FlexParentData && (data.flex ?? 0) > 0) {
      parts.add(
        '${data.fit == FlexFit.tight ? 'Expanded' : 'Flexible'}'
        '(flex ${data.flex})',
      );
    }
    if (box is RenderFlex) {
      parts.add(
        '${box.direction == Axis.horizontal ? 'horizontal' : 'vertical'}'
        '${box.mainAxisSize == MainAxisSize.min ? ', mainAxisSize min' : ''}',
      );
    }
    return parts.join('  ');
  }

  /// The widget that created [box], with its app location when it has one.
  /// A box a framework widget made for an app widget (the RichText inside
  /// a Text, the _ListTile inside a ListTile) is named after the app widget:
  /// `Text lib/ui/tile.dart:32 (RichText)`.
  static String _name(RenderObject box) {
    final creator = box.debugCreator;
    if (creator is! DebugCreator) return box.runtimeType.toString();
    final element = creator.element;
    final type = element.widget.runtimeType.toString();
    String? located(Element e) => debugIsWidgetLocalCreation(e.widget)
        ? SourceLocator.locationOf(e)
        : null;
    final own = located(element);
    if (own != null) return '$type $own';
    // Up to (not into) the widget that made the parent box.
    final parentCreator = box.parent?.debugCreator;
    final stop = parentCreator is DebugCreator ? parentCreator.element : null;
    String? app;
    element.visitAncestorElements((a) {
      if (identical(a, stop)) return false;
      final loc = located(a);
      if (loc != null) app = '${a.widget.runtimeType} $loc ($type)';
      return app == null;
    });
    return app ?? type;
  }

  static String _num(double v) => v.isInfinite
      ? '∞'
      : (v - v.roundToDouble()).abs() < 0.05
      ? v.round().toString()
      : v.toStringAsFixed(1);

  static String _size(Size s) => '${_num(s.width)}×${_num(s.height)}';

  static String _range(String axis, double min, double max) =>
      min == max ? '$axis=${_num(min)}' : '$axis ${_num(min)}–${_num(max)}';

  static String _constraints(RenderBox box) {
    final c = box.constraints;
    return '${_range('w', c.minWidth, c.maxWidth)} · '
        '${_range('h', c.minHeight, c.maxHeight)}';
  }

  /// A Row/Column whose children need more room than it has on its main
  /// axis: by how much, and which children take the space.
  static String? _flexOverflow(RenderFlex flex) {
    final horizontal = flex.direction == Axis.horizontal;
    double main(Size s) => horizontal ? s.width : s.height;
    final children = <RenderBox>[];
    var child = flex.firstChild;
    while (child != null) {
      children.add(child);
      child = (child.parentData! as FlexParentData).nextSibling;
    }
    if (children.isEmpty) return null;
    final needed =
        children.fold<double>(
          0,
          (sum, c) => sum + (c.hasSize ? main(c.size) : 0),
        ) +
        flex.spacing * (children.length - 1);
    final available = main(flex.size);
    final over = needed - available;
    if (over <= 0.5) return null;

    final list =
        (children.where((c) => c.hasSize).toList()
              ..sort((a, b) => main(b.size).compareTo(main(a.size))))
            .take(4)
            .map((c) {
              final data = c.parentData! as FlexParentData;
              final flexible = (data.flex ?? 0) > 0;
              return '${_name(c)} ${_num(main(c.size))} px'
                  '${flexible ? '' : ' (not flexible)'}';
            })
            .join(', ');
    final rigid = children.any(
      (c) => ((c.parentData! as FlexParentData).flex ?? 0) == 0,
    );
    return '${_name(flex)} overflows by ${_num(over)} px: its children need '
        '${_num(needed)} px, it has ${_num(available)} '
        '(${horizontal ? 'width' : 'height'}). Widest: $list.'
        '${rigid ? ' Wrap the long child in Expanded/Flexible (a Text then '
                  'wraps or ellipsizes with overflow: TextOverflow.ellipsis), '
                  'or make the ${horizontal ? 'Row' : 'Column'} scroll.' : ''}';
  }

  /// A box 0 wide or tall: whether it was told to be (max 0, and by which
  /// ancestor) or chose to be (empty content).
  static String? _zeroSize(List<RenderBox> chain) {
    final target = chain.first;
    for (final horizontal in [true, false]) {
      final size = horizontal ? target.size.width : target.size.height;
      if (size > 0) continue;
      final axis = horizontal ? 'width' : 'height';
      double max(RenderBox b) =>
          horizontal ? b.constraints.maxWidth : b.constraints.maxHeight;
      if (max(target) > 0) {
        return '${_name(target)} has $axis 0 although it may be up to '
            '${_num(max(target))}: its content is empty or sized 0.';
      }
      // Walk up while ancestors also got max 0: the last one got it from
      // its parent, which is where the 0 comes from.
      var from = target;
      for (final box in chain.skip(1)) {
        if (max(box) > 0) {
          final data = from.parentData;
          final flexHint = data is FlexParentData && (data.flex ?? 0) > 0
              ? ' It is flexible in ${_name(box)}: the other children '
                    'already use all the room.'
              : '';
          return '${_name(target)} has $axis 0 because ${_name(box)} '
              '(${_size(box.size)}) gives ${_name(from)} max $axis 0.'
              '$flexHint';
        }
        from = box;
      }
    }
    return null;
  }
}
