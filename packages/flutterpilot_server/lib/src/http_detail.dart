/// One HTTP request in full (ROADMAP §5.6): headers, bodies, timing and
/// errors from `ext.dart.io.getHttpProfileRequest`, for any dart:io client
/// (HttpClient, package:http's IOClient, Dio's IO adapter). Secrets in
/// headers and bodies are masked before the agent sees them.
library;

import 'dart:convert';
import 'redaction.dart';

/// Header names whose values are credentials.
final _secretHeader = RegExp(
  r'^(authorization|proxy-authorization|cookie|set-cookie|x-api-key|'
  r'api-key|x-auth-token|x-access-token|x-csrf-token|x-xsrf-token)$',
  caseSensitive: false,
);

/// JSON keys / form fields whose values are credentials or personal data.
final _secretField = RegExp(
  r'pass(word|wd)?$|secret|token|api[-_]?key|authorization|cookie|'
  r'session|credit|card[-_]?number|cvv|cvc|ssn|pin$',
  caseSensitive: false,
);

const _mask = '•••';

/// Total time: until the response finished, not until the request was
/// sent (the top-level endTime).
int? durationMs(Map request) {
  final start = request['startTime'];
  final end = (request['response'] as Map?)?['endTime'];
  if (start is! int || end is! int) return null;
  return ((end - start) / 1000).round();
}

/// `content-type: application/json` lines, credentials masked.
List<String> headerLines(Map? headers) {
  if (headers == null) return const [];
  return [
    for (final MapEntry(:key, :value) in headers.entries)
      '$key: ${_secretHeader.hasMatch('$key') ? _mask : (value is List ? value.join(', ') : value)}',
  ];
}

/// Masks credential-like fields in decoded JSON, recursively.
Object? redactJson(Object? value) => switch (value) {
  Map() => {
    for (final MapEntry(:key, value: v) in value.entries)
      '$key': _secretField.hasMatch('$key') && v is! Map && v is! List
          ? _mask
          : redactJson(v),
  },
  List() => [for (final v in value) redactJson(v)],
  _ => value,
};

/// A body as text an agent can read: JSON (credentials masked), form
/// fields (masked), or text; binary as a size; cut at [max] characters.
String? describeBody(List<int>? bytes, String? contentType, {int max = 3000}) {
  if (bytes == null || bytes.isEmpty) return null;
  final type = (contentType ?? '').toLowerCase();
  final binary =
      type.startsWith('image/') ||
      type.startsWith('audio/') ||
      type.startsWith('video/') ||
      type.contains('octet-stream') ||
      type.contains('protobuf') ||
      type.contains('font');
  if (binary) return '${bytes.length} bytes of $type (binary, not shown)';
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return '${bytes.length} bytes${type.isEmpty ? '' : ' of $type'} '
        '(not UTF-8 text, not shown)';
  }
  var shown = text;
  if (type.contains('json') ||
      text.trimLeft().startsWith('{') ||
      text.trimLeft().startsWith('[')) {
    try {
      shown = jsonEncode(redactJson(jsonDecode(text)));
    } on FormatException {
      // Not JSON after all: show as text.
    }
  } else if (type.contains('x-www-form-urlencoded')) {
    shown = text
        .split('&')
        .map((pair) {
          final name = Uri.decodeQueryComponent(pair.split('=').first);
          return _secretField.hasMatch(name) ? '$name=$_mask' : pair;
        })
        .join('&');
  }
  if (shown.length <= max) return shown;
  return '${shown.substring(0, max)}… (${shown.length - max} more '
      'characters; ${bytes.length} bytes in all)';
}

String? _contentType(Map? headers) {
  final v = headers?['content-type'];
  return v is List ? v.join(', ') : v?.toString();
}

/// The detail of one request from `getHttpProfileRequest`, as text.
String formatRequestDetail(Map detail, {required int number}) {
  final request = (detail['request'] as Map?) ?? const {};
  final response = detail['response'] as Map?;
  final buf = StringBuffer();
  final status = response?['statusCode'];
  final ms = durationMs(detail);
  buf.writeln(
    '#$number ${detail['method']} ${Redaction.text('${detail['uri']}')} → '
    '${status == null ? 'no response' : '$status ${response?['reasonPhrase'] ?? ''}'.trim()}'
    '${ms == null ? '' : ' in $ms ms'}',
  );
  final error = request['error'] ?? response?['error'];
  if (error != null) buf.writeln('Error: $error');

  // Where the time went, from the connection events.
  final start = detail['startTime'];
  final events = (detail['events'] as List? ?? const []).whereType<Map>();
  if (start is int && events.isNotEmpty) {
    buf.writeln(
      'Timeline: ${events.map((e) => '${e['event']} +${(((e['timestamp'] as int? ?? start) - start) / 1000).round()} ms').join(', ')}',
    );
  }
  final redirects = (response?['redirects'] as List? ?? const []);
  if (redirects.isNotEmpty) {
    buf.writeln(
      'Redirects: ${redirects.whereType<Map>().map((r) => '${r['statusCode']} → ${r['location']}').join(', ')}',
    );
  }

  buf.writeln('Request headers:');
  for (final line in headerLines(request['headers'] as Map?)) {
    buf.writeln('  $line');
  }
  final requestBody = describeBody(
    (detail['requestBody'] as List?)?.cast<int>(),
    _contentType(request['headers'] as Map?),
  );
  if (requestBody != null) buf.writeln('Request body: $requestBody');

  if (response != null) {
    buf.writeln('Response headers:');
    for (final line in headerLines(response['headers'] as Map?)) {
      buf.writeln('  $line');
    }
    final responseBody = describeBody(
      (detail['responseBody'] as List?)?.cast<int>(),
      _contentType(response['headers'] as Map?),
    );
    buf.writeln('Response body: ${responseBody ?? '(empty)'}');
  }
  return buf.toString().trim();
}
