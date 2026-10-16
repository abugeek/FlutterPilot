/// Truthful effect modeling and argument-aware retry safety (roadmap task 01).
///
/// Two questions are answered here, and they are deliberately separate from
/// the public MCP annotations in `tool_annotations.dart` and from destructive
/// authorization:
///
/// 1. **Scheduling** — must this service-extension call be serialized behind
///    other mutations instead of running on the concurrent read path?
/// 2. **Replay** — after a lost response (the VM Service connection dropped
///    mid-call), may the call be sent again?
///
/// The old rule inferred both from the extension *name*: any `get…`/`list…`
/// prefix was treated as a read and replayed. That is wrong for a name that
/// only looks observational (`auditScreenHealth` navigates when a tool sweeps
/// routes; `getStateHistory` clears the history when `clear: true` is passed)
/// and it cannot see diagnostic clears at all. Replay here is decided from a
/// reviewed inventory plus the arguments of the specific call.
///
/// The rule that matters most: **an extension that is not in the inventory is
/// never replayed.** A new plugin extension that forgets to register here
/// executes at most once and reports uncertainty, rather than duplicating an
/// action after a reconnect.
library;

/// Where a service-extension call sits on the two independent axes above.
class ExtensionPolicy {
  /// It changes the app, or FlutterPilot's captured diagnostic state, so it
  /// must be serialized behind other mutations and kept off the read path.
  final bool mutating;

  /// After a lost response it may be sent again. Only a pure observation is
  /// safe: an action, a diagnostic clear, or an unknown extension executes at
  /// most once and reports uncertainty instead.
  final bool replaySafe;

  /// The extension is named in the reviewed inventory. Unknown extensions are
  /// treated conservatively (mutating, never replayed).
  final bool known;

  const ExtensionPolicy({
    required this.mutating,
    required this.replaySafe,
    this.known = true,
  });

  @override
  String toString() =>
      'ExtensionPolicy(mutating: $mutating, replaySafe: $replaySafe, '
      'known: $known)';
}

const _read = ExtensionPolicy(mutating: false, replaySafe: true);
const _acts = ExtensionPolicy(mutating: true, replaySafe: false);

/// Empties FlutterPilot's capture of logs, requests or state changes. It
/// changes no app data, but it must not be replayed: a retry after a lost
/// response would erase evidence collected between the first attempt and the
/// retry. Serialized like a mutation because a later read must see the clear.
const _diagnosticClear = ExtensionPolicy(mutating: true, replaySafe: false);

/// Not in the inventory: an unknown extension. Conservative in both
/// directions — serialized, and never replayed.
const _unknown = ExtensionPolicy(
  mutating: true,
  replaySafe: false,
  known: false,
);

