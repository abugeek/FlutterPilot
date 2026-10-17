import 'package:mcp_dart/mcp_dart.dart';

/// Tells the client how far a long tool call has got (MCP
/// `notifications/progress`) and whether the client has cancelled it.
///
/// Only when the client asked: a request without `_meta.progressToken` gets no
/// notification at all, so nothing changes for a client that never asks. A
/// client that does ask can show the stage to its user and — the reason this
/// exists — keep a call alive past its own request timeout (the TypeScript SDK's
/// `resetTimeoutOnProgress`), where a `launch_app` build of a few minutes was
/// otherwise cut off at the client's 60 s default with no answer at all.
///
/// The spec requires `progress` to increase with every notification for one
/// token. Composites hand the same request to the tools they run
/// (`run_on_devices` runs `execute_action_chain` on several devices at once),
/// so every reporter made for one request shares one counter.
class ToolProgress {
  /// A reporter for the call [extra] belongs to; null [extra] (a tool run
  /// from a test or another tool with no request) reports nothing.
  ToolProgress(
    this._extra, {
    this.total,
    this.heartbeat = const Duration(seconds: 5),
  });

  final RequestHandlerExtra? _extra;

  /// How many units [advance] will count to, when known up front.
  final double? total;

  /// How often [tick] repeats an unchanged message, so a client that resets
  /// its timeout on progress keeps waiting through a long silent stretch.
  final Duration heartbeat;

  static final _shared = Expando<_RequestProgress>('ToolProgress');

  Object? get _token => _extra?.meta?['progressToken'];

  /// Whether the client asked for progress on this call.
  bool get requested {
    final token = _token;
    return token is String || token is int;
  }

  /// Whether the client cancelled this call (`notifications/cancelled`). Its
  /// answer will be dropped, so a tool stops before the next thing it would
  /// do to the app.
  bool get cancelled => _extra?.signal.aborted ?? false;

  _RequestProgress get _state => _shared[_extra!] ??= _RequestProgress();

  /// One unit of work is done: [message] says which.
  Future<void> advance(String message) async {
    if (!requested) return;
    await _send(message);
  }

  /// Still waiting, nothing finished: sent when [message] changes, otherwise
  /// at most once per [heartbeat].
  Future<void> tick(String message) async {
    if (!requested) return;
    final state = _state;
    final last = state.sentAt;
    if (message == state.message &&
        last != null &&
        DateTime.now().difference(last) < heartbeat) {
      return;
    }
    await _send(message);
  }

  Future<void> _send(String message) async {
    final extra = _extra!;
    final state = _state;
    // Claimed before the await, so concurrent reporters on one request never
    // send the same or a smaller number.
    final progress = ++state.progress;
    state
      ..message = message
      ..sentAt = DateTime.now();
    try {
      await extra.sendNotification(
        JsonRpcProgressNotification(
          progressParams: ProgressNotification(
            progressToken: _token,
            progress: progress.toDouble(),
            total: total == null || total! < progress ? null : total,
            message: message,
          ),
        ),
      );
    } catch (_) {
      // A closed transport or a client that went away: progress is a
      // courtesy, never a reason for the tool itself to fail.
    }
  }
}

class _RequestProgress {
  int progress = 0;
  String? message;
  DateTime? sentAt;
}
