part of '../../flutterpilot_sdk.dart';

/// Widget interaction and inspection service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `tapWidget` — Tap a widget by key
/// - `enterText` — Enter text in a text field by key
/// - `scrollIntoView` — Scroll a widget into the visible viewport
/// - `doubleTapWidget` — Double-tap a widget by key
/// - `longPressWidget` — Long-press a widget by key
/// - `swipeWidget` — Swipe from a widget center in a direction
/// - `dragWidget` — Drag from one widget to another
/// - `clearTextField` — Clear a text field by key
/// - `focusWidget` — Focus a widget by key (tap to open keyboard)
/// - `toggleCheckbox` — Toggle a Checkbox/Switch/Radio by key
/// - `setSliderValue` — Set a Slider's value by key
/// - `getWidgetProperties` — Read semantic properties of a widget
/// - `getWidgetTree` — Capture the full widget tree as JSON
/// - `assertWidgetVisible` — Assert a widget exists and has layout
/// - `assertTextVisible` — Assert text is visible on screen
/// - `assertWidgetCount` — Assert count of widgets of a type
/// - `assertWidgetEnabled` — Assert a widget is enabled
/// - `assertWidgetDisabled` — Assert a widget is disabled
/// - `unfocusAll` — Remove focus from all widgets
extension _WidgetExtensions on FlutterPilot {
  static void register() {
    // -- ext.flutterpilot.tapWidget -------------------------------------------
    registerExtension('ext.flutterpilot.tapWidget', (method, parameters) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found',
        );
      }
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('tapWidget', {'key': key});
        }
        await InteractionManager.tapAt(pos);
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success'}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'No layout',
      );
    });

    // -- ext.flutterpilot.enterText -------------------------------------------
    registerExtension('ext.flutterpilot.enterText', (method, parameters) async {
      final key = parameters['key'];
      final text = parameters['text'];
      if (key == null || text == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing params',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found',
        );
      }
      bool found = false;
      void findText(Element e) {
        if (found) return;
        if (e is StatefulElement && e.state is EditableTextState) {
          try {
            final state = e.state;
            if (state is EditableTextState) {
              state.updateEditingValue(TextEditingValue(text: text));
              found = true;
            }
          } catch (_) {
            // Fall back to dynamic access for older Flutter versions
            try {
              (e.state as dynamic).controller.text = text;
              found = true;
            } catch (_) {}
          }
          if (found && FlutterPilot._isRecording) {
            FlutterPilot._recordAction('enterText', {'key': key, 'text': text});
          }
          return;
        }
        e.visitChildren(findText);
      }

      findText(element);
      return found
          ? ServiceExtensionResponse.result(json.encode({'status': 'success'}))
          : ServiceExtensionResponse.error(
              ServiceExtensionResponse.extensionError,
              'Not text field',
            );
    });

    // -- ext.flutterpilot.scrollIntoView --------------------------------------
    registerExtension('ext.flutterpilot.scrollIntoView', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found',
        );
      }
      Scrollable.ensureVisible(element);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.doubleTapWidget -------------------------------------
    registerExtension('ext.flutterpilot.doubleTapWidget', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('doubleTapWidget', {'key': key});
        }
        await InteractionManager.doubleTapAt(pos);
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success'}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'No layout for widget: $key',
      );
    });

    // -- ext.flutterpilot.longPressWidget -------------------------------------
    registerExtension('ext.flutterpilot.longPressWidget', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      final ms = int.tryParse(parameters['durationMs'] ?? '600') ?? 600;
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('longPressWidget', {
            'key': key,
            'durationMs': ms,
          });
        }
        await InteractionManager.longPressAt(
          pos,
          duration: Duration(milliseconds: ms),
        );
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success'}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'No layout for widget: $key',
      );
    });

    // -- ext.flutterpilot.swipeWidget -----------------------------------------
    registerExtension('ext.flutterpilot.swipeWidget', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      final direction = parameters['direction'] ?? 'up';
      final distance =
          double.tryParse(parameters['distance'] ?? '200') ?? 200.0;
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      final ro = element.renderObject;
      if (ro is! RenderBox || !ro.hasSize) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No layout for widget: $key',
        );
      }
      final start = ro.localToGlobal(ro.size.center(Offset.zero));
      final Offset end;
      switch (direction) {
        case 'up':
          end = start.translate(0, -distance);
        case 'down':
          end = start.translate(0, distance);
        case 'left':
          end = start.translate(-distance, 0);
        case 'right':
          end = start.translate(distance, 0);
        default:
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'direction must be up|down|left|right',
          );
      }
      if (FlutterPilot._isRecording) {
        FlutterPilot._recordAction('swipeWidget', {
          'key': key,
          'direction': direction,
          'distance': distance,
        });
      }
      await InteractionManager.swipeFromTo(start, end);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.dragWidget ------------------------------------------
    registerExtension('ext.flutterpilot.dragWidget', (
      method,
      parameters,
    ) async {
      final fromKey = parameters['fromKey'];
      final toKey = parameters['toKey'];
      if (fromKey == null || toKey == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing fromKey or toKey',
        );
      }
      final fromEl = PilotWidgetInspector.findElementByKey(fromKey);
      final toEl = PilotWidgetInspector.findElementByKey(toKey);
      if (fromEl == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $fromKey',
        );
      }
      if (toEl == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $toKey',
        );
      }
      final fromRo = fromEl.renderObject;
      final toRo = toEl.renderObject;
      if (fromRo is! RenderBox ||
          !fromRo.hasSize ||
          toRo is! RenderBox ||
          !toRo.hasSize) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No layout for one or both widgets',
        );
      }
      final from = fromRo.localToGlobal(fromRo.size.center(Offset.zero));
      final to = toRo.localToGlobal(toRo.size.center(Offset.zero));
      if (FlutterPilot._isRecording) {
        FlutterPilot._recordAction('dragWidget', {
          'fromKey': fromKey,
          'toKey': toKey,
        });
      }
      await InteractionManager.dragFromTo(from, to);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.clearTextField --------------------------------------
    registerExtension('ext.flutterpilot.clearTextField', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      bool found = false;
      void clearText(Element e) {
        if (found) return;
        if (e is StatefulElement && e.state is EditableTextState) {
          try {
            final state = e.state;
            if (state is EditableTextState) {
              state.updateEditingValue(TextEditingValue.empty);
              found = true;
            }
          } catch (_) {
            // Fall back to dynamic access for older Flutter versions
            try {
              (e.state as dynamic).controller.clear();
              found = true;
            } catch (_) {}
          }
          if (found && FlutterPilot._isRecording) {
            FlutterPilot._recordAction('clearTextField', {'key': key});
          }
          return;
        }
        e.visitChildren(clearText);
      }

      clearText(element);
      return found
          ? ServiceExtensionResponse.result(json.encode({'status': 'success'}))
          : ServiceExtensionResponse.error(
              ServiceExtensionResponse.extensionError,
              'No text field found under key: $key',
            );
    });

    // -- ext.flutterpilot.focusWidget -----------------------------------------
    registerExtension('ext.flutterpilot.focusWidget', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      final renderObject = element.renderObject;
      if (renderObject is! RenderBox) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget "$key" has no renderable box',
        );
      }
      final offset = renderObject.localToGlobal(Offset.zero);
      final center = offset +
          Offset(renderObject.size.width / 2, renderObject.size.height / 2);
      await InteractionManager.tapAt(center);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.toggleCheckbox --------------------------------------
    registerExtension('ext.flutterpilot.toggleCheckbox', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      RenderBox? renderBox;
      void findToggleable(Element e) {
        if (renderBox != null) return;
        final w = e.widget;
        if (w is Checkbox || w is Switch || w is Radio) {
          renderBox = e.renderObject as RenderBox?;
          return;
        }
        e.visitChildren(findToggleable);
      }

      if (element.widget is Checkbox ||
          element.widget is Switch ||
          element.widget is Radio) {
        renderBox = element.renderObject as RenderBox?;
      } else {
        findToggleable(element);
      }
      renderBox ??= element.renderObject as RenderBox?;
      if (renderBox == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget "$key" has no renderable box',
        );
      }
      final box = renderBox!;
      final offset = box.localToGlobal(Offset.zero);
      final center =
          offset + Offset(box.size.width / 2, box.size.height / 2);
      await InteractionManager.tapAt(center);
      if (FlutterPilot._isRecording) {
        FlutterPilot._recordAction('toggleCheckbox', {'key': key});
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.setSliderValue --------------------------------------
    registerExtension('ext.flutterpilot.setSliderValue', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      final valueStr = parameters['value'];
      if (key == null || valueStr == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameters: key, value',
        );
      }
      final targetValue = double.tryParse(valueStr);
      if (targetValue == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'value must be a numeric string',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      Slider? sliderWidget;
      Element? sliderElement;
      void findSlider(Element e) {
        if (sliderWidget != null) return;
        if (e.widget is Slider) {
          sliderWidget = e.widget as Slider;
          sliderElement = e;
          return;
        }
        e.visitChildren(findSlider);
      }

      if (element.widget is Slider) {
        sliderWidget = element.widget as Slider;
        sliderElement = element;
      } else {
        findSlider(element);
      }
      if (sliderWidget == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No Slider found under key: $key',
        );
      }
      final renderBox = sliderElement!.renderObject;
      if (renderBox is! RenderBox) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Slider not rendered',
        );
      }
      final slider = sliderWidget!;
      final min = slider.min;
      final max = slider.max;
      if (max <= min) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Slider min ($min) >= max ($max)',
        );
      }
      final clamped = targetValue.clamp(min, max);
      final fraction = (clamped - min) / (max - min);
      const trackPadding = 24.0;
      final trackWidth = renderBox.size.width - trackPadding * 2;
      if (trackWidth <= 0) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          json.encode({'error': 'Slider too narrow for tap simulation.'}),
        );
      }
      final globalOffset = renderBox.localToGlobal(Offset.zero);
      final tapX = globalOffset.dx + trackPadding + fraction * trackWidth;
      final tapY = globalOffset.dy + renderBox.size.height / 2;
      await InteractionManager.tapAt(Offset(tapX, tapY));
      if (FlutterPilot._isRecording) {
        FlutterPilot._recordAction('setSliderValue', {
          'key': key,
          'value': clamped,
        });
      }
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'success',
          'value': clamped,
          'fraction': fraction,
        }),
      );
    });

    // -- ext.flutterpilot.getWidgetProperties ---------------------------------
    registerExtension('ext.flutterpilot.getWidgetProperties', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      final props = <String, dynamic>{
        'type': element.widget.runtimeType.toString(),
        'key': key,
      };
      FlutterPilot._extractWidgetProps(element, props);
      return ServiceExtensionResponse.result(json.encode(props));
    });

    // -- ext.flutterpilot.getWidgetTree ---------------------------------------
    registerExtension('ext.flutterpilot.getWidgetTree', (
      method,
      parameters,
    ) async {
      try {
        return ServiceExtensionResponse.result(
          json.encode({'tree': PilotWidgetInspector.captureWidgetTree()}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Error: $e',
        );
      }
    });

    // -- ext.flutterpilot.assertWidgetVisible ---------------------------------
    registerExtension('ext.flutterpilot.assertWidgetVisible', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'ASSERTION FAILED: widget "$key" not found in tree',
        );
      }
      final ro = element.renderObject;
      if (ro is! RenderBox || !ro.hasSize) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'ASSERTION FAILED: widget "$key" found but has no layout (off-screen?)',
        );
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': 'passed', 'key': key}),
      );
    });

    // -- ext.flutterpilot.assertTextVisible -----------------------------------
    registerExtension('ext.flutterpilot.assertTextVisible', (
      method,
      parameters,
    ) async {
      final text = parameters['text'];
      final exact = parameters['exact'] == 'true';
      if (text == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing text',
        );
      }
      bool found = false;
      void findText(Element e) {
        if (found) return;
        if (e.widget is Text) {
          final data = (e.widget as Text).data ?? '';
          found = exact ? data == text : data.contains(text);
        } else if (e.widget is RichText) {
          final plain = (e.widget as RichText).text.toPlainText();
          found = exact ? plain == text : plain.contains(text);
        }
        if (!found) e.visitChildren(findText);
      }

      final root = WidgetsBinding.instance.rootElement;
      if (root != null) findText(root);
      if (found) {
        return ServiceExtensionResponse.result(
          json.encode({'status': 'passed', 'text': text}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'ASSERTION FAILED: text "$text" not visible on screen',
      );
    });

    // -- ext.flutterpilot.assertWidgetCount -----------------------------------
    registerExtension('ext.flutterpilot.assertWidgetCount', (
      method,
      parameters,
    ) async {
      final type = parameters['type'];
      final expectedStr = parameters['count'];
      if (type == null || expectedStr == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing type or count',
        );
      }
      final expected = int.tryParse(expectedStr);
      if (expected == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'count must be an integer',
        );
      }
      int actual = 0;
      void countWidgets(Element e) {
        if (e.widget.runtimeType.toString() == type) actual++;
        e.visitChildren(countWidgets);
      }

      final root = WidgetsBinding.instance.rootElement;
      if (root != null) countWidgets(root);
      if (actual == expected) {
        return ServiceExtensionResponse.result(
          json.encode({'status': 'passed', 'type': type, 'count': actual}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'ASSERTION FAILED: expected $expected "$type" widgets but found $actual',
      );
    });

    // -- ext.flutterpilot.assertWidgetEnabled / assertWidgetDisabled ----------
    registerExtension('ext.flutterpilot.assertWidgetEnabled', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      return FlutterPilot._assertWidgetState(
        element,
        key,
        shouldBeEnabled: true,
      );
    });

    registerExtension('ext.flutterpilot.assertWidgetDisabled', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      return FlutterPilot._assertWidgetState(
        element,
        key,
        shouldBeEnabled: false,
      );
    });

    // -- ext.flutterpilot.unfocusAll ------------------------------------------
    registerExtension('ext.flutterpilot.unfocusAll', (
      method,
      parameters,
    ) async {
      FocusManager.instance.primaryFocus?.unfocus();
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });
  }
}
