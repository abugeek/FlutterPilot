# 25 · Field Findings Remediation (Bridge Logging & Selector Matching)

**Branch:** `fix/selector-and-bridge-logging` from `main` · **Depends on:** PR #135 merged

## Goal
Resolve two ergonomic findings identified during the live `fp_lab_shop` verification (Findings 351 and 352):
1. **Bridge Call Telemetry (Finding 351)**: `tool/.fp/calls.jsonl` logged `"tool": null` for generic MCP `method` calls (resources/list, prompts/get, etc.).
2. **Form Selector Key Matching (Finding 352)**: In `fill_form`, selectors using the syntax `Type['key']` (e.g., `TextField['checkout_name']` or `Checkbox['accept_terms']`) failed to resolve because `Type['value']` only compared against visible labels/tooltips rather than widget keys.

## Implementation Details

### 1. Merge PR #135 & Sync Main
```bash
gh pr merge 135 --merge
git checkout main
git pull origin main
git branch -d docs/field-test-sprint5
git checkout -b fix/selector-and-bridge-logging
```

### 2. Fix Bridge Call Telemetry (Finding 351)
In `packages/flutterpilot_server/tool/fp_bridge.dart` (around line 150):
Record `body['method'] ?? body['name'] ?? body['uri'] ?? 'unknown'` instead of `body['name']` so that resource reads and prompt calls log their actual target instead of `null`:
```dart
calls.writeAsStringSync(
  '${jsonEncode({'tool': body['method'] ?? body['name'] ?? body['uri'] ?? 'unknown', 'ms': sw.elapsedMilliseconds, 'isError': isError, 'chars': out.length})}\n',
  mode: FileMode.append,
);
```

### 3. Fix Form & Widget Selector Key Matching (Finding 352)
In `packages/flutterpilot_sdk/lib/src/widget_inspector.dart`:
In `_findSingleElementUnder`, inside the `if (typeTarget != null ...)` evaluation block:
When matching `Type['valueTarget']`, also check whether `valueTarget` matches `cleanKey` or semantics `id` in addition to widget labels.
```dart
final value = valueTarget.toLowerCase();
final keyMatches =
    (cleanKey != null && cleanKey.toLowerCase() == value) ||
    (id != null && id.toLowerCase() == value);

if (keyMatches) {
  consider(97); // Higher than label match (96) so exact key wins
} else if (ownLabel == value || (text == value && !label.glyphOnly)) {
  consider(96);
...
```

### 4. Tests
1. In `packages/flutterpilot_sdk/test/widget_inspector_test.dart`:
   Add a test verifying that `PilotWidgetInspector.findElement("TextField['custom_key']")` resolves a `TextField` with `Key('custom_key')` even if its text/hint is empty or different.
2. Run `dart test` in `packages/flutterpilot_sdk`.
3. Run `dart analyze` across all packages.

## Done When
- [x] PR #135 merged into `main`.
- [x] `fp_bridge.dart` logs non-null names for `method` calls in `calls.jsonl`.
- [x] `findElement` resolves `Type['key']` selectors accurately.
- [x] SDK tests pass (all 253 tests).
- [x] PR #136 opened and verified.
