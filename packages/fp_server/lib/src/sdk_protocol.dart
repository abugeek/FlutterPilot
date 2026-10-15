/// The contract between this server and the fp_sdk inside the
/// app, as a number both sides carry: the app's SDK is pinned in its
/// pubspec and the server is a compiled binary, so one is often older than
/// the other, and package versions don't move with every change.
///
/// Raise [sdkProtocol] and `FlutterPilot.protocol` (fp_sdk)
/// together whenever the server starts relying on something new in the SDK,
/// and say in [protocolAdds] what an app without it misses.
library;

/// What this server was built for.
const sdkProtocol = 2;

/// What each protocol added, for an app whose SDK is older.
const protocolAdds = {
  2:
      'the screen after wait_for and navigate_to, and "still starting" '
      'in the summary and screenshot error',
};

/// One line when the app's SDK ([app]) and this server differ, else null.
String? protocolNote(int app, {int server = sdkProtocol}) {
  if (app == server) return null;
  if (app > server) {
    return "The app's fp_sdk is newer than this server (protocol "
        '$app, server $server): the server may not know what the SDK '
        'offers. Rebuild the server ("flutterpilot mcp install") and '
        'restart the MCP client.';
  }
  final missing = [for (var v = app + 1; v <= server; v++) ?protocolAdds[v]];
  return "The app's fp_sdk is older than this server (protocol "
      '$app, server $server)'
      '${missing.isEmpty ? '' : ', so it lacks: ${missing.join('; ')}'}. '
      'Update the fp_sdk (and plugin) versions or git ref in the '
      "app's pubspec.yaml, then launch_app(relaunch: true).";
}
