import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:go_router/go_router.dart';

/// FlutterPilot plugin that exposes GoRouter navigation state to AI agents.
///
/// Provides visibility into:
/// - **Current location**: URI, path parameters, query parameters
/// - **Route configuration**: registered routes and their paths
/// - **Navigation history**: recent route changes
/// - **Programmatic navigation**: go, push, pop via MCP tools
///
/// ## Setup
/// ```dart
/// final router = GoRouter(routes: [...]);
/// GoRouterPilotInspector.register(router);
/// ```
class GoRouterPilotInspector {
  GoRouterPilotInspector._();

  static bool _registered = false;
  static GoRouter? _router;
  static final List<Map<String, dynamic>> _navigationHistory = [];
  static const int _maxHistory = 50;
  static VoidCallback? _routerListener;

  /// Registers a [GoRouter] instance with FlutterPilot.
  ///
  /// Call once after creating your GoRouter, typically in your app setup:
  /// ```dart
  /// final router = GoRouter(routes: [...]);
  /// GoRouterPilotInspector.register(router);
  /// ```
  static void register(GoRouter router) {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        '[FlutterPilot] GoRouterPilotInspector.register called before '
        'FlutterPilot.initialize(). Extensions will not be registered.',
      );
      return;
    }
    if (_registered) return;
    _registered = true;
    _router = router;
    _listenRouteChanges();
    _registerExtensions();
  }

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    if (_routerListener != null && _router != null) {
      _router!.routerDelegate.removeListener(_routerListener!);
    }
    _routerListener = null;
    _navigationHistory.clear();
    _router = null;
    _registered = false;
  }

  static void _listenRouteChanges() {
    _routerListener = () {
      final config = _router?.routerDelegate.currentConfiguration;
      if (config != null) {
        _navigationHistory.add({
          'location': config.uri.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        });
        while (_navigationHistory.length > _maxHistory) {
          _navigationHistory.removeAt(0);
        }
      }
    };
    _router?.routerDelegate.addListener(_routerListener!);
  }

  static void _registerExtensions() {
    // -- ext.flutterpilot.getGoRouterState ------------------------------------
    registerExtension('ext.flutterpilot.getGoRouterState', (
      method,
      parameters,
    ) async {
      final router = _router;
      if (router == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'GoRouter not registered.',
        );
      }

      final config = router.routerDelegate.currentConfiguration;
      final location = config.uri.toString();

      return ServiceExtensionResponse.result(json.encode({
        'currentLocation': location,
        'pathParameters': config.pathParameters,
        'queryParameters': config.uri.queryParameters,
        'matchedRoutes': config.matches.map((m) {
          return {
            'matchedLocation': m.matchedLocation,
            'route': m.route is GoRoute
                ? (m.route as GoRoute).path
                : m.route.runtimeType.toString(),
          };
        }).toList(),
        'canPop': router.canPop(),
      }));
    });

    // -- ext.flutterpilot.getGoRouterConfig -----------------------------------
    registerExtension('ext.flutterpilot.getGoRouterConfig', (
      method,
      parameters,
    ) async {
      final router = _router;
      if (router == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'GoRouter not registered.',
        );
      }

      List<Map<String, dynamic>> extractRoutes(List<RouteBase> routes) {
        return routes.map((route) {
          final data = <String, dynamic>{
            'type': route.runtimeType.toString(),
          };
          if (route is GoRoute) {
            data['path'] = route.path;
            data['name'] = route.name;
            if (route.routes.isNotEmpty) {
              data['children'] = extractRoutes(route.routes);
            }
          } else if (route is ShellRoute) {
            data['type'] = 'ShellRoute';
            if (route.routes.isNotEmpty) {
              data['children'] = extractRoutes(route.routes);
            }
          }
          return data;
        }).toList();
      }

      return ServiceExtensionResponse.result(json.encode({
        'routes': extractRoutes(router.configuration.routes),
      }));
    });

    // -- ext.flutterpilot.getGoRouterHistory -----------------------------------
    registerExtension('ext.flutterpilot.getGoRouterHistory', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(json.encode({
        'history': _navigationHistory,
        'count': _navigationHistory.length,
      }));
    });

    // -- ext.flutterpilot.goRouterNavigate ------------------------------------
    registerExtension('ext.flutterpilot.goRouterNavigate', (
      method,
      parameters,
    ) async {
      final router = _router;
      if (router == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'GoRouter not registered.',
        );
      }

      final location = parameters['location'];
      final action = parameters['action'] ?? 'go';

      if (location == null && action != 'pop') {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing "location" parameter (required for go/push).',
        );
      }

      try {
        switch (action) {
          case 'push':
            router.push(location!);
          case 'replace':
            router.replace(location!);
          case 'pop':
            if (router.canPop()) {
              router.pop();
            } else {
              return ServiceExtensionResponse.error(
                ServiceExtensionResponse.extensionError,
                'Cannot pop — already at root route.',
              );
            }
          case 'go':
          default:
            router.go(location!);
        }
        return ServiceExtensionResponse.result(json.encode({
          'status': 'success',
          'action': action,
          'location': location,
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Navigation failed: $e',
        );
      }
    });
  }
}
