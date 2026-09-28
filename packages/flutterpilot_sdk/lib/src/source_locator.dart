import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'ai_overlay_manager.dart';
import 'widget_inspector.dart';

/// "What code draws this?" (ROADMAP §5.1): the file:line in the app's own
/// code that creates a widget, and the app widgets above it.
///
/// Reads the creation locations that `--track-widget-creation` (on by
/// default for `flutter run` and `flutter test` in debug mode) records on
/// every widget, the same data DevTools' inspector shows.
class SourceLocator {
  /// Max app widgets listed above the source; the rest are counted.
  static const int maxAncestors = 8;

  /// Whether the app records creation locations (debug builds only).
  static bool get available =>
      WidgetInspectorService.instance.isWidgetCreationTracked();

  /// Where [element]'s widget is created, e.g. `lib/ui/tile.dart:42:7`.
  /// Null when the widget has no recorded location.
  static String? locationOf(Element element) {
    final json = element.toDiagnosticsNode().toJsonMap(
      InspectorSerializationDelegate(
        service: WidgetInspectorService.instance,
        subtreeDepth: 0,
      ),
    );
    final location = json['creationLocation'];
    if (location is! Map) return null;
    final file = location['file']?.toString();
    if (file == null) return null;
    return '${shortPath(file)}:${location['line']}:${location['column']}';
  }

  /// `file:///Users/me/app/lib/ui/tile.dart` -> `lib/ui/tile.dart`.
  static String shortPath(String file) {
    final path = file.startsWith('file://') ? Uri.parse(file).path : file;
    final lib = path.lastIndexOf('/lib/');
    return lib >= 0 ? path.substring(lib + 1) : path;
  }

  /// The element drawn at global logical point [position]: the deepest
  /// render object a tap there would hit, as the element that created it.
  /// Null when nothing but the app's root is there.
  static Element? elementAt(Offset position) {
    final binding = WidgetsBinding.instance;
    final viewId = binding.platformDispatcher.implicitView?.viewId;
    if (viewId == null) return null;
    final result = HitTestResult();
    binding.hitTestInView(result, position, viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderObject || target is RenderView) continue;
      final creator = target.debugCreator;
      if (creator is! DebugCreator) continue;
      final element = creator.element;
      if (_inOverlay(element)) continue;
      return element;
    }
    return null;
  }

  static bool _inOverlay(Element element) {
    if (element.widget is AiOverlayMarker) return true;
    var inside = false;
    element.visitAncestorElements((a) {
      inside = a.widget is AiOverlayMarker;
      return !inside;
    });
    return inside;
  }

  /// The source of [element]: the nearest widget at or above it that the
  /// app's own code creates, its location, and the app widgets above that.
  static Map<String, dynamic> describe(Element element) {
    final widget = element.widget;
    final result = <String, dynamic>{
      'widget': {
        'type': widget.runtimeType.toString(),
        'key': ?PilotWidgetInspector.extractCleanKey(
          widget.key is GlobalKey ? null : widget.key,
        ),
        if (widget is Text)
          'text': widget.data ?? widget.textSpan?.toPlainText() ?? '',
        'bounds': ?_bounds(element),
      },
    };

    // The matched widget itself, then its ancestors: the first app-created
    // one is the source; the next ones are the chain an agent walks up.
    final chain = <Element>[if (debugIsWidgetLocalCreation(widget)) element];
    var total = chain.length;
    element.visitAncestorElements((a) {
      if (debugIsWidgetLocalCreation(a.widget)) {
        total++;
        if (chain.length <= maxAncestors) chain.add(a);
      }
      return true;
    });
    if (chain.isEmpty) return result;

    final source = chain.first;
    result['source'] = {
      'type': source.widget.runtimeType.toString(),
      'loc': ?locationOf(source),
      if (!identical(source, element))
        'note':
            '${widget.runtimeType} is created inside '
            '${source.widget.runtimeType} (framework or package code); '
            'this is the app code that draws it.',
    };
    final ancestors = [
      for (final a in chain.skip(1))
        '${a.widget.runtimeType} ${locationOf(a) ?? ''}'.trim(),
    ];
    if (ancestors.isNotEmpty) result['ancestors'] = ancestors;
    if (total > chain.length) {
      result['moreAncestors'] = total - chain.length;
    }
    return result;
  }

  static Map<String, int>? _bounds(Element element) {
    final ro = element.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
    final pos = ro.localToGlobal(Offset.zero);
    return {
      'x': pos.dx.round(),
      'y': pos.dy.round(),
      'w': ro.size.width.round(),
      'h': ro.size.height.round(),
    };
  }
}
