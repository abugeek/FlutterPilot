import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_firebase/flutterpilot_firebase.dart';

void main() {
  group('parseWhere', () {
    test('reads typed values', () {
      expect(FirebasePilotInspector.parseWhere('done == false'), (
        field: 'done',
        op: '==',
        value: false,
      ));
      expect(FirebasePilotInspector.parseWhere("title = 'Buy milk'"), (
        field: 'title',
        op: '==',
        value: 'Buy milk',
      ));
      expect(FirebasePilotInspector.parseWhere('n >= 3'), (
        field: 'n',
        op: '>=',
        value: 3,
      ));
      expect(FirebasePilotInspector.parseWhere('tags array-contains work'), (
        field: 'tags',
        op: 'array-contains',
        value: 'work',
      ));
      expect(FirebasePilotInspector.parseWhere('deletedAt == null'), (
        field: 'deletedAt',
        op: '==',
        value: null,
      ));
    });

    test('rejects what it cannot read', () {
      expect(FirebasePilotInspector.parseWhere('done'), isNull);
      expect(FirebasePilotInspector.parseWhere('== 3'), isNull);
    });
  });

  test('firestoreToJson turns Firestore types into plain JSON', () {
    final at = DateTime.utc(2026, 9, 28, 12);
    expect(
      FirebasePilotInspector.firestoreToJson({
        'at': Timestamp.fromDate(at),
        'where': const GeoPoint(41.3, 69.2),
        'raw': Blob(Uint8List(3)),
        'list': [
          1,
          {'nested': Timestamp.fromDate(at)},
        ],
        'text': 'hi',
      }),
      {
        'at': '2026-09-28T12:00:00.000Z',
        'where': {'lat': 41.3, 'lng': 69.2},
        'raw': '<3 bytes>',
        'list': [
          1,
          {'nested': '2026-09-28T12:00:00.000Z'},
        ],
        'text': 'hi',
      },
    );
  });

  test('redact keeps a hint, never the value', () {
    expect(FirebasePilotInspector.redact(null), isNull);
    expect(FirebasePilotInspector.redact('ab'), '***');
    expect(
      FirebasePilotInspector.redact('pilot@example.com'),
      'pi***[17 chars]',
    );
  });

  test('reset is safe without registration', () {
    FirebasePilotInspector.reset();
    FirebasePilotInspector.reset();
  });
}
