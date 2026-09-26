part of '../../flutterpilot_sdk.dart';

/// Navigation service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `navigateTo` — Push a named route
/// - `pressBack` — Pop the current route
/// - `getNavigationStack` — Return the route stack
/// - `waitForRoute` — Poll until a route is active
/// - `waitForWidget` — Poll until a widget appears
/// - `waitForAnimation` — Wait for animations to settle
/// - `simulateDeepLink` — Simulate a deep link URL open
/// - `setOrientation` — Switch device orientation
extension _NavigationExtensions on FlutterPilot {
  static void register() {
    // -- ext.flutterpilot.navigateTo ------------------------------------------
    registerExtension('ext.flutterpilot.navigateTo', (
      method,
      parameters,
    ) async {
      final route = parameters['route'];
      if (route == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: route',
        );
      }
      try {
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('navigate', {'route': route});
        }
        await _pushRoute(route);
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success', 'route': route}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Navigation failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.pressBack -------------------------------------------
    registerExtension('ext.flutterpilot.pressBack', (method, parameters) async {
      try {
        bool popped = false;
        final nav = NavigationTracker.navigatorState;
        if (nav != null && nav.mounted) {
          popped = await nav.maybePop();
        }
        if (!popped &&
            NavigationTracker.stack.length <= 1 &&
            parameters['allowExit'] != 'true') {
          // At the root the OS back path calls SystemNavigator.pop(), which
          // closes the app. Don't do that to an agent by accident.
          return ServiceExtensionResponse.result(
            json.encode({
              'status': 'success',
              'popped': false,
              'note': 'Already at the root route; back would exit the app. '
                  'Pass allowExit=true to do that.',
            }),
          );
        }
        if (!popped) {
          // Same path as the OS back button, so Router-based apps
          // (go_router, auto_route) handle it too.
          // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
          popped = await WidgetsBinding.instance.handlePopRoute();
        }
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('pressBack', {});
        }
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success', 'popped': popped}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Pop failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.getNavigationStack ----------------------------------
    registerExtension('ext.flutterpilot.getNavigationStack', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({'stack': NavigationTracker.stack}),
      );
    });

    // -- ext.flutterpilot.waitForRoute ----------------------------------------
    registerExtension('ext.flutterpilot.waitForRoute', (
      method,
      parameters,
    ) async {
      final route = parameters['route'];
      final timeoutMs = int.tryParse(parameters['timeoutMs'] ?? '5000') ?? 5000;
      if (route == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing route',
        );
      }
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
      while (DateTime.now().isBefore(deadline)) {
        final current = NavigationTracker.currentRoute;
        if (current == route) {
          return ServiceExtensionResponse.result(
            json.encode({'status': 'reached', 'route': route}),
          );
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      final current = NavigationTracker.currentRoute;
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'Timeout: route "$route" not reached within ${timeoutMs}ms (currently on "$current")',
      );
    });

    // -- ext.flutterpilot.waitForWidget ---------------------------------------
    registerExtension('ext.flutterpilot.waitForWidget', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      final timeoutMs = int.tryParse(parameters['timeoutMs'] ?? '5000') ?? 5000;
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
      Duration pollInterval = const Duration(milliseconds: 50);
      while (DateTime.now().isBefore(deadline)) {
        final element = PilotWidgetInspector.findElement(key);
        if (element != null) {
          return ServiceExtensionResponse.result(
            json.encode({'status': 'found', 'key': key}),
          );
        }
        await Future.delayed(pollInterval);
        // Increase poll interval up to 200ms to reduce CPU
        if (pollInterval.inMilliseconds < 200) {
          pollInterval = Duration(
            milliseconds: (pollInterval.inMilliseconds * 1.5).round(),
          );
        }
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'Timeout: widget "$key" not found within ${timeoutMs}ms',
      );
    });

    // -- ext.flutterpilot.waitForAnimation ------------------------------------
    registerExtension('ext.flutterpilot.waitForAnimation', (
      method,
      parameters,
    ) async {
      final timeoutMs = int.tryParse(parameters['timeoutMs'] ?? '3000') ?? 3000;
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
      var stableFrames = 0;
      while (DateTime.now().isBefore(deadline)) {
        final scheduler = SchedulerBinding.instance;
        final busy = scheduler.hasScheduledFrame || scheduler.transientCallbackCount > 0;
        if (busy) {
          stableFrames = 0;
        } else {
          stableFrames++;
          if (stableFrames >= 2) {
            await WidgetsBinding.instance.endOfFrame;
            return ServiceExtensionResponse.result(
              json.encode({'status': 'settled', 'stableFrames': stableFrames}),
            );
          }
        }
        await Future.delayed(const Duration(milliseconds: 16));
      }
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'timeout',
          'note': 'Animation may still be running',
          'transientCallbackCount': SchedulerBinding.instance.transientCallbackCount,
        }),
      );
    });

    // -- ext.flutterpilot.simulateDeepLink ------------------------------------
    registerExtension('ext.flutterpilot.simulateDeepLink', (
      method,
      parameters,
    ) async {
      final url = parameters['url'];
      if (url == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: url',
        );
      }
      try {
        await _pushRoute(url, deepLink: true);
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('simulateDeepLink', {'url': url});
        }
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success', 'url': url}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Deep link failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.setOrientation --------------------------------------
    registerExtension('ext.flutterpilot.setOrientation', (
      method,
      parameters,
    ) async {
      final orientation = parameters['orientation'];
      final List<DeviceOrientation> preferred;
      switch (orientation) {
        case 'portrait':
          preferred = [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ];
        case 'landscape':
          preferred = [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ];
        case 'all':
          preferred = DeviceOrientation.values;
        default:
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'orientation must be: portrait | landscape | all',
          );
      }
      await SystemChrome.setPreferredOrientations(preferred);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success', 'orientation': orientation}),
      );
    });

    // -- ext.flutterpilot.jumpToScreen ----------------------------------------
    registerExtension('ext.flutterpilot.jumpToScreen', (
      method,
      parameters,
    ) async {
      final route = parameters['route'];
      final stateJson = parameters['state'];

      if (route == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing route parameter',
        );
      }

      // 1. Inject seed state if provided
      if (stateJson != null) {
        try {
          final dynamic stateData = json.decode(stateJson);
          if (stateData is Map) {
            for (final entry in stateData.entries) {
              final parts = entry.key.toString().split(':');
              if (parts.length >= 2) {
                final type = parts[0];
                final name = parts.sublist(1).join(':');
                if (FlutterPilot._stateSetters.containsKey(type)) {
                  await FlutterPilot._stateSetters[type]!(name, entry.value);
                }
              }
            }
          }
        } catch (_) {}
      }

      // 2. Teleport to target screen
      try {
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('jumpToScreen', {'route': route});
        }
        await _pushRoute(route);
        return ServiceExtensionResponse.result(
          json.encode({
            'status': 'success',
            'route': route,
            'stateInjected': stateJson != null,
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Jump to screen failed: $e',
        );
      }
    });
  }
}

/// Navigates to [route]. Apps using [NavigationTracker] get a pushNamed;
/// Router-based apps (go_router, auto_route) and deep links go through
/// [WidgetsBinding.handlePushRoute] — the same entry point the OS uses.
Future<void> _pushRoute(String route, {bool deepLink = false}) async {
  final nav = NavigationTracker.navigatorState;
  if (!deepLink && nav != null && nav.mounted) {
    nav.pushNamed(route);
    return;
  }
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  await WidgetsBinding.instance.handlePushRoute(route);
}
