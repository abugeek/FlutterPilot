import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// FlutterPilot plugin that lets AI agents see Firebase Auth and Firestore
/// the way the app sees them: who is signed in, and what the database
/// holds. Read-only; change data through the app's own UI.
///
/// ## Setup
/// ```dart
/// await Firebase.initializeApp(...);
/// FlutterPilot.initialize();
/// FirebasePilotInspector.register(
///   auth: FirebaseAuth.instance,
///   firestore: FirebaseFirestore.instance,
/// );
/// ```
/// Both are optional — register what the app uses.
class FirebasePilotInspector {
  FirebasePilotInspector._();

  static FirebaseAuth? _auth;
  static FirebaseFirestore? _firestore;
  static StreamSubscription<User?>? _authSub;
  static final List<Map<String, dynamic>> _authEvents = [];
  static const int _maxAuthEvents = 20;

  /// Registers the Firebase services the app uses with FlutterPilot.
  static void register({FirebaseAuth? auth, FirebaseFirestore? firestore}) {
    FlutterPilot.registerCapability(
      'firebase',
      version: '2',
      extensions: [
        'ext.flutterpilot.getFirebaseAuth',
        'ext.flutterpilot.queryFirestore',
      ],
    );
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        '[FlutterPilot] FirebasePilotInspector.register called before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
    }
    reset();
    _auth = auth;
    _firestore = firestore;
    _authSub = auth?.authStateChanges().listen((user) {
      _authEvents.add({
        'event': user == null ? 'signedOut' : 'signedIn',
        'provider': ?user?.providerData.firstOrNull?.providerId,
        'at': DateTime.now().toIso8601String(),
      });
      while (_authEvents.length > _maxAuthEvents) {
        _authEvents.removeAt(0);
      }
    });
    registerExtension('ext.flutterpilot.getFirebaseAuth', _getAuth);
    registerExtension('ext.flutterpilot.queryFirestore', _queryFirestore);
  }

  /// Forgets the registered services (e.g. before registering again).
  static void reset() {
    _authSub?.cancel();
    _authSub = null;
    _authEvents.clear();
    _auth = null;
    _firestore = null;
  }

  static ServiceExtensionResponse _error(String message) =>
      ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        message,
      );

  static Future<ServiceExtensionResponse> _getAuth(
    String method,
    Map<String, String> parameters,
  ) async {
    final auth = _auth;
    if (auth == null) {
      return _error(
        'FirebaseAuth not registered: pass auth: FirebaseAuth.instance to '
        'FirebasePilotInspector.register.',
      );
    }
    final sensitive = parameters['showSensitive'] == 'true';
    final user = auth.currentUser;
    final result = <String, dynamic>{
      'projectId': auth.app.options.projectId,
      'signedIn': user != null,
      'events': _authEvents,
    };
    if (user != null) {
      String? hide(String? v) => sensitive ? v : redact(v);
      result['user'] = {
        // Needed to build the app's Firestore paths (users/{uid}/...).
        'uid': user.uid,
        'email': hide(user.email),
        'displayName': hide(user.displayName),
        'phoneNumber': hide(user.phoneNumber),
        'isAnonymous': user.isAnonymous,
        'emailVerified': user.emailVerified,
        'providers': [for (final p in user.providerData) p.providerId],
        'createdAt': user.metadata.creationTime?.toIso8601String(),
        'lastSignInAt': user.metadata.lastSignInTime?.toIso8601String(),
      };
      try {
        // Cached token: no network call unless it expired.
        final token = await user.getIdTokenResult();
        result['token'] = {
          'signInProvider': token.signInProvider,
          'expiresAt': token.expirationTime?.toIso8601String(),
          'customClaims': {
            for (final e in (token.claims ?? const {}).entries)
              if (!_standardClaims.contains(e.key)) e.key: e.value,
          },
        };
      } catch (e) {
        result['token'] = {'error': e.toString()};
      }
    }
    return ServiceExtensionResponse.result(jsonEncode(result));
  }

  static const _standardClaims = {
    'iss', 'aud', 'auth_time', 'user_id', 'sub', 'iat', 'exp', 'email', //
    'email_verified', 'firebase', 'name', 'picture', 'phone_number',
  };

  static Future<ServiceExtensionResponse> _queryFirestore(
    String method,
    Map<String, String> parameters,
  ) async {
    final firestore = _firestore;
    if (firestore == null) {
      return _error(
        'FirebaseFirestore not registered: pass firestore: '
        'FirebaseFirestore.instance to FirebasePilotInspector.register.',
      );
    }
    final path = (parameters['path'] ?? '').trim().replaceAll(
      RegExp(r'^/+|/+$'),
      '',
    );
    if (path.isEmpty) {
      return _error(
        'Missing "path": a collection ("users/abc/notes") or a document '
        '("users/abc").',
      );
    }
    final limit = int.tryParse(parameters['limit'] ?? '') ?? 20;
    if (limit < 1 || limit > 100) {
      return _error('limit must be between 1 and 100.');
    }
    final source = parameters['source'] == 'cache'
        ? Source.cache
        : Source.server;
    final options = GetOptions(source: source);
    final isDocument = path.split('/').length.isEven;
    try {
      if (isDocument) {
        final doc = await firestore.doc(path).get(options);
        return ServiceExtensionResponse.result(
          jsonEncode({
            'path': path,
            'kind': 'document',
            'source': source.name,
            'exists': doc.exists,
            if (doc.exists) 'data': firestoreToJson(doc.data()),
          }),
        );
      }
      Query<Map<String, dynamic>> query = firestore.collection(path);
      final where = parameters['where'];
      if (where != null && where.trim().isNotEmpty) {
        final filter = parseWhere(where);
        if (filter == null) {
          return _error(
            'Could not read where "$where". Use "field op value", op one of '
            '${_operators.join(' ')}; e.g. "done == false".',
          );
        }
        query = _applyWhere(query, filter);
      }
      final orderBy = parameters['orderBy']?.trim();
      if (orderBy != null && orderBy.isNotEmpty) {
        final parts = orderBy.split(RegExp(r'\s+'));
        query = query.orderBy(
          parts.first,
          descending: parts.length > 1 && parts[1].toLowerCase() == 'desc',
        );
      }
      final snapshot = await query.limit(limit).get(options);
      return ServiceExtensionResponse.result(
        jsonEncode({
          'path': path,
          'kind': 'collection',
          'source': source.name,
          'count': snapshot.docs.length,
          'limit': limit,
          'docs': [
            for (final d in snapshot.docs)
              {'id': d.id, 'data': firestoreToJson(d.data())},
          ],
        }),
      );
    } on FirebaseException catch (e) {
      return _error(
        'Firestore ${e.code}: ${e.message}'
        '${e.code == 'permission-denied' ? ' (security rules deny this read ${_auth?.currentUser == null ? 'while nobody is signed in' : 'for the signed-in user'})' : ''}'
        '${e.code == 'unavailable' && source == Source.cache ? ' (not in the local cache)' : ''}',
      );
    } catch (e) {
      return _error('Query failed: $e');
    }
  }

  static const _operators = [
    '==',
    '!=',
    '<',
    '<=',
    '>',
    '>=',
    'array-contains',
  ];

  static Query<Map<String, dynamic>> _applyWhere(
    Query<Map<String, dynamic>> q,
    ({String field, String op, Object? value}) f,
  ) => switch (f.op) {
    '==' => q.where(f.field, isEqualTo: f.value),
    '!=' => q.where(f.field, isNotEqualTo: f.value),
    '<' => q.where(f.field, isLessThan: f.value),
    '<=' => q.where(f.field, isLessThanOrEqualTo: f.value),
    '>' => q.where(f.field, isGreaterThan: f.value),
    '>=' => q.where(f.field, isGreaterThanOrEqualTo: f.value),
    _ => q.where(f.field, arrayContains: f.value),
  };

  /// `"done == false"`, `"title == 'Buy milk'"`, `"n >= 3"`, `"tags
  /// array-contains work"` → field, operator and a typed value. Null when it
  /// isn't one of these.
  @visibleForTesting
  static ({String field, String op, Object? value})? parseWhere(String input) {
    final m = RegExp(
      r'^\s*([A-Za-z_][\w.]*)\s*(array-contains|==|!=|<=|>=|<|>|=)\s*(.+?)\s*$',
    ).firstMatch(input);
    if (m == null) return null;
    final raw = m.group(3)!;
    final Object? value;
    if (RegExp(r'''^(['"]).*\1$''').hasMatch(raw)) {
      value = raw.substring(1, raw.length - 1);
    } else if (raw == 'true' || raw == 'false') {
      value = raw == 'true';
    } else if (raw == 'null') {
      value = null;
    } else {
      value = num.tryParse(raw) ?? raw;
    }
    final op = m.group(2) == '=' ? '==' : m.group(2)!;
    return (field: m.group(1)!, op: op, value: value);
  }

  /// Firestore values as plain JSON: timestamps as ISO strings, references
  /// as their path, geo points as lat/lng, bytes as their length.
  @visibleForTesting
  static Object? firestoreToJson(Object? value) => switch (value) {
    Timestamp t => t.toDate().toUtc().toIso8601String(),
    DateTime d => d.toUtc().toIso8601String(),
    GeoPoint g => {'lat': g.latitude, 'lng': g.longitude},
    DocumentReference r => r.path,
    Blob b => '<${b.bytes.length} bytes>',
    Map m => {
      for (final e in m.entries) e.key.toString(): firestoreToJson(e.value),
    },
    List l => [for (final v in l) firestoreToJson(v)],
    _ => value,
  };

  /// First two characters and the length: enough to recognise, not to leak.
  @visibleForTesting
  static String? redact(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length <= 2) return '***';
    return '${value.substring(0, 2)}***[${value.length} chars]';
  }
}
