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
  final Map<String, RegisteredTool> _nativeTools = {};

  /// Shows the native tools only where they can work: an iOS app, with
  /// `xcrun` (screenshot) and `idb` (everything else) on this machine.
  /// Called after every VM connection; hidden until then.
  Future<void> _updateNativeToolVisibility(
    String? operatingSystem, {
    int? pid,
  }) async {
    final ios = operatingSystem == 'ios' && Platform.isMacOS;
    if (ios) _idb = await _findIdb();
    _simulatorApp = ios && pid != null ? await _findSimulatorApp(pid) : null;
    final idb = ios && _idb != null;
    final xcrun = ios && await _onPath('xcrun');
    if (staticTools) return;
    for (final MapEntry(key: name, value: tool) in _nativeTools.entries) {
      final usable = switch (name) {
        'native_screenshot' => xcrun,
        'native_open_app' => xcrun && _simulatorApp != null,
        _ => idb,
      };
      if (tool.enabled != usable) usable ? tool.enable() : tool.disable();
    }
  }

  /// The simulator app behind the connection. Simulator apps are processes
  /// on this Mac, so the VM's pid leads to the app bundle and the simulator
  /// it runs in. Null for apps on a phone.
  ({String bundleId, String udid})? _simulatorApp;

  static Future<({String bundleId, String udid})?> _findSimulatorApp(
    int pid,
  ) async {
    try {
      final ps = await Process.run('ps', ['-p', '$pid', '-o', 'comm=']);
      final executable = (ps.stdout as String).trim();
      final udid = RegExp(
        r'/CoreSimulator/Devices/([0-9A-Fa-f-]{36})/',
      ).firstMatch(executable)?.group(1);
      if (udid == null) return null;
      final plist = await Process.run('plutil', [
        '-extract',
        'CFBundleIdentifier',
        'raw',
        '-o',
        '-',
        '${File(executable).parent.path}/Info.plist',
      ]);
      final bundleId = (plist.stdout as String).trim();
      if (plist.exitCode != 0 || bundleId.isEmpty) return null;
      return (bundleId: bundleId, udid: udid);
    } catch (_) {
      return null;
    }
  }

  /// Physical pixels per point on the simulator's screen, from the SDK;
  /// kept for when the app is backgrounded and can't answer.
  double? _nativePixelRatio;

  /// From the SDK, or else (app backgrounded, no SDK) from the screen
  /// width in points that idb reports, given the screenshot's [pixelWidth].
  Future<double?> _pixelRatio(String udid, int pixelWidth) async {
    final ping = await _callExtensionRaw('ext.flutterpilot.ping', {});
    var ratio = (ping.data?['devicePixelRatio'] as num?)?.toDouble();
    if (ratio == null && _nativePixelRatio == null && _idb != null) {
      try {
        final r = await Process.run(_idb!, [
          'ui',
          'describe-all',
          '--udid',
          udid,
          '--json',
        ]);
        final app = (jsonDecode(r.stdout as String) as List)
            .whereType<Map>()
            .firstWhere((e) => e['type'] == 'Application');
        ratio = pixelWidth / ((app['frame'] as Map)['width'] as num);
      } catch (_) {}
    }
    return _nativePixelRatio = ratio ?? _nativePixelRatio;
  }

  /// The idb executable. `pip3 install --user fb-idb` puts it in
  /// `~/Library/Python/<version>/bin`, which is usually not on PATH.
  String? _idb;

  static Future<String?> _findIdb() async {
    if (await _onPath('idb')) return 'idb';
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    final candidates = [
      File('$home/.local/bin/idb'),
      if (Directory('$home/Library/Python').existsSync())
        for (final version in Directory('$home/Library/Python').listSync())
          File('${version.path}/bin/idb'),
    ];
    return candidates.where((f) => f.existsSync()).firstOrNull?.path;
  }

  static Future<bool> _onPath(String exe) async {
    try {
      final r = await Process.run('which', [exe]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static const String _unavailableReason =
      'Native automation tools require macOS with `idb` (for tap/text/button) '
      'and/or Xcode command-line tools (for screenshot) installed, targeting a '
      'booted iOS Simulator. Install idb with `brew install idb-companion` and '
      '`pip3 install fb-idb`, or use tap_widget/enter_text/capture_screenshot '
      'instead for anything inside the Flutter app itself.';

  Future<String?> _resolveSimulatorUdid(Map<String, dynamic> p) async {
    final explicit = p['simulatorUdid']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (_simulatorApp != null) return _simulatorApp!.udid;

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
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
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
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
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
    _nativeTools['native_screenshot'] = _tool(
      'native_screenshot',
      description:
          'Screenshot of the whole simulator screen, in points: unlike '
          'capture_screenshot it includes system alerts, the keyboard and '
          'other apps. Use when the Flutter screenshot does not show what is '
          'on top.',
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
                  text:
                      'simctl screenshot failed: ${result.stderr}\n$_unavailableReason',
                ),
              ],
            );
          }
          var bytes = await tempFile.readAsBytes();
          final decoded = img.decodePng(bytes);
          final ratio = decoded == null
              ? null
              : await _pixelRatio(udid, decoded.width);
          var note =
              'coordinates are physical pixels: divide by the '
              'screen scale (2 or 3) for native_tap';
          if (ratio != null && ratio > 1) {
            final image = decoded;
            if (image != null) {
              bytes = img.encodePng(
                img.copyResize(
                  image,
                  width: (image.width / ratio).round(),
                  interpolation: img.Interpolation.average,
                ),
              );
              note = 'in points, the coordinates native_tap takes';
            }
          }
          return CallToolResult(
            content: [
              ImageContent(data: base64Encode(bytes), mimeType: 'image/png'),
              TextContent(text: 'Native screenshot ($note).'),
            ],
          );
        } finally {
          if (await tempFile.exists()) await tempFile.delete();
        }
      },
    );

    _nativeTools['native_tap'] = _tool(
      'native_tap',
      description:
          'Taps the simulator screen at x/y in points, e.g. a permission '
          'alert\'s "Allow", which is not in the Flutter tree. Take the '
          'point from native_describe_screen. For the app\'s own widgets use '
          'tap_widget.',
      inputSchema: ToolInputSchema(
        properties: {
          'x': JsonSchema.number(description: 'X in points.'),
          'y': JsonSchema.number(description: 'Y in points.'),
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
        required: ['x', 'y'],
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
        // idb ui tap requires integer coordinates — widget/accessibility frames
        // are frequently fractional (e.g. 275.0), so round rather than pass through.
        final x = (p['x'] as num).round().toString();
        final y = (p['y'] as num).round().toString();
        final result = await Process.run(_idb ?? 'idb', [
          'ui',
          'tap',
          x,
          y,
          '--udid',
          udid,
        ]);
        if (result.exitCode != 0) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'idb ui tap failed: ${result.stderr}\n$_unavailableReason',
              ),
            ],
          );
        }
        return CallToolResult(
          content: [TextContent(text: 'Native tap at ($x, $y) on $udid.')],
        );
      },
    );

    _nativeTools['native_text'] = _tool(
      'native_text',
      description:
          'Types text into whatever has focus on the simulator, through the '
          'real iOS keyboard path: native alert fields, other apps. For the '
          'app\'s own text fields use enter_text.',
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
          return CallToolResult(
            isError: true,
            content: [TextContent(text: _unavailableReason)],
          );
        }
        final udid = await _resolveSimulatorUdid(p);
        if (udid == null) {
          return _noSimulatorError(await _listBootedSimulators());
        }
        final text = p['text'].toString();
        final result = await Process.run(_idb ?? 'idb', [
          'ui',
          'text',
          text,
          '--udid',
          udid,
        ]);
        if (result.exitCode != 0) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'idb ui text failed: ${result.stderr}\n$_unavailableReason',
              ),
            ],
          );
        }
        return CallToolResult(
          content: [TextContent(text: 'Native text entered on $udid.')],
        );
      },
    );

    _nativeTools['native_button'] = _tool(
      'native_button',
      description:
          'Presses a simulator hardware button. HOME backgrounds the app '
          '(iOS then suspends it; native_open_app brings it back).',
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
          return CallToolResult(
            isError: true,
            content: [TextContent(text: _unavailableReason)],
          );
        }
        final udid = await _resolveSimulatorUdid(p);
        if (udid == null) {
          return _noSimulatorError(await _listBootedSimulators());
        }
        final button = p['button'].toString();
        final result = await Process.run(_idb ?? 'idb', [
          'ui',
          'button',
          button,
          '--udid',
          udid,
        ]);
        if (result.exitCode != 0) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'idb ui button failed: ${result.stderr}\n$_unavailableReason',
              ),
            ],
          );
        }
        return CallToolResult(
          content: [TextContent(text: 'Pressed $button on $udid.')],
        );
      },
    );

    _nativeTools['native_describe_screen'] = _tool(
      'native_describe_screen',
      description:
          'What iOS shows on the simulator right now, one line per element '
          'with its role, label and tap point (points), including system '
          'alerts the Flutter tree does not have. Use before native_tap.',
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
        final result = await Process.run(_idb ?? 'idb', [
          'ui',
          'describe-all',
          '--udid',
          udid,
          '--json',
        ]);
        if (result.exitCode != 0) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'idb ui describe-all failed: ${result.stderr}\n$_unavailableReason',
              ),
            ],
          );
        }
        return CallToolResult(
          content: [TextContent(text: describeNativeScreen(result.stdout))],
        );
      },
    );

    _nativeTools['native_open_app'] = _tool(
      'native_open_app',
      description:
          'Brings the connected app back to the foreground on the iOS '
          'simulator (after native_button HOME, or when another app is in '
          'front), keeping its state. iOS suspends a backgrounded app, so '
          'every other tool fails until then.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final app = _simulatorApp;
        if (app == null) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'The connected app is not running in an iOS simulator.',
              ),
            ],
          );
        }
        final result = await Process.run('xcrun', [
          'simctl',
          'launch',
          app.udid,
          app.bundleId,
        ]);
        if (result.exitCode != 0) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(text: 'simctl launch failed: ${result.stderr}'),
            ],
          );
        }
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (_activeContext?.lifecycle != null &&
            _activeContext?.lifecycle != 'resumed' &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Brought ${app.bundleId} to the foreground (app state kept).',
            ),
          ],
        );
      },
    );
  }
}

