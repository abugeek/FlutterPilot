import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// Shows what the app's screens get: text scale and locale.
class _Probe extends StatelessWidget {
  const _Probe(this.seen);
  final List<double> seen;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    seen.add(scale);
    return Text('scale $scale locale ${Localizations.localeOf(context)}');
  }
}

Widget _app(
  List<double> seen, {
  List<Locale> supported = const [Locale('en', 'US')],
  Locale? locale,
  TransitionBuilder? builder,
}) => MaterialApp(
  supportedLocales: supported,
  locale: locale,
  builder: builder,
  home: Scaffold(body: _Probe(seen)),
);

/// Runs [call], pumping the frame it waits for.
Future<T> _settle<T>(WidgetTester tester, Future<T> call) async {
  await tester.pump();
  await tester.pump();
  return call;
}

void main() {
  final override = AppSettingsOverride.instance;
  tearDown(override.reset);

  group('text scale, no wiring in the app', () {
    testWidgets('reaches the app and resets', (tester) async {
      final seen = <double>[];
      await tester.pumpWidget(_app(seen));
      expect(find.textContaining('scale 1.0'), findsOneWidget);

      final r = await _settle(tester, override.setTextScale(2));
      expect(r['scale'], 2.0);
      expect(find.textContaining('scale 2.0'), findsOneWidget);

      final back = await _settle(tester, override.setTextScale(null));
      expect(back['scale'], 1.0);
      expect(find.textContaining('scale 1.0'), findsOneWidget);
    });

    testWidgets('survives a device change without a frame at the device '
        'scale', (tester) async {
      final seen = <double>[];
      await tester.pumpWidget(_app(seen));
      await _settle(tester, override.setTextScale(2));
      seen.clear();

      // Keyboard, rotation and window resizes change the metrics; the root
      // MediaQuery then rebuilds from the device.
      tester.view.physicalSize = const Size(1000, 2000);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('scale 2.0'), findsOneWidget);
      expect(seen, isNot(contains(1.0)));
    });

    testWidgets('survives a hot reload', (tester) async {
      final seen = <double>[];
      await tester.pumpWidget(_app(seen));
      await _settle(tester, override.setTextScale(1.5));

      final reload = tester.binding.reassembleApplication();
      await tester.pump();
      await reload;
      await tester.pump();
      expect(find.textContaining('scale 1.5'), findsOneWidget);
    });

    testWidgets('reports the scale an app that clamps it gets', (tester) async {
      final seen = <double>[];
      await tester.pumpWidget(
        _app(
          seen,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: child!,
          ),
        ),
      );
      final r = await _settle(tester, override.setTextScale(2));
      expect(r['scale'], 1.3);
      expect(find.textContaining('scale 1.3'), findsOneWidget);
    });
  });

  group('locale, no wiring in the app', () {
    const gb = Locale('en', 'GB');
    const supported = [Locale('en', 'US'), gb];

    testWidgets('reaches the app and resets', (tester) async {
      await tester.pumpWidget(_app([], supported: supported));
      expect(find.textContaining('locale en_US'), findsOneWidget);

      final r = await _settle(tester, override.setLocale(gb));
      expect(r['locale'], 'en_GB');
      expect(find.textContaining('locale en_GB'), findsOneWidget);

      final back = await _settle(tester, override.setLocale(null));
      expect(back['locale'], 'en_US');
      expect(find.textContaining('locale en_US'), findsOneWidget);
    });

    testWidgets('reports a locale the app does not support', (tester) async {
      await tester.pumpWidget(_app([], supported: supported));
      final r = await _settle(tester, override.setLocale(const Locale('fr')));
      expect(r['locale'], 'en_US');
      expect(r['supported'], ['en_US', 'en_GB']);
      expect(r.containsKey('appSetsLocale'), isFalse);
    });

    testWidgets('reports an app that sets its own locale', (tester) async {
      await tester.pumpWidget(
        _app([], supported: supported, locale: const Locale('en', 'US')),
      );
      final r = await _settle(tester, override.setLocale(gb));
      expect(r['locale'], 'en_US');
      expect(r['appSetsLocale'], 'en_US');
    });

    testWidgets('survives MaterialApp rebuilding with a new supportedLocales '
        'list', (tester) async {
      late StateSetter rebuild;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            // A new list each build re-resolves the locale from the device.
            return _app([], supported: [...supported]);
          },
        ),
      );
      await _settle(tester, override.setLocale(gb));
      rebuild(() {});
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.textContaining('locale en_GB'), findsOneWidget);
    });
  });

  test('parseLocale', () {
    expect(AppSettingsOverride.parseLocale('fr'), const ui.Locale('fr'));
    expect(
      AppSettingsOverride.parseLocale('en-GB'),
      const ui.Locale('en', 'GB'),
    );
    expect(
      AppSettingsOverride.parseLocale('pt_br'),
      const ui.Locale('pt', 'BR'),
    );
    expect(
      AppSettingsOverride.parseLocale('zh-hans-CN'),
      const ui.Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
        countryCode: 'CN',
      ),
    );
    expect(
      AppSettingsOverride.parseLocale('es-419'),
      const ui.Locale('es', '419'),
    );
    expect(AppSettingsOverride.parseLocale('english!'), isNull);
    expect(AppSettingsOverride.parseLocale('en-GB-x'), isNull);
  });
}
