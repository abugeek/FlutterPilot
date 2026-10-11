/// Why the app did not answer a call. A timeout used to say "the app may be
/// unresponsive", and field sessions relaunched the app to find out; the VM
/// can say whether its UI isolate is spinning in Dart code (and where),
/// stopped in the debugger, blocked outside Dart, or fine.
library;

import 'dart:async';

import 'package:vm_service/vm_service.dart';

/// Whether [toolText] is one of the server's "no answer from the app"
/// errors.
bool isNoAnswer(String toolText) =>
    toolText.contains('No answer from the app within') ||
    toolText.contains('Extension call timed out');

/// One frame as `function (uri:line)`.
String describeFrame(Frame frame) {
  final name = frame.function?.name ?? frame.code?.name ?? '<unknown>';
  final owner = frame.function?.owner;
  final type = owner is ClassRef ? '${owner.name}.' : '';
  final uri = frame.location?.script?.uri;
  final line = frame.location?.line;
  return '$type$name'
      '${uri == null ? '' : ' ($uri${line == null ? '' : ':$line'})'}';
}

/// The top of [frames]: the first [max], with the first frame from the
/// app's own code ([appUriPrefixes]) pointed out when it is further down.
String describeStack(
  List<Frame> frames, {
  int max = 8,
  List<String> appUriPrefixes = const [],
}) {
  bool isApp(Frame f) {
    final uri = f.location?.script?.uri ?? '';
    return appUriPrefixes.any(uri.startsWith);
  }

  final lines = [for (final f in frames.take(max)) '  ${describeFrame(f)}'];
  final firstApp = frames.indexWhere(isApp);
  if (firstApp >= max) {
    lines.add('  …\n  ${describeFrame(frames[firstApp])}  <- app code');
  }
  return lines.join('\n');
}

/// Looks at the UI isolate [isolateId] after a call went unanswered and
/// says what it is doing. Never leaves the isolate paused: if a pause it
/// asked for lands late, it is resumed then.
Future<String> diagnoseNoAnswer(
  VmService vm,
  String isolateId, {
  List<String> appUriPrefixes = const [],
  Duration pauseWait = const Duration(seconds: 2),
}) async {
  final isolate = await vm.getIsolate(isolateId);
  final paused = isolate.pauseEvent;
  final kind = paused?.kind;
  if (kind != null &&
      kind != EventKind.kResume &&
      kind != EventKind.kNone &&
      kind != EventKind.kPauseInterrupted) {
    final at = paused?.topFrame == null
        ? ''
        : ' at ${describeFrame(paused!.topFrame!)}';
    final why = switch (kind) {
      EventKind.kPauseBreakpoint => 'at a breakpoint',
      EventKind.kPauseException => 'on an exception ("pause on exceptions")',
      EventKind.kPauseStart => 'at its start (launched with --start-paused)',
      EventKind.kPauseExit => 'at exit: its main isolate has finished',
      _ => 'in the debugger ($kind)',
    };
    return 'WHY: the app is paused $why$at. Nothing runs until it is '
        'resumed from the IDE or debugger that paused it.';
  }

  // Ask it to stop: Dart code that is running stops at once, wherever it is.
  final interrupted = Completer<void>();
  late final StreamSubscription<Event> sub;
  var gaveUp = false;
  sub = vm.onDebugEvent.listen((event) {
    if (event.isolate?.id != isolateId ||
        event.kind != EventKind.kPauseInterrupted) {
      return;
    }
    if (!interrupted.isCompleted) interrupted.complete();
    if (gaveUp) {
      // The pause landed after we stopped waiting: don't leave it there.
      unawaited(vm.resume(isolateId).then((_) {}, onError: (_) {}));
      unawaited(sub.cancel());
    }
  });
  try {
    await vm.streamListen(EventStreams.kDebug);
  } on RPCError {
    // Already subscribed.
  }
  await vm.pause(isolateId);
  try {
    await interrupted.future.timeout(pauseWait);
  } on TimeoutException {
    gaveUp = true;
    return 'WHY: the app\'s UI isolate is not running Dart code and did not '
        'stop when asked: it is blocked outside Dart (a synchronous native '
        'or platform-channel call, a native modal dialog, a deadlock in '
        'native code). If hot_reload(restart: true) gets no answer either, '
        'launch_app(relaunch: true) starts the app again.';
  }
  try {
    final frames = (await vm.getStack(isolateId)).frames ?? const <Frame>[];
    if (frames.isEmpty) {
      return 'WHY: the app is not hung: its UI isolate is idle and answers '
          'the debugger. The call itself was waiting for something that '
          'did not happen (a frame while nothing draws, an animation that '
          'never settles, a dialog). get_app_summary shows the screen.';
    }
    return 'WHY: the app\'s UI isolate was busy in Dart code and answered '
        'only when interrupted. It was here:\n'
        '${describeStack(frames, appUriPrefixes: appUriPrefixes)}\n'
        'If the same place shows on a second timeout it is a loop or a '
        'long synchronous computation there. A hot restart cannot '
        'interrupt code that never returns: fix it, then '
        'launch_app(relaunch: true).';
  } finally {
    await sub.cancel();
    try {
      await vm.resume(isolateId);
    } catch (_) {}
  }
}
