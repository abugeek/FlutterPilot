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
  static final List<Route<dynamic>> _stack = [];

  /// The most-recently registered [NavigationTracker] instance.
  ///
  /// Used internally by the SDK to perform programmatic navigation via
  /// `ext.flutterpilot.navigateTo` without requiring a user-supplied
  /// `BuildContext`.
  static NavigationTracker? _instance;

  /// The [NavigatorState] this observer is attached to, if any.
  ///
  /// Exposed so the SDK can call [NavigatorState.pushNamed] programmatically
  /// from outside the widget tree (e.g., from a VM service extension).
  static NavigatorState? get navigatorState => _instance?.navigator;

  /// Optional router-specific handler (e.g. GoRouter, AutoRoute) to execute
  /// declarative navigation when `ext.flutterpilot.navigateTo` is called.
  static Future<bool> Function(String route)? customNavigateHandler;

  /// Optional router-specific handler to pop routes when `ext.flutterpilot.pressBack` is called.
  static Future<bool> Function()? customPopHandler;

  /// Creates a [NavigationTracker] and registers it as the active instance.
  NavigationTracker() {
    _instance = this;
  }

  /// Optional callback invoked on every navigation event.
  ///
  /// Receives [source] (`'navigation'`), [name] (the event type such as
  /// `'push'`, `'pop'`, `'remove'`, `'replace'`), and the route name as
  /// [value].
  static void Function(String source, String name, dynamic value)?
  onStateChange;

  /// Returns an unmodifiable snapshot of the current route name stack.
  ///
  /// The list is ordered from bottom to top — the last element is the
  /// currently visible route.
  ///
  /// Without an observer or router plugin (e.g. `MaterialApp.router`, whose
  /// navigators take no observers from the app), it is read from the pages
  /// in the widget tree: go_router names each page after its route's name
  /// or path.
  static List<String?> get stack => List.unmodifiable(
    stackProvider?.call() ??
        (_stack.isNotEmpty ? _stack.map(describe) : _pagesInTree()),
  );

  /// Set by router plugins (e.g. flutterpilot_gorouter) whose navigation is
  /// not visible to a [NavigatorObserver]. Returns the stack, bottom to top.
  static List<String> Function()? stackProvider;

  /// The name of the currently active (top-most) route.
  ///
  /// Returns [unknown] when there is no route at all (no Navigator).
  static String get currentRoute {
    final s = stack;
    return s.isNotEmpty ? (s.last ?? unknown) : unknown;
  }

  /// [currentRoute] when there is no route to name.
  static const unknown = 'Unknown';

  /// The routes in the widget tree, bottom to top: every navigator's pages
  /// in tree order, so a nested navigator's pages (a go_router shell) come
  /// after the page holding them. Hidden branches (IndexedStack tabs sit
  /// behind an Offstage) are skipped; pages covered by another are not.
  static List<String> _pagesInTree() {
    Element? root;
    try {
      root = WidgetsBinding.instance.rootElement;
    } catch (_) {
      return const []; // no binding yet (plain unit tests, before runApp)
    }
    if (root == null) return const [];
    final routes = <String>[];
    void visit(Element e) {
      final w = e.widget;
      if (w is Offstage && w.offstage) return;
      // Every route builds a private _ModalScope whose `route` field is
      // the ModalRoute.
      if (w.runtimeType.toString().startsWith('_ModalScope<')) {
        final route = (w as dynamic).route;
        if (route is ModalRoute && route.isActive) routes.add(describe(route));
      }
      e.visitChildren(visit);
    }

    visit(root);
    return routes;
  }

  /// A readable name for [route]: its settings name, else what it is —
  /// "(menu)", "(dialog)", "(bottom sheet)", or the page's first app widget
  /// (e.g. "EditorScreen") for an unnamed `MaterialPageRoute(builder: ...)`.
  static String describe(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null) return name;
    final type = route.runtimeType.toString();
    if (route is PopupRoute) {
      if (type.contains('PopupMenu')) return '(menu)';
      if (type.contains('BottomSheet')) return '(bottom sheet)';
      if (type.contains('Dialog')) return '(dialog)';
      return '(popup)';
    }
    if (route is ModalRoute) {
      final page = _firstAppWidget(route.subtreeContext);
      if (page != null) return page;
    }
    return type.split('<').first;
  }

  static String? _firstAppWidget(BuildContext? context) {
    if (context is! Element) return null;
    String? found;
    var budget = 300; // pages are shallow; never walk a whole screen
    void visit(Element e) {
      if (found != null || --budget < 0) return;
      if (debugIsWidgetLocalCreation(e.widget)) {
        found = e.widget.runtimeType.toString();
        return;
      }
      e.visitChildren(visit);
    }

    context.visitChildren(visit);
    return found;
  }

  /// Clears the navigation stack and removes the [onStateChange] callback.
  ///
  /// Primarily used in tests to reset global state between test runs.
  static void reset() {
    _stack.clear();
    onStateChange = null;
    stackProvider = null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _stack.add(route);
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
    _stack.remove(route);
    onStateChange?.call('navigation', 'remove', route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index != -1 && newRoute != null) _stack[index] = newRoute;
    onStateChange?.call('navigation', 'replace', newRoute?.settings.name);
  }
}
