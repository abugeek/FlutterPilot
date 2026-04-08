import 'package:flutter/widgets.dart';

/// A [NavigatorObserver] that tracks the application's navigation stack.
///
/// Add an instance of [NavigationTracker] to your app's
/// `navigatorObservers` to enable route tracking:
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [NavigationTracker()],
/// )
/// ```
///
/// The current route stack is available via the static [stack] getter and
/// is exposed to external tools through the
/// `ext.flutterpilot.getNavigationStack` service extension.
///
/// **Note:** When multiple [Navigator]s are used (e.g., nested navigation),
/// create a separate [NavigationTracker] instance for each. The static
/// [_stack] is shared across all instances.
class NavigationTracker extends NavigatorObserver {
  static final List<String?> _stack = [];

  /// Optional callback invoked on every navigation event.
  ///
  /// Receives [source] (`'navigation'`), [name] (the event type such as
  /// `'push'`, `'pop'`, `'remove'`, `'replace'`), and the route name as
  /// [value].
  static void Function(String source, String name, dynamic value)? onStateChange;

  /// Returns an unmodifiable snapshot of the current route name stack.
  ///
  /// The list is ordered from bottom to top — the last element is the
  /// currently visible route.
  static List<String?> get stack => List.unmodifiable(_stack);

  /// The name of the currently active (top-most) route.
  ///
  /// Returns `'Unknown'` if the stack is empty or the route has no name.
  static String get currentRoute => _stack.isNotEmpty ? (_stack.last ?? 'Unknown') : 'Unknown';

  /// Clears the navigation stack and removes the [onStateChange] callback.
  ///
  /// Primarily used in tests to reset global state between test runs.
  static void reset() {
    _stack.clear();
    onStateChange = null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _stack.add(route.settings.name);
    onStateChange?.call('navigation', 'push', route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_stack.isNotEmpty) _stack.removeLast();
    onStateChange?.call('navigation', 'pop', route.settings.name);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    // Use lastIndexOf to remove the correct occurrence when duplicate names exist
    final index = _stack.lastIndexOf(route.settings.name);
    if (index != -1) _stack.removeAt(index);
    onStateChange?.call('navigation', 'remove', route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final index = _stack.lastIndexOf(oldRoute?.settings.name);
    if (index != -1) {
      _stack[index] = newRoute?.settings.name;
    }
    onStateChange?.call('navigation', 'replace', newRoute?.settings.name);
  }
}