/// One line per element of `idb ui describe-all --json`, with the point to
/// pass to native_tap, instead of ~400 bytes of JSON per element.
String describeNativeScreen(Object? json) {
  final List<Object?> elements;
  try {
    elements = jsonDecode(json.toString()) as List<Object?>;
  } catch (_) {
    return json.toString();
  }
  final lines = <String>[];
  for (final e in elements.whereType<Map>()) {
    final type = e['type']?.toString() ?? '?';
    final label = e['AXLabel']?.toString().trim() ?? '';
    final value = e['AXValue']?.toString().trim() ?? '';
    if (type == 'Application' || (label.isEmpty && value.isEmpty)) continue;
    final f = e['frame'];
    final at = f is Map
        ? ' → tap (${((f['x'] as num) + (f['width'] as num) / 2).round()}, '
              '${((f['y'] as num) + (f['height'] as num) / 2).round()})'
        : '';
    lines.add(
      '- $type "$label"${value.isEmpty ? '' : ' = "$value"'}'
      '${e['enabled'] == false ? ' (disabled)' : ''}$at',
    );
  }
  if (lines.isEmpty) {
    return 'Nothing native on screen with a label (Flutter content is not '
        'described here; use get_app_summary).';
  }
  return '${lines.join('\n')}\nCoordinates are points (native_tap).';
}
