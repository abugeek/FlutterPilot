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
    _nativeOs = operatingSystem;
    _androidPid = pid;
    final ios = operatingSystem == 'ios' && Platform.isMacOS;
    final android = operatingSystem == 'android';
    _adb = android ? await findAdb() : null;
    _androidPackage = android && _adb != null && pid != null
        ? await androidPackageOfPid(_adb!, await _androidSerial(null), pid)
        : null;
    if (android && _adb != null) await _rememberAdbForward();
    if (ios) _idb = await _findIdb();
    _simulatorApp = ios && pid != null ? await _findSimulatorApp(pid) : null;
    _iosDeviceApp = ios && pid != null && _simulatorApp == null
        ? await findIosDeviceApp(pid)
        : null;
    final idb = ios && _idb != null;
    final xcrun = ios && await _onPath('xcrun');
    if (staticTools) return;
    for (final MapEntry(key: name, value: tool) in _nativeTools.entries) {
      final usable = android
          ? _adb != null
          : switch (name) {
              'native_screenshot' => xcrun,
              'native_open_app' =>
                xcrun && (_simulatorApp != null || _iosDeviceApp != null),
              _ => idb,
            };
      if (tool.enabled != usable) usable ? tool.enable() : tool.disable();
    }
  }

  /// The physical iPhone and bundle id behind the connection, if it is one.
  @override
  ({String device, String bundleId})? _iosDeviceApp;

  /// The connected app's operating system (`ios`, `android`, ...).
  String? _nativeOs;

  /// The VM's process id (on the phone when the app runs on one).
  int? _androidPid;

  /// The adb executable, when the connected app runs on Android.
  String? _adb;

  /// The Android application id of the connected app.
  String? _androidPackage;

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
          'serial': JsonSchema.string(description: 'Android adb serial.'),
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
      ),
      callback: (p, e) async {
        if (_nativeOs == 'android') {
          return _androidNative('native_screenshot', p);
        }
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
          'serial': JsonSchema.string(description: 'Android adb serial.'),
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
        required: ['x', 'y'],
      ),
      callback: (p, e) async {
        if (_nativeOs == 'android') return _androidNative('native_tap', p);
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
          'serial': JsonSchema.string(description: 'Android adb serial.'),
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
        required: ['text'],
      ),
      callback: (p, e) async {
        if (_nativeOs == 'android') return _androidNative('native_text', p);
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
            enumValues: [
              'APPLE_PAY',
              'HOME',
              'LOCK',
              'SIDE_BUTTON',
              'SIRI',
              'BACK',
              'WAKEUP',
            ],
          ),
          'serial': JsonSchema.string(description: 'Android adb serial.'),
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
        required: ['button'],
      ),
      callback: (p, e) async {
        if (_nativeOs == 'android') return _androidNative('native_button', p);
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
          'serial': JsonSchema.string(description: 'Android adb serial.'),
          'simulatorUdid': JsonSchema.string(
            description:
                'Target simulator UDID. Omit to auto-detect when exactly one simulator is booted.',
          ),
        },
      ),
      callback: (p, e) async {
        if (_nativeOs == 'android') {
          return _androidNative('native_describe_screen', p);
        }
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
        if (_nativeOs == 'android') return _androidNative('native_open_app', p);
        if (_iosDeviceApp case final phone?) {
          final error = await launchOnIosDevice(phone.device, phone.bundleId);
          if (error != null) {
            return _androidError('devicectl launch failed: $error');
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
                    'Brought ${phone.bundleId} to the foreground on the '
                    'iPhone (app state kept).',
              ),
            ],
          );
        }
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

  /// The `adb forward` that carries the VM service to the phone: kept so it
  /// can be made again when the cable or the adb server drops it (the app
  /// keeps running on the phone, the port on this Mac is just gone).
  ({int port, String serial, String remote})? _adbForward;

  Future<void> _rememberAdbForward() async {
    final adbPath = _adb;
    if (adbPath == null) return;
    final list = await adb(adbPath, null, ['forward', '--list']);
    if (list == null) return;
    final forwards = parseAdbForwards(list.stdout as String);
    final port = Uri.tryParse(_activeContext?.uri ?? '')?.port;
    // flutter run may put its own proxy port in the URI: then the adb
    // forward behind it is the one of this phone that still answers.
    var mine = forwards.where((f) => f.local == 'tcp:$port').toList();
    if (mine.isEmpty) {
      final serial = await _androidSerial(null);
      final live = <AdbForward>[];
      for (final f in forwards.where((f) => f.serial == serial)) {
        final local = int.tryParse(f.local.replaceFirst('tcp:', ''));
        if (local != null && await portAnswersHttp(local)) live.add(f);
      }
      mine = live.length == 1 ? live : const [];
    }
    if (mine.length != 1) return;
    final f = mine.single;
    _adbForward = (
      port: int.parse(f.local.replaceFirst('tcp:', '')),
      serial: f.serial,
      remote: f.remote,
    );
  }

  /// Reaches an app whose `flutter run` is gone (the cable dropped and its
  /// service proxy died with it): its VM service address is in logcat from
  /// when it started. Forwards that port and returns the new URI, else null.
  @override
  Future<String?> _adoptAndroidApp() async {
    final adbPath = _adb;
    final pid = _androidPid;
    final serial = _adbForward?.serial ?? await _androidSerial(null);
    if (adbPath == null || pid == null || serial == null) return null;
    final log = await adb(adbPath, serial, [
      'logcat',
      '-d',
      '-v',
      'brief',
      '-s',
      'flutter:I',
    ]);
    if (log == null || log.exitCode != 0) return null;
    final vm = parseVmServiceFromLogcat(log.stdout as String, pid);
    if (vm == null) return null;
    final fwd = await adb(adbPath, serial, [
      'forward',
      'tcp:0',
      'tcp:${vm.devicePort}',
    ]);
    final hostPort = int.tryParse('${fwd?.stdout}'.trim());
    if (fwd == null || fwd.exitCode != 0 || hostPort == null) return null;
    return 'ws://127.0.0.1:$hostPort/${vm.token}/ws';
  }

  /// On a device where nothing here can tap a system dialog (a real
  /// iPhone): what the app asked the platform for that may have opened one,
  /// and how to avoid it. Null where the native tools can tap it, or when no
  /// permission call was made.
  @override
  Future<String?> _permissionDialogHint() async {
    if (_allTools['native_tap']?.enabled == true) return null;
    final calls = await _callExtensionRaw(
      'ext.flutterpilot.platformChannel',
      {},
    );
    if (calls.isError) return null;
    if (calls.data?['installed'] != true) {
      return '  Nothing here can tap a system dialog on this device. If the '
          'action opened one, dismiss it by hand. Putting '
          'FlutterPilot.initialize() first in main() (before '
          'WidgetsFlutterBinding.ensureInitialized()) would let '
          'mock_platform_channel answer the permission call instead.';
    }
    return permissionCallsHint((calls.data?['calls'] as List?) ?? const []) ??
        '  Nothing here can tap a system dialog on this device: if the '
            'action opened one, dismiss it by hand.';
  }

  /// Makes the remembered forward again if it is gone and the phone is
  /// attached; true when it did.
  @override
  Future<bool> _restoreAdbForward() async {
    final known = _adbForward;
    final adbPath = _adb;
    if (known == null || adbPath == null) return false;
    final list = await adb(adbPath, null, ['forward', '--list']);
    if (list == null ||
        parseAdbForwards(list.stdout as String).any(
          (f) => f.serial == known.serial && f.local == 'tcp:${known.port}',
        )) {
      return false; // still there: the app is what is not answering
    }
    final r = await adb(adbPath, known.serial, [
      'forward',
      'tcp:${known.port}',
      known.remote,
    ]);
    return r != null && r.exitCode == 0;
  }

  // ---------------------------------------------------------------------------
  // Is the phone fit to drive?
  // ---------------------------------------------------------------------------

  PhoneState? _phoneStateCache;
  DateTime? _phoneStateAt;

  /// Awake/locked state of the physical phone the app runs on (Android over
  /// adb, an iPhone over devicectl); null for simulators, emulators-less
  /// desktops, or when it cannot be read. Cached for a few seconds.
  @override
  Future<PhoneState?> _phoneState() async {
    final at = _phoneStateAt;
    if (at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 5)) {
      return _phoneStateCache;
    }
    PhoneState? state;
    try {
      if (_nativeOs == 'android') {
        final adbPath = _adb ?? await findAdb();
        if (adbPath != null) {
          final s = await readAndroidDeviceState(
            adbPath,
            await _androidSerial(null),
          );
          if (s != null) state = PhoneState.android(s);
        }
      } else if (_nativeOs == 'ios' && _simulatorApp == null) {
        state = await readIosPhoneState();
      }
    } catch (_) {}
    _phoneStateCache = state;
    _phoneStateAt = DateTime.now();
    return state;
  }

  /// A failure that could be the phone's doing says so: "no answer" from a
  /// locked or sleeping phone looks like a hung app otherwise.
  @override
  Future<CallToolResult> _withPhoneState(CallToolResult result) async {
    final text = result.content
        .whereType<TextContent>()
        .map((c) => c.text)
        .join('\n');
    if (!(isNoAnswer(text) ||
        text.contains('connection to the app dropped') ||
        text.contains('No active Flutter app connection') ||
        text.contains('Service has disappeared'))) {
      return result;
    }
    final state = await _phoneState();
    final problem = state?.problem;
    if (state == null || problem == null) return result;
    return CallToolResult(
      isError: true,
      content: [
        ...result.content,
        TextContent(text: 'DEVICE: $problem. ${state.fix}'),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Android (adb)
  // ---------------------------------------------------------------------------

  /// The adb serial of the connected app's device: the [p] `serial`, else the
  /// device whose forwarded port is the VM service's, else the only device.
  Future<String?> _androidSerial(Map<String, dynamic>? p) async {
    final explicit = p?['serial']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final adbPath = _adb ?? await findAdb();
    if (adbPath == null) return null;
    final port = Uri.tryParse(_activeContext?.uri ?? '')?.port;
    if (port != null && port != 0) {
      final forwards = await adb(adbPath, null, ['forward', '--list']);
      final serial = forwards == null
          ? null
          : serialForForwardedPort(forwards.stdout as String, port);
      if (serial != null) return serial;
    }
    final devices = await adb(adbPath, null, ['devices', '-l']);
    final ready = devices == null
        ? const <AdbDevice>[]
        : parseAdbDevices(devices.stdout as String).where((d) => d.ready);
    if (ready.length == 1) return ready.first.serial;
    // Several phones: the one that has this app's process.
    final pid = _androidPid;
    if (pid == null || ready.isEmpty) return null;
    final hits = <String>[];
    for (final d in ready) {
      if (await androidPackageOfPid(adbPath, d.serial, pid) != null) {
        hits.add(d.serial);
      }
    }
    return hits.length == 1 ? hits.single : null;
  }

  CallToolResult _androidError(String message) =>
      CallToolResult(isError: true, content: [TextContent(text: message)]);

  Future<CallToolResult> _androidNative(
    String tool,
    Map<String, dynamic> p,
  ) async {
    final adbPath = _adb ?? await findAdb();
    if (adbPath == null) {
      return _androidError(
        'adb was not found. Install the Android SDK platform-tools, or set '
        'ANDROID_HOME. tap_widget/enter_text work without it for anything '
        'inside the Flutter app.',
      );
    }
    final serial = await _androidSerial(p);
    if (serial == null) {
      final devices = await adb(adbPath, null, ['devices', '-l']);
      final list = devices == null
          ? ''
          : parseAdbDevices(devices.stdout as String)
                .map((d) => '  - ${d.serial} (${d.state}, ${d.model ?? '?'})')
                .join('\n');
      return _androidError(
        'Which Android device? ${list.isEmpty ? 'None is attached.' : 'Pass serial:\n$list'}',
      );
    }
    Future<CallToolResult> failed(String what, ProcessResult? r) async {
      final state = await readAndroidDeviceState(adbPath, serial);
      final why = state?.problem;
      return _androidError(
        '$what failed${r == null ? ' (adb did not answer)' : ': ${r.stderr}'}'
        '${why == null ? '' : '\nThe device may be the cause: $why. Wake and unlock it.'}',
      );
    }

    switch (tool) {
      case 'native_screenshot':
        final r = await adb(adbPath, serial, [
          'exec-out',
          'screencap',
          '-p',
        ], stdoutEncoding: null);
        final bytes = r?.stdout;
        if (r == null ||
            r.exitCode != 0 ||
            bytes is! List<int> ||
            bytes.isEmpty) {
          return failed('adb screencap', r);
        }
        return CallToolResult(
          content: [
            ImageContent(
              data: fitBase64Png(base64Encode(bytes)),
              mimeType: 'image/png',
            ),
            TextContent(
              text:
                  'Native screenshot of $serial (system dialogs included; '
                  'coordinates are screen pixels, the ones native_tap takes).',
            ),
          ],
        );
      case 'native_tap':
        final x = (p['x'] as num).round(), y = (p['y'] as num).round();
        final r = await adb(adbPath, serial, [
          'shell',
          'input',
          'tap',
          '$x',
          '$y',
        ]);
        if (r == null || r.exitCode != 0) return failed('adb input tap', r);
        return CallToolResult(
          content: [TextContent(text: 'Native tap at ($x, $y) on $serial.')],
        );
      case 'native_text':
        final text = p['text'].toString();
        final escaped = escapeAdbInputText(text);
        if (escaped == null) {
          return _androidError(
            'adb can only type ASCII. Use enter_text for a field of the app.',
          );
        }
        final r = await adb(adbPath, serial, [
          'shell',
          'input',
          'text',
          escaped,
        ]);
        if (r == null || r.exitCode != 0) return failed('adb input text', r);
        return CallToolResult(
          content: [TextContent(text: 'Native text entered on $serial.')],
        );
      case 'native_button':
        final button = p['button'].toString();
        final key = androidButtons[button];
        if (key == null) {
          return _androidError(
            '$button is not an Android button. Use: ${androidButtons.keys.join(', ')}.',
          );
        }
        final r = await adb(adbPath, serial, [
          'shell',
          'input',
          'keyevent',
          key,
        ]);
        if (r == null || r.exitCode != 0) {
          return failed('adb input keyevent', r);
        }
        return CallToolResult(
          content: [TextContent(text: 'Pressed $button on $serial.')],
        );
      case 'native_describe_screen':
        final r = await adb(adbPath, serial, [
          'exec-out',
          'uiautomator',
          'dump',
          '/dev/tty',
        ], timeout: const Duration(seconds: 25));
        final out = r?.stdout as String?;
        if (r == null ||
            r.exitCode != 0 ||
            out == null ||
            !out.contains('<hierarchy')) {
          return failed('uiautomator dump', r);
        }
        return CallToolResult(
          content: [TextContent(text: describeAndroidScreen(out))],
        );
      case 'native_open_app':
        final package = _androidPackage;
        if (package == null) {
          return _androidError('The app\'s package name could not be read.');
        }
        final r = await adb(adbPath, serial, [
          'shell',
          'monkey',
          '-p',
          package,
          '-c',
          'android.intent.category.LAUNCHER',
          '1',
        ]);
        if (r == null || r.exitCode != 0) return failed('adb monkey', r);
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (_activeContext?.lifecycle != null &&
            _activeContext?.lifecycle != 'resumed' &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return CallToolResult(
          content: [
            TextContent(
              text: 'Brought $package to the foreground (app state kept).',
            ),
          ],
        );
    }
    return _androidError('Unknown native tool $tool.');
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
