import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Overrides the locale and text scale the app gets from the device, with no
/// wiring in the app.
///
/// * Locale: tells the binding the device locales changed
///   ([WidgetsBinding.dispatchLocalesChanged]), as changing the device
///   language does. The app resolves it against its own `supportedLocales`,
///   and an app that sets `MaterialApp(locale:)` keeps its locale — as on a
///   real device.
/// * Text scale: puts the scale into the root [MediaQuery], the one [View]
///   builds from the device, as changing the device font size does. An app
///   that clamps text scaling below it still clamps it.
///
/// The framework rebuilds both from the device now and then (keyboard,
/// rotation, window resize, hot reload, a rebuilt `MaterialApp`); they are
/// put back each time. Each setter reports what the app ended up with.
class AppSettingsOverride with WidgetsBindingObserver {
  AppSettingsOverride._();

  static final AppSettingsOverride instance = AppSettingsOverride._();

  ui.Locale? _locale;
  double? _textScale;
  double? _keyboardInset;

  bool get _overridesMedia => _textScale != null || _keyboardInset != null;

  /// The locale the app resolved after the last override, re-read after
  /// FlutterPilot re-dispatches it (null until then).
  ui.Locale? _appLocale;
  final _patched = Expando<MediaQuery>();
  Element? _localizations;
  var _hooked = false;

  /// "fr", "en-GB", "en_GB", "zh-Hans-CN" → [ui.Locale]; null if malformed.
  static ui.Locale? parseLocale(String tag) {
    final parts = tag.split(RegExp('[-_]'));
    final language = parts.first;
    if (!RegExp(r'^[A-Za-z]{2,8}$').hasMatch(language)) return null;
    String? script;
    String? country;
    for (final part in parts.skip(1)) {
      if (script == null &&
          country == null &&
          RegExp(r'^[A-Za-z]{4}$').hasMatch(part)) {
        script = '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      } else if (country == null &&
          RegExp(r'^([A-Za-z]{2}|\d{3})$').hasMatch(part)) {
        country = part.toUpperCase();
      } else {
        return null;
      }
    }
    return ui.Locale.fromSubtags(
      languageCode: language.toLowerCase(),
      scriptCode: script,
      countryCode: country,
    );
  }

