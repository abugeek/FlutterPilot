import 'package:fp_server/fp_server.dart';
import 'package:test/test.dart';

void main() {
  group('set_app_settings orientation', () {
    test('auto releases the pin as all, which every SDK knows', () {
      expect(orientationExtensionArgument('auto'), 'all');
      expect(orientationExtensionArgument('portrait'), 'portrait');
      expect(orientationExtensionArgument('landscape'), 'landscape');
      expect(orientationExtensionArgument('all'), 'all');
    });

    test('a pin says it outlives the call; auto and all stay quiet', () {
      expect(orientationPinNote('portrait'), contains('stays pinned'));
      expect(orientationPinNote('portrait'), contains('"auto"'));
      expect(orientationPinNote('landscape'), contains('no longer follows'));
      expect(orientationPinNote('auto'), isNull);
      expect(orientationPinNote('all'), isNull);
    });
  });
}