/// Extensions that only observe: they change neither the app nor
/// FlutterPilot's captured state, so they are safe to run concurrently and to
/// send again after a lost response.
const readOnlyExtensions = <String>{
  // FlutterPilot inspection.
  'ext.flutterpilot.auditScreenHealth',
  'ext.flutterpilot.captureScreenshot',
  'ext.flutterpilot.getAppSnapshot',
  'ext.flutterpilot.getBlocStates',
  'ext.flutterpilot.getCapabilities',
  'ext.flutterpilot.getConnectivity',
  'ext.flutterpilot.getConnectivityHistory',
  'ext.flutterpilot.getErrors',
  'ext.flutterpilot.getFirebaseAuth',
  'ext.flutterpilot.getFrameBudgetProfile',
  'ext.flutterpilot.getGoRouterConfig',
  'ext.flutterpilot.getGoRouterHistory',
  'ext.flutterpilot.getGoRouterState',
  'ext.flutterpilot.getHiveContents',
  'ext.flutterpilot.getHttpMocks',
  'ext.flutterpilot.getInteractiveElements',
  'ext.flutterpilot.getNavigationStack',
  'ext.flutterpilot.getNetworkLogs',
  'ext.flutterpilot.getRiverpodStates',
  'ext.flutterpilot.getSecureStorageKeys',
  'ext.flutterpilot.getSemanticsTree',
  'ext.flutterpilot.getSharedPreferences',
  'ext.flutterpilot.getStateHistory',
  'ext.flutterpilot.getSummary',
  'ext.flutterpilot.getSupabaseAuth',
  'ext.flutterpilot.getSupabaseRealtime',
  'ext.flutterpilot.getWidgetProperties',
  'ext.flutterpilot.getWidgetTree',
  'ext.flutterpilot.getWidgetTreeDiff',
  'ext.flutterpilot.inspectWidget',
  'ext.flutterpilot.listCustomTools',
  'ext.flutterpilot.listDriftTables',
  'ext.flutterpilot.listSqfliteDatabases',
  'ext.flutterpilot.listSqfliteTables',
  'ext.flutterpilot.ping',
  'ext.flutterpilot.protocol',
  'ext.flutterpilot.queryDrift',
  'ext.flutterpilot.queryFirestore',
  'ext.flutterpilot.querySqflite',
  'ext.flutterpilot.querySupabaseTable',
  'ext.flutterpilot.readSecureStorageKey',
  'ext.flutterpilot.screenNow',
  // Data snapshots a scenario/scenario-list read takes; they write nothing.
  'ext.flutterpilot.dumpDrift',
  'ext.flutterpilot.dumpHive',
  'ext.flutterpilot.dumpSqflite',
  // Assertions and waits observe; re-running them is harmless.
  'ext.flutterpilot.assertTextVisible',
  'ext.flutterpilot.assertWidgetCount',
  'ext.flutterpilot.assertWidgetDisabled',
  'ext.flutterpilot.assertWidgetEnabled',
  'ext.flutterpilot.assertWidgetVisible',
  'ext.flutterpilot.waitForAnimation',
  'ext.flutterpilot.waitForCondition',
  'ext.flutterpilot.waitForRoute',
  'ext.flutterpilot.waitForState',
  'ext.flutterpilot.waitForWidget',
  // Flutter / VM framework reads the server uses directly.
  'ext.dart.io.getHttpProfile',
  'ext.dart.io.getHttpProfileRequest',
  'ext.dart.io.httpEnableTimelineLogging',
  'ext.flutter.didSendFirstFrameEvent',
  'ext.flutter.inspector.disposeGroup',
  'ext.flutter.inspector.getLayoutExplorerNode',
  'ext.flutter.inspector.getProperties',
  'ext.flutter.inspector.getRootWidget',
  'ext.flutter.inspector.getRootWidgetTree',
  'ext.flutter.inspector.screenshot',
};

/// Extensions that change the app (or write a file) and must never be replayed
/// after a lost response: the effect may already have happened.
const mutatingExtensions = <String>{
  'ext.flutter.brightnessOverride',
  'ext.flutter.debugPaint',
  'ext.flutter.exit',
  'ext.flutter.profileUserWidgetBuilds',
  'ext.flutter.repaintRainbow',
  'ext.flutter.timeDilation',
  'ext.flutterpilot.addHttpMock',
  'ext.flutterpilot.batchSetState',
  'ext.flutterpilot.callCustomTool',
  'ext.flutterpilot.clearHttpMocks',
  'ext.flutterpilot.clearSharedPreferences',
  'ext.flutterpilot.clearTextField',
  'ext.flutterpilot.deleteSecureStorageKey',
  'ext.flutterpilot.doubleTapWidget',
  'ext.flutterpilot.dragWidget',
  'ext.flutterpilot.enterText',
  'ext.flutterpilot.executeActionChain',
  'ext.flutterpilot.fillForm',
  'ext.flutterpilot.focusWidget',
  'ext.flutterpilot.goRouterNavigate',
  'ext.flutterpilot.longPressWidget',
  'ext.flutterpilot.navigateTo',
  'ext.flutterpilot.pinchZoomWidget',
  'ext.flutterpilot.platformChannel',
  'ext.flutterpilot.prepareRestart',
  'ext.flutterpilot.pressBack',
  'ext.flutterpilot.pressKey',
  'ext.flutterpilot.profiling',
  'ext.flutterpilot.pumpFrames',
  'ext.flutterpilot.restoreDrift',
  'ext.flutterpilot.restoreHive',
  'ext.flutterpilot.restoreSqflite',
  'ext.flutterpilot.scrollIntoView',
  'ext.flutterpilot.secondaryTapWidget',
  'ext.flutterpilot.setKeyboardInset',
  'ext.flutterpilot.setLocale',
  'ext.flutterpilot.setOrientation',
  'ext.flutterpilot.setSecureStorageKey',
  'ext.flutterpilot.setSharedPreference',
  'ext.flutterpilot.setSliderValue',
  'ext.flutterpilot.setState',
  'ext.flutterpilot.setTextScaleFactor',
  'ext.flutterpilot.simulateDeepLink',
  'ext.flutterpilot.simulateNetwork',
  'ext.flutterpilot.supabaseRefreshSession',
  'ext.flutterpilot.supabaseSignOut',
  'ext.flutterpilot.swipeWidget',
  'ext.flutterpilot.tapWidget',
  'ext.flutterpilot.testRecording',
  'ext.flutterpilot.toggleCheckbox',
  'ext.flutterpilot.unfocusAll',
};