  /// Drops both overrides without touching the app (tests).
  @visibleForTesting
  void reset() {
    _locale = null;
    _textScale = null;
    _keyboardInset = null;
    _appLocale = null;
    _localizations = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// The overriding locale, or null for the device's.
  ui.Locale? get locale => _locale;

  /// The overriding text scale, or null for the device's.
  double? get textScale => _textScale;

  /// Overrides the device locale; null restores it. Returns `locale` (what
  /// the app shows now), `supported`, and `appSetsLocale` when the app pins
  /// its own locale.
  Future<Map<String, Object?>> setLocale(ui.Locale? locale) async {
    _locale = locale;
    _appLocale = null;
    _hook();
    _dispatchLocale();
    await _nextFrame();
    final app = _widgetsApp();
    _localizations = _find<Localizations>();
    final shown = _appLocalizations()?.locale;
    _appLocale = shown;
    return {
      'locale': shown?.toString(),
      if (app != null)
        'supported': [for (final l in app.supportedLocales) l.toString()],
      if (app?.locale != null) 'appSetsLocale': app!.locale.toString(),
    };
  }

  /// Overrides the device text scale; null restores it. Returns `scale`,
  /// the scale the app's screens get (below any clamp the app applies).
  Future<Map<String, Object?>> setTextScale(double? scale) async {
    _textScale = scale;
    _hook();
    _applyMediaOverrides(changed: true);
    await _nextFrame();
    return {'scale': effectiveTextScale()};
  }

  /// The overriding keyboard inset, or null for the device's.
  double? get keyboardInset => _keyboardInset;

  /// Lays the app out as if an on-screen keyboard [inset] logical pixels
  /// tall were open (the root [MediaQuery]'s `viewInsets.bottom`, and no
  /// bottom padding, as on a phone); null restores the device's. A desktop
  /// or web app has no such keyboard, and a form that overflows above one
  /// is only seen this way. Returns `inset` (what the app's screens get)
  /// and `height` (the view's height).
  Future<Map<String, Object?>> setKeyboardInset(double? inset) async {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    final height = view == null
        ? null
        : view.physicalSize.height / view.devicePixelRatio;
    _keyboardInset = inset == null || height == null
        ? inset
        : inset.clamp(0, height * 0.9).toDouble();
    _hook();
    _applyMediaOverrides(changed: true);
    await _nextFrame();
    final probe = _find<Navigator>() ?? _find<MediaQuery>();
    final media = probe?.getInheritedWidgetOfExactType<MediaQuery>();
    return {'inset': media?.data.viewInsets.bottom, 'height': height};
  }

  /// The text scale the app's screens get: the one at the root [Navigator].
  double? effectiveTextScale() {
    final probe = _find<Navigator>() ?? _find<MediaQuery>();
    final media = probe?.getInheritedWidgetOfExactType<MediaQuery>();
    if (media == null) return null;
    return media.data.textScaler.scale(100).round() / 100;
  }

  void _hook() {
    if (!_hooked) {
      _hooked = true;
      SchedulerBinding.instance.addPersistentFrameCallback(_checkAfterFrame);
    }
    // Last, so the root MediaQuery has marked itself for rebuild from the
    // device before [didChangeMetrics] here runs.
    WidgetsBinding.instance
      ..removeObserver(this)
      ..addObserver(this);
  }

  void _dispatchLocale() {
    final binding = WidgetsBinding.instance;
    // ignore: invalid_use_of_protected_member
    binding.dispatchLocalesChanged(
      _locale == null ? binding.platformDispatcher.locales : [_locale!],
    );
  }

  /// Puts the override into each root [MediaQuery] that doesn't have it, or
  /// has the root rebuild from the device when there is none.
  ///
  /// When a device change (keyboard, rotation, resize) has marked the root's
  /// parent for rebuild, it is rebuilt here first and the override put back
  /// before anything below it builds, so nothing builds or paints at the
  /// device's scale in between.
  ///
  /// [changed]: an override was just set, so a root that already carries
  /// the previous values is rebuilt from the device and patched again.
  void _applyMediaOverrides({bool changed = false}) {
    final owner = WidgetsBinding.instance.buildOwner;
    if (owner == null) return;
    for (final element in _rootMediaQueries()) {
      final parent = _parentOf(element);
      final scale = _textScale;
      final inset = _keyboardInset;
      if (parent == null) continue;
      if (!_overridesMedia) {
        if (_patched[element] != null) {
          _patched[element] = null;
          parent.markNeedsBuild();
        }
        continue;
      }
      if (changed && _patched[element] != null) parent.markNeedsBuild();
      if (!parent.dirty && identical(element.widget, _patched[element])) {
        continue;
      }
      owner.buildScope(parent, () {
        if (parent.dirty) parent.rebuild();
        final current = element.widget as MediaQuery;
        var data = current.data;
        if (scale != null) {
          data = data.copyWith(textScaler: TextScaler.linear(scale));
        }
        if (inset != null) {
          // As an open keyboard reports: it covers the bottom safe area.
          data = data.copyWith(
            viewInsets: data.viewInsets.copyWith(bottom: inset),
            padding: data.padding.copyWith(bottom: 0),
          );
        }
        final patched = MediaQuery(
          key: current.key,
          data: data,
          child: current.child,
        );
        _patched[element] = patched;
        element.update(patched);
      });
    }
  }

  void _deviceChanged() {
    if (_overridesMedia) _applyMediaOverrides();
  }

  /// Catches what [_deviceChanged] can't see coming (hot reload, a rebuilt
  /// [View]) one frame late.
  void _checkAfterFrame(Duration _) {
    if (_overridesMedia &&
        _rootMediaQueries().any((e) => !identical(e.widget, _patched[e]))) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => _applyMediaOverrides(),
      );
    }
    if (_locale != null && _localizations != null) {
      final shown = _appLocalizations()?.locale;
      if (_appLocale == null) {
        _appLocale = shown;
      } else if (shown != _appLocale) {
        // MaterialApp re-resolved from the device (e.g. rebuilt with a new
        // supportedLocales list). Dispatch again, then accept what it shows,
        // so a locale the app picks itself isn't fought.
        _appLocale = null;
        SchedulerBinding.instance.addPostFrameCallback(
          (_) => _dispatchLocale(),
        );
      }
    }
  }

  @override
  void didChangeMetrics() => _deviceChanged();

  @override
  void didChangeTextScaleFactor() => _deviceChanged();

  @override
  void didChangePlatformBrightness() => _deviceChanged();

  @override
  void didChangeAccessibilityFeatures() => _deviceChanged();

  @override
  void didChangeLocales(List<ui.Locale>? locales) {
    // The device language changed while overridden: keep the override.
    final locale = _locale;
    if (locale != null && !(locales?.length == 1 && locales!.first == locale)) {
      scheduleMicrotask(_dispatchLocale);
    }
  }

  static Future<void> _nextFrame() => SchedulerBinding.instance.endOfFrame
      .timeout(const Duration(seconds: 1), onTimeout: () {});

  /// The first [MediaQuery] under each view: the one built from the device.
  static List<Element> _rootMediaQueries() {
    final found = <Element>[];
    void visit(Element element, int depth) {
      if (element.widget is MediaQuery) {
        found.add(element);
      } else if (depth < 32) {
        element.visitChildElements((child) => visit(child, depth + 1));
      }
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root, 0);
    return found;
  }

  static Element? _parentOf(Element element) {
    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false;
    });
    return parent;
  }

  static WidgetsApp? _widgetsApp() =>
      _find<WidgetsApp>()?.widget as WidgetsApp?;

  /// The app-level [Localizations] (the one `WidgetsApp` builds), found
  /// again only when its element is gone: this runs after every frame.
  Localizations? _appLocalizations() {
    var element = _localizations;
    if (element == null ||
        !element.mounted ||
        element.widget is! Localizations) {
      element = _localizations = _find<Localizations>();
    }
    return element?.widget as Localizations?;
  }

  /// The first element (depth-first from the root) whose widget is a [T].
  static Element? _find<T extends Widget>() {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget is T) {
        found = element;
      } else {
        element.visitChildElements(visit);
      }
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return found;
  }
}
