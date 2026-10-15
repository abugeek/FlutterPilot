# 26 · Dynamic MCP Resource Templates (RFC 6570)

**Branch:** `feat/resource-templates` from `main` · **Depends on:** 25

## Goal
Implement dynamic MCP Resource Templates (`resources/templates/list` and templated `resources/read`) so AI agents (Cursor, Claude, Antigravity, Zed) can query granular app state—such as a single widget subtree or route details—by URI without needing to pull the entire app widget tree or execute tool calls.

## Templates to Register

1. **Widget by Key**:
   - URI Template: `flutterpilot://app/widgets/{key}`
   - Name: `Widget Subtree by Key`
   - Description: `Compact widget hierarchy and properties for a specific widget Key.`
   - MIME Type: `application/json`

2. **Route by Path**:
   - URI Template: `flutterpilot://app/routes/{path}`
   - Name: `Route Inspection`
   - Description: `Navigation state, matched route, and parameters for a specific route path or 'current'.`
   - MIME Type: `application/json`

## Implementation Details

### 1. Register Resource Templates in `packages/flutterpilot_server/lib/src/resources.dart`
Use `mcp_dart`'s `server.registerResourceTemplate`:
```dart
server.registerResourceTemplate(
  'widget_by_key',
  ResourceTemplateRegistration(
    'flutterpilot://app/widgets/{key}',
    listCallback: null,
  ),
  (
    description: 'Compact widget hierarchy and properties for a specific widget Key.',
    mimeType: 'application/json',
  ),
  (uri, params) async {
    final key = params['key'] ?? '';
    return _readWidgetResource(key);
  },
);
```

### 2. Handlers
- `_readWidgetResource(String key)`:
  Queries the connected app for the widget with key `key` (via `ext.flutterpilot.inspectWidget` or `getWidgetTree` scoped to key). If not connected, returns `_noAppMessage`. If not found, returns `{"found": false, "key": key}`.
- `_readRouteResource(String path)`:
  Queries the connected app for the navigation stack and matched route.

### 3. Protocol Compliance & Tests
1. In `packages/flutterpilot_server/test/mcp_protocol_compliance_test.dart`:
   Add test under Matrix 2:
   ```dart
   test('resources/templates/list offers widget and route templates', () async {
     final response = await inspector.request('resources/templates/list');
     expect(response['error'], isNull);
     final templates = (response['result'] as Map)['resourceTemplates'] as List;
     expect(templates, isNotEmpty);
     final uriTemplates = [
       for (final t in templates) (t as Map)['uriTemplate'].toString(),
     ];
     expect(uriTemplates, contains('flutterpilot://app/widgets/{key}'));
     expect(uriTemplates, contains('flutterpilot://app/routes/{path}'));
   });
   ```
2. Verify reading a templated resource:
   ```dart
   test('resources/read with templated URI dispatches to template handler', () async {
     final response = await inspector.request('resources/read', {
       'uri': 'flutterpilot://app/widgets/test_key',
     });
     expect(response['error'], isNull);
   });
   ```
3. Run verification tests:
   ```bash
   dart test test/mcp_protocol_compliance_test.dart
   dart test test/tool_registration_test.dart
   dart analyze
   ```

## Done When
- [x] `resources/templates/list` returns both resource templates.
- [x] `resources/read` with `flutterpilot://app/widgets/{key}` resolves via the template handler.
- [x] Protocol compliance test passes.
- [x] Tool registration count remains 63 (0 tool budget impact).
- [x] PR #137 opened and verified.
