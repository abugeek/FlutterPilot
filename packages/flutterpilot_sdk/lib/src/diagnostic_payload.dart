import 'dart:convert';

/// Bounds diagnostic payloads before they enter long-lived in-memory buffers.
class DiagnosticPayload {
  static const int maxDepth = 8;
  static const int maxItems = 200;
  static const int maxStringLength = 4000;

  static dynamic sanitize(dynamic value, [int depth = 0]) {
    if (depth >= maxDepth) return '<max depth exceeded>';
    if (value == null || value is num || value is bool) return value;
    if (value is String) {
      return value.length <= maxStringLength
          ? value
          : '${value.substring(0, maxStringLength)}…<truncated>';
    }
    if (value is Map) {
      final entries = value.entries.take(maxItems);
      final result = <String, dynamic>{
        for (final entry in entries)
          entry.key.toString(): sanitize(entry.value, depth + 1),
      };
      if (value.length > maxItems) result['<truncated>'] = true;
      return result;
    }
    if (value is Iterable) {
      final result = value
          .take(maxItems)
          .map((item) => sanitize(item, depth + 1))
          .toList();
      if (value.length > maxItems) result.add('<truncated>');
      return result;
    }
    return value.toString();
  }

  static Map<String, dynamic> boundedMap(Map<String, dynamic> value) {
    final sanitized = sanitize(value);
    try {
      final encoded = jsonEncode(sanitized);
      if (utf8.encode(encoded).length <= 64 * 1024) {
        return Map<String, dynamic>.from(sanitized as Map);
      }
    } catch (_) {}
    return {
      '<truncated>': true,
      'preview': sanitized.toString().substring(
        0,
        sanitized.toString().length.clamp(0, 4000),
      ),
    };
  }
}
