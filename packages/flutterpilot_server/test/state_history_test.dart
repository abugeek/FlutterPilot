import 'package:flutterpilot_server/src/state_history.dart';
import 'package:test/test.dart';

void main() {
  final changes = [
    {
      'source': 'riverpod',
      'name': 'cartProvider',
      'to': '0',
      'at': '2026-10-05T01:04:12.100123',
    },
    {
      'source': 'riverpod',
      'name': 'cartProvider',
      'from': '0',
      'to': '3',
      'at': '2026-10-05T01:04:12.110123',
    },
    {
      'source': 'navigation',
      'name': 'push',
      'to': '/cart',
      'at': '2026-10-05T01:04:12.200123',
    },
    {
      'source': 'bloc',
      'name': 'AuthCubit',
      'from': 'in',
      'to': 'out',
      'at': '2026-10-05T01:04:13.000123',
    },
    {
      'source': 'riverpod',
      'name': 'cartProvider',
      'from': '3',
      'disposed': true,
      'at': '2026-10-05T01:04:13.004123',
    },
  ];

  test('changes read as a timeline, oldest first', () {
    expect(formatStateHistory(changes, dropped: 2).split('\n'), [
      'State changes, oldest first (5; 2 older ones dropped):',
      '01:04:12.100  riverpod  cartProvider: created 0',
      '01:04:12.110  riverpod  cartProvider: 0 → 3',
      '01:04:12.200  navigation  push /cart',
      '01:04:13.000  bloc  AuthCubit: in → out',
      '01:04:13.004  riverpod  cartProvider: disposed (was 3)',
    ]);
  });

  test('type keeps one plugin and the route changes', () {
    final text = formatStateHistory(changes, type: 'bloc');
    expect(text, contains('AuthCubit'));
    expect(text, contains('push /cart'));
    expect(text, isNot(contains('cartProvider')));
  });

  test('nothing observed says so', () {
    expect(formatStateHistory(const []), contains('No state changes observed'));
  });
}
