import 'package:flutterpilot_server/src/cpu_profile.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

Map<String, dynamic> _fn(String name, String url, {String? owner}) => {
  'type': 'ProfileFunction',
  'kind': 'Dart',
  'inclusiveTicks': 0,
  'exclusiveTicks': 0,
  'resolvedUrl': url,
  'function': {
    'type': '@Function',
    'id': 'functions/$name',
    'name': name,
    'owner': owner == null
        ? {'type': '@Library', 'id': 'libraries/1', 'name': '', 'uri': url}
        : {'type': '@Class', 'id': 'classes/$owner', 'name': owner},
    'static': false,
    'const': false,
    'implicit': false,
    'abstract': false,
    '_intrinsic': false,
    '_native': false,
    'isGetter': false,
    'isSetter': false,
  },
};

CpuSamples _samples(List<Map<String, dynamic>> fns, List<List<int>> stacks) =>
    CpuSamples.parse({
      'type': 'CpuSamples',
      'samplePeriod': 250,
      'maxStackDepth': 128,
      'sampleCount': stacks.length,
      'timeOriginMicros': 0,
      'timeExtentMicros': 1000,
      'pid': 1,
      'functions': fns,
      'samples': [
        for (final s in stacks) {'tid': 1, 'timestamp': 0, 'stack': s},
      ],
    })!;

void main() {
  final classifier = CodeClassifier(
    appPackages: {'hn_reader'},
    appRoot: '/Users/me/hn_reader',
  );

  test('classifies app, FlutterPilot and other code by URL', () {
    expect(classifier.ownerOf('package:hn_reader/ui/tile.dart'), CodeOwner.app);
    expect(
      classifier.ownerOf('file:///Users/me/hn_reader/lib/main.dart'),
      CodeOwner.app,
    );
    expect(
      classifier.ownerOf('package:flutterpilot_sdk/src/x.dart'),
      CodeOwner.flutterpilot,
    );
    expect(
      classifier.ownerOf('package:flutter/src/widgets/framework.dart'),
      CodeOwner.other,
    );
    expect(classifier.ownerOf('dart:convert'), CodeOwner.other);
  });

  test('attributes samples to the nearest owner and leaves out '
      'FlutterPilot\'s own work', () {
    final fns = [
      _fn('build', 'package:hn_reader/ui/tile.dart', owner: 'StoryTile'), // 0
      _fn('jsonDecode', 'dart:convert'), // 1
      _fn(
        'performRebuild',
        'package:flutter/src/widgets/framework.dart',
        owner: 'Element',
      ), // 2
      _fn(
        'captureWidgetTree',
        'package:flutterpilot_sdk/src/w.dart',
        owner: 'PilotWidgetInspector',
      ), // 3
      _fn(
        'tap',
        'package:flutterpilot_sdk/src/i.dart',
        owner: 'InteractionManager',
      ), // 4
      _fn('_onTap', 'package:hn_reader/ui/feed.dart', owner: 'Feed'), // 5
    ];
    final cpu = _samples(fns, [
      [0, 2], // StoryTile.build self
      [0, 2],
      [1, 0, 2], // jsonDecode called by StoryTile.build
      [2], // framework only
      [2, 3], // FlutterPilot's tree walk inside framework code: left out
      [5, 4], // app tap handler reached through FlutterPilot's tap: app
    ]);
    final profile = ActionProfile.analyze(cpu, classifier);

    expect(profile.flutterpilotSamples, 1);
    expect(profile.dartSamples, 5);
    expect(profile.appSamples, 4);
    expect(profile.ms(profile.dartSamples), 1.25);

    final app = profile.topApp(classifier);
    expect(app.map((f) => f.name), ['StoryTile.build', 'Feed._onTap']);
    expect(app.first.self, 2);
    expect(app.first.total, 3);

    final hot = profile.topSelf();
    expect(hot.first.name, 'StoryTile.build');
    final json = hot.firstWhere((f) => f.name == 'jsonDecode');
    expect(profile.functions[json.topAppCaller!].name, 'StoryTile.build');
  });

  test('samples without Dart frames count as GC/VM/native', () {
    final cpu = _samples(
      [
        {
          'type': 'ProfileFunction',
          'kind': 'Native',
          'inclusiveTicks': 0,
          'exclusiveTicks': 0,
          'resolvedUrl': '',
          'function': {'type': 'NativeFunction', 'name': 'memcpy'},
        },
      ],
      [
        [0],
      ],
    );
    final profile = ActionProfile.analyze(cpu, classifier);
    expect(profile.nativeSamples, 1);
    expect(profile.dartSamples, 0);
  });

  test('file paths map back to packages through package_config', () {
    // What the VM reports for a path dependency and the Flutter SDK.
    final mapped = CodeClassifier.fromPackageConfig(
      appPackages: {'hn_reader'},
      appRoot: '/Users/me/hn_reader',
      configUri: Uri.file('/Users/me/hn_reader/.dart_tool/package_config.json'),
      json: {
        'packages': [
          {'name': 'hn_reader', 'rootUri': '../', 'packageUri': 'lib/'},
          {
            'name': 'flutterpilot_sdk',
            'rootUri': '../../FlutterPilot/packages/flutterpilot_sdk',
            'packageUri': 'lib/',
          },
          {
            'name': 'flutter',
            'rootUri': 'file:///sdk/flutter/packages/flutter',
            'packageUri': 'lib/',
          },
        ],
      },
    );
    const sdkFile =
        '/Users/me/FlutterPilot/packages/flutterpilot_sdk/lib/src/w.dart';
    expect(mapped.ownerOf(sdkFile), CodeOwner.flutterpilot);
    expect(mapped.display(sdkFile), 'package:flutterpilot_sdk/src/w.dart');
    const framework = '/sdk/flutter/packages/flutter/lib/src/widgets/x.dart';
    expect(mapped.ownerOf(framework), CodeOwner.other);
    expect(mapped.display(framework), 'package:flutter/src/widgets/x.dart');
    const app = '/Users/me/hn_reader/lib/ui/tile.dart';
    expect(mapped.ownerOf(app), CodeOwner.app);
    expect(mapped.display(app), 'lib/ui/tile.dart');
    expect(mapped.display('package:hn_reader/main.dart'), 'lib/main.dart');
    expect(
      mapped.display(
        'org-dartlang-sdk:///flutter/third_party/dart/sdk/lib/convert/json.dart',
      ),
      'dart:convert/json.dart',
    );
    expect(
      mapped.display('org-dartlang-sdk:///flutter/lib/ui/text.dart'),
      'dart:ui/text.dart',
    );
  });
}