/// Extensions that empty a FlutterPilot diagnostic buffer. They change no app
/// data but must not be replayed (see [_diagnosticClear]).
const diagnosticClearExtensions = <String>{
  'ext.dart.io.clearHttpProfile',
  'ext.flutterpilot.clearDebugLogs',
};

/// Extensions whose effect depends on their arguments. Each entry returns the
/// policy for the given call, so a plain read and its clearing mode are not
/// forced into the same bucket.
const _argumentAware = <String, ExtensionPolicy Function(Map<String, dynamic>)>{
  'ext.flutterpilot.getStateHistory': _getStateHistoryPolicy,
};

ExtensionPolicy _getStateHistoryPolicy(Map<String, dynamic> args) =>
    _requestsClear(args) ? _diagnosticClear : _read;

bool _requestsClear(Map<String, dynamic> args) {
  final value = args['clear'];
  return value == true || value == 'true';
}

/// The reviewed policy for a single call to [extension].
///
/// Argument-aware overrides win first, then the name-based inventory. An
/// extension in none of the sets is unknown: serialized and never replayed.
ExtensionPolicy extensionPolicyOf(
  String extension, [
  Map<String, dynamic>? parameters,
]) {
  final args = parameters ?? const <String, dynamic>{};
  final argument = _argumentAware[extension];
  if (argument != null) return argument(args);
  if (readOnlyExtensions.contains(extension)) return _read;
  if (diagnosticClearExtensions.contains(extension)) return _diagnosticClear;
  if (mutatingExtensions.contains(extension)) return _acts;
  return _unknown;
}

/// The outcome of running a call through [runWithReplay].
class ExtensionReplay<T> {
  /// The result to report: the first response, or the replay's response when
  /// [replayed] is true.
  final T result;

  /// The call was sent a second time because its first response was lost.
  final bool replayed;

  /// The first response was lost and the call was not safe to replay, so the
  /// effect may or may not have happened. The caller reports this honestly
  /// instead of pretending the call succeeded or failed.
  final bool uncertain;

  const ExtensionReplay(
    this.result, {
    this.replayed = false,
    this.uncertain = false,
  });
}

/// Runs [callOnce]; if [lostResponse] says its result means the response never
/// arrived, reconnects and — only when [policy] marks the call replay-safe and
/// [canReplay] agrees — sends it again.
///
/// This is the single place a service-extension call is replayed, so an
/// action, a diagnostic clear, or an unknown extension executes at most once.
Future<ExtensionReplay<T>> runWithReplay<T>({
  required ExtensionPolicy policy,
  required Future<T> Function() callOnce,
  required bool Function(T result) lostResponse,
  required Future<void> Function() reconnect,
  bool Function()? canReplay,
}) async {
  final first = await callOnce();
  if (!lostResponse(first)) return ExtensionReplay(first);
  await reconnect();
  if (!policy.replaySafe || !(canReplay?.call() ?? true)) {
    return ExtensionReplay(first, uncertain: true);
  }
  return ExtensionReplay(await callOnce(), replayed: true);
}
