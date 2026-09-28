import 'dart:convert';

import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:flutterpilot_server/src/image_budget.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  test('describeNativeScreen: one line per labelled element, tap point '
      'in points', () {
    final json = jsonEncode([
      {
        'type': 'Application',
        'AXLabel': ' ',
        'frame': {'x': 0, 'y': 0, 'width': 402, 'height': 874},
      },
      {
        'type': 'StaticText',
        'AXLabel': 'Allow “Native App” to use your location?',
        'frame': {'x': 71, 'y': 330, 'width': 260, 'height': 42.3},
      },
      {
        'type': 'Button',
        'AXLabel': 'Allow Once',
        'enabled': true,
        'frame': {'x': 57, 'y': 418, 'width': 288, 'height': 48},
      },
      {
        'type': 'Other',
        'AXLabel': null,
        'frame': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
      },
    ]);
    expect(
      describeNativeScreen(json),
      '- StaticText "Allow “Native App” to use your location?" → tap (201, 351)\n'
      '- Button "Allow Once" → tap (201, 442)\n'
      'Coordinates are points (native_tap).',
    );
    expect(describeNativeScreen('[]'), contains('Nothing native on screen'));
    expect(describeNativeScreen('not json'), 'not json');
  });

  group('fitBase64Png', () {
    String noisyPng(int size) {
      final image = img.Image(width: size, height: size);
      var seed = 7;
      for (final p in image) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        p.setRgb(seed & 255, (seed >> 8) & 255, (seed >> 16) & 255);
      }
      return base64Encode(img.encodePng(image));
    }

    test('scales an image down until it fits', () {
      final big = noisyPng(600);
      final fitted = fitBase64Png(big, maxChars: big.length ~/ 4);
      expect(fitted.length, lessThanOrEqualTo(big.length ~/ 4));
      final image = img.decodePng(base64Decode(fitted))!;
      expect(image.width, lessThan(600));
      expect(image.width, image.height);
    });

    test('leaves an image that fits unchanged', () {
      final small = noisyPng(20);
      expect(fitBase64Png(small), same(small));
    });
  });

  test('native tools are registered but hidden until an iOS app connects', () {
    final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    expect(
      server.listedToolNames,
      isNot(contains(anyOf('native_open_app', 'native_tap'))),
    );
  });
}
