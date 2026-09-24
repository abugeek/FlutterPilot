part of '../../flutterpilot_server.dart';

/// Tools that reach outside the Flutter engine's own rendering surface via
/// `idb`/`xcrun simctl`, for the one class of thing pure Dart-VM-service
/// automation structurally cannot see or touch: native OS chrome layered
/// above the Flutter view — iOS permission dialogs ("Allow Location"),
/// the system keyboard, Apple Pay sheets, SFSafariViewController. A tap
/// simulated through the Flutter gesture binding never reaches these,
/// because they are not part of the Flutter widget tree at all.
///
/// macOS + iOS Simulator only, best-effort. Every tool here degrades to a
/// clear error (not a crash) when `idb`/`simctl` are missing or no
/// simulator is booted — this is a narrow escape hatch alongside the
/// existing VM-service tools, not a replacement for them. Prefer
/// `tap_widget`/`enter_text` for anything inside the Flutter app itself;
/// reach for these only when a native dialog or the system keyboard is
/// blocking the screen.
mixin _NativeAutomationToolsMixin on _FlutterPilotServerBase {
  static const String _unavailableReason =
      'Native automation tools require macOS with `idb` (for tap/text/button) '
      'and/or Xcode command-line tools (for screenshot) installed, targeting a '
      'booted iOS Simulator. Install idb with `brew install idb-companion` and '
      '`pip3 install fb-idb`, or use tap_widget/enter_text/capture_screenshot '
      'instead for anything inside the Flutter app itself.';

  Future<String?> _resolveSimulatorUdid(Map<String, dynamic> p) async {
    final explicit = p['simulatorUdid']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    if (!Platform.isMacOS) return null;
    try {
      final result = await Process.run('xcrun', [
        'simctl',
        'list',
        'devices',
        'booted',
        '-j',
      ]);
      if (result.exitCode != 0) return null;
      final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final devices = decoded['devices'] as Map<String, dynamic>? ?? {};
      final booted = <Map<String, dynamic>>[];
      for (final list in devices.values) {
        if (list is List) {
          for (final d in list) {
            if (d is Map<String, dynamic> && d['state'] == 'Booted') {
              booted.add(d);
            }
          }
        }
      }
      if (booted.length == 1) return booted.first['udid'] as String?;
      return null;
    } catch (_) {
      return null;
    }
  }

  CallToolResult _noSimulatorError(List<Map<String, dynamic>> candidates) {
    if (candidates.isEmpty) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                'No booted iOS Simulator found and no simulatorUdid was given. '
                'Boot one (`xcrun simctl boot <udid>`) or pass simulatorUdid explicitly.',
          ),
        ],
      );
    }
    final list = candidates
        .map((d) => '  - ${d['name']} (${d['udid']})')
        .join('\n');
    return CallToolResult(
      isError: true,
      content: [
        TextContent(
          text:
              'Multiple simulators are booted — pass simulatorUdid to disambiguate:\n$list',
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _listBootedSimulators() async {
    try {
      final result = await Process.run('xcrun', [
        'simctl',
        'list',
        'devices',
        'booted',
        '-j',
      ]);
      if (result.exitCode != 0) return const [];
      final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final devices = decoded['devices'] as Map<String, dynamic>? ?? {};
      final booted = <Map<String, dynamic>>[];
      for (final list in devices.values) {
        if (list is List) {
          for (final d in list) {
            if (d is Map<String, dynamic> && d['state'] == 'Booted') {
              booted.add(d);
            }
          }
        }
      }
      return booted;
    } catch (_) {
      return const [];
    }
  }

  void _registerNativeAutomationTools() {
    server.registerTool(
      'native_screenshot',
      description:
          'Captures the simulator screen at the OS/framebuffer level via `xcrun simctl` — '
          'unlike capture_screenshot, this sees native dialogs, the system keyboard, and any '
          'OS chrome layered above the Flutter view. macOS + iOS Simulator only.',
      inputSchema: ToolInputSchema(
        properties: {
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
      ),
      callback: (p, e) async {
        if (!Platform.isMacOS) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: _unavailableReason)],
          );
        }
        final udid = await _resolveSimulatorUdid(p);
        if (udid == null) {
          return _noSimulatorError(await _listBootedSimulators());
        }
        final tempFile = File(
          '${Directory.systemTemp.path}/flutterpilot_native_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        try {
          final result = await Process.run('xcrun', [
            'simctl',
            'io',
            udid,
            'screenshot',
            tempFile.path,
          ]);
          if (result.exitCode != 0 || !await tempFile.exists()) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text: 'simctl screenshot failed: ${result.stderr}\n$_unavailableReason',
                ),
              ],
            );
          }
          final bytes = await tempFile.readAsBytes();
          return CallToolResult(
            content: [
              ImageContent(data: base64Encode(bytes), mimeType: 'image/png'),
              TextContent(text: 'Native screenshot captured ($udid).'),
            ],
          );
        } finally {
          if (await tempFile.exists()) await tempFile.delete();
        }
      },
    );

    server.registerTool(
      'native_tap',
      description:
          'Taps native screen coordinates via `idb ui tap` — reaches system permission dialogs, '
          'alerts, and other OS chrome that tap_widget/tap_at cannot see because they are not '
          'part of the Flutter widget tree. Use native_screenshot first to find coordinates. '
          'Requires idb (brew install idb-companion && pip3 install fb-idb). macOS + iOS Simulator only.',
      inputSchema: ToolInputSchema(
        properties: {
          'x': JsonSchema.number(description: 'X coordinate in the native screenshot\'s pixel space.'),
          'y': JsonSchema.number(description: 'Y coordinate in the native screenshot\'s pixel space.'),
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
        required: ['x', 'y'],
      ),
      callback: (p, e) async {
        if (!Platform.isMacOS) {
          return CallToolResult(isError: true, content: [TextContent(text: _unavailableReason)]);
        }
        final udid = await _resolveSimulatorUdid(p);
        if (udid == null) {
          return _noSimulatorError(await _listBootedSimulators());
        }
        // idb ui tap requires integer coordinates — widget/accessibility frames
        // are frequently fractional (e.g. 275.0), so round rather than pass through.
        final x = (p['x'] as num).round().toString();
        final y = (p['y'] as num).round().toString();
        final result = await Process.run('idb', ['ui', 'tap', x, y, '--udid', udid]);
        if (result.exitCode != 0) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'idb ui tap failed: ${result.stderr}\n$_unavailableReason')],
          );
        }
        return CallToolResult(content: [TextContent(text: 'Native tap at ($x, $y) on $udid.')]);
      },
    );

    server.registerTool(
      'native_text',
      description:
          'Types text into the currently-focused native field via `idb ui text` — for native '
          'alert text fields, Safari, or anything outside the Flutter engine. For text fields '
          'inside the Flutter app itself, use enter_text instead (it is faster and semantic). '
          'Requires idb. macOS + iOS Simulator only.',
      inputSchema: ToolInputSchema(
        properties: {
          'text': JsonSchema.string(description: 'Text to type.'),
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
        required: ['text'],
      ),
      callback: (p, e) async {
        if (!Platform.isMacOS) {
          return CallToolResult(isError: true, content: [TextContent(text: _unavailableReason)]);
        }
        final udid = await _resolveSimulatorUdid(p);
        if (udid == null) {
          return _noSimulatorError(await _listBootedSimulators());
        }
        final text = p['text'].toString();
        final result = await Process.run('idb', ['ui', 'text', text, '--udid', udid]);
        if (result.exitCode != 0) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'idb ui text failed: ${result.stderr}\n$_unavailableReason')],
          );
        }
        return CallToolResult(content: [TextContent(text: 'Native text entered on $udid.')]);
      },
    );

    server.registerTool(
      'native_button',
      description:
          'Presses a hardware button via `idb ui button` — HOME, LOCK, SIDE_BUTTON, SIRI, or '
          'APPLE_PAY. Requires idb. macOS + iOS Simulator only.',
      inputSchema: ToolInputSchema(
        properties: {
          'button': JsonSchema.string(
            enumValues: ['APPLE_PAY', 'HOME', 'LOCK', 'SIDE_BUTTON', 'SIRI'],
          ),
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
        required: ['button'],
      ),
      callback: (p, e) async {
        if (!Platform.isMacOS) {
          return CallToolResult(isError: true, content: [TextContent(text: _unavailableReason)]);
        }
        final udid = await _resolveSimulatorUdid(p);
        if (udid == null) {
          return _noSimulatorError(await _listBootedSimulators());
        }
        final button = p['button'].toString();
        final result = await Process.run('idb', ['ui', 'button', button, '--udid', udid]);
        if (result.exitCode != 0) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'idb ui button failed: ${result.stderr}\n$_unavailableReason')],
          );
        }
        return CallToolResult(content: [TextContent(text: 'Pressed $button on $udid.')]);
      },
    );

    server.registerTool(
      'native_describe_screen',
      description:
          'Returns the native accessibility tree (labels, frames, roles) for whatever is on '
          'screen right now via `idb ui describe-all` — including system dialogs and alerts '
          'that are invisible to get_widget_tree. Use this instead of guessing pixel '
          'coordinates from a screenshot before calling native_tap: it gives you the actual '
          'button labels and frames for "Allow"/"Don\'t Allow"-style native alerts. '
          'Requires idb. macOS + iOS Simulator only.',
      inputSchema: ToolInputSchema(
        properties: {
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
      ),
      callback: (p, e) async {
        if (!Platform.isMacOS) {
          return CallToolResult(isError: true, content: [TextContent(text: _unavailableReason)]);
        }
        final udid = await _resolveSimulatorUdid(p);
        if (udid == null) {
          return _noSimulatorError(await _listBootedSimulators());
        }
        final result = await Process.run('idb', ['ui', 'describe-all', '--udid', udid, '--json']);
        if (result.exitCode != 0) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(text: 'idb ui describe-all failed: ${result.stderr}\n$_unavailableReason'),
            ],
          );
        }
        return CallToolResult(content: [TextContent(text: result.stdout as String)]);
      },
    );
  }
}
