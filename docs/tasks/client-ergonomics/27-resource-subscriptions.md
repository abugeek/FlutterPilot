# 27 · Live MCP Resource Subscriptions & Push Notifications

**Branch:** `feat/resource-subscriptions` from `main` · **Depends on:** 26

## Goal
Implement standard MCP resource subscriptions (`resources/subscribe`, `resources/unsubscribe`, and `notifications/resources/updated`) so connected AI clients (Claude Desktop, Cursor, Antigravity, Zed) receive instant, asynchronous push notifications when app state changes (hot reload, route navigation, uncaught exception, or device fleet change) without polling.

## Context
In `FlutterPilotServer` constructor:
`capabilities` already declares:
```dart
resources: ServerCapabilitiesResources(
  listChanged: true,
  subscribe: true,
)
```
In `mcp_dart`:
`Method.resourcesSubscribe` and `Method.resourcesUnsubscribe` are standard methods, and `server.server.sendResourceUpdated(ResourceUpdatedNotification(uri: uri))` sends the standard JSON-RPC `notifications/resources/updated` notification.

## Implementation Details

### 1. Subscription Registry in `packages/flutterpilot_server/lib/src/resources.dart`
Add a set to track active client subscriptions:
```dart
final Set<String> _subscribedResourceUris = {};

void _registerSubscriptionHandlers() {
  server.server.setRequestHandler<SubscribeRequest, EmptyResult>(
    Method.resourcesSubscribe,
    (request, extra) async {
      _subscribedResourceUris.add(request.uri);
      return const EmptyResult();
    },
    (json) => SubscribeRequest.fromJson(json),
  );

  server.server.setRequestHandler<UnsubscribeRequest, EmptyResult>(
    Method.resourcesUnsubscribe,
    (request, extra) async {
      _subscribedResourceUris.remove(request.uri);
      return const EmptyResult();
    },
    (json) => UnsubscribeRequest.fromJson(json),
  );
}

/// Emits `notifications/resources/updated` to subscribed clients if [uri] is subscribed.
Future<void> notifyResourceUpdated(String uri) async {
  if (_subscribedResourceUris.contains(uri)) {
    await server.server.sendResourceUpdated(
      ResourceUpdatedNotification(uri: uri),
    );
  }
}
```

### 2. Event Triggers
Hook `notifyResourceUpdated` to key app events:
- **App Connect / Disconnect**: notify `flutterpilot://app/summary` and `flutterpilot://devices`.
- **Route Navigation**: notify `flutterpilot://app/summary`, `flutterpilot://app/widget-tree`, and `flutterpilot://app/routes/current`.
- **Unhandled Error / Overflow**: notify `flutterpilot://app/errors` and `flutterpilot://app/summary`.
- **Hot Reload / Hot Restart**: notify `flutterpilot://app/summary`, `flutterpilot://app/errors`, and `flutterpilot://app/widget-tree`.

### 3. Protocol Compliance & Tests
In `packages/flutterpilot_server/test/mcp_protocol_compliance_test.dart`:
Add group `Matrix 5 · resource subscriptions & live notifications`:
```dart
group('Matrix 5 · resource subscriptions & live notifications', () {
  test('subscribing to a resource returns EmptyResult', () async {
    final response = await inspector.request('resources/subscribe', {
      'uri': 'flutterpilot://app/summary',
    });
    expect(response['error'], isNull);
  });

  test('notifying an update sends notifications/resources/updated', () async {
    await inspector.request('resources/subscribe', {
      'uri': 'flutterpilot://app/summary',
    });
    // Trigger update via test seam or server method
    // Assert inspector receives notifications/resources/updated with uri
  });

  test('unsubscribing removes subscription', () async {
    final response = await inspector.request('resources/unsubscribe', {
      'uri': 'flutterpilot://app/summary',
    });
    expect(response['error'], isNull);
  });
});
```

### 4. Verification
- `dart test test/mcp_protocol_compliance_test.dart` passes.
- `dart test test/tool_registration_test.dart` passes with 63 tools and 0 token regression.
- `dart analyze packages/flutterpilot_server` clean.

## Done When
- [x] `resources/subscribe` and `resources/unsubscribe` handled without errors.
- [x] `notifications/resources/updated` emitted when subscribed resources change.
- [x] Headless protocol test in `mcp_protocol_compliance_test.dart` verifies full subscribe/notify/unsubscribe cycle.
- [x] PR #138 opened and verified.
