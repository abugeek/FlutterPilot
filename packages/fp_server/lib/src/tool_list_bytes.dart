import 'dart:convert';

/// The model-facing projection of [tool] in `tools/list`: its name,
/// description and input schema. `annotations` and `execution` go to the
/// client, not the model, so they are dropped here — which keeps the size
/// measure identical whether it is handed the in-process `Tool.toJson()` or
/// the raw `tools/list` result (the running server adds `execution`, the
/// in-process list does not).
Map<String, dynamic> toolModelProjection(Map<String, dynamic> tool) => {
  'name': tool['name'],
  'description': tool['description'],
  'inputSchema': tool['inputSchema'],
};

/// The serialized model-facing projection of [tool], in Dart string units.
///
/// This is the **legacy** measure. `String.length` counts UTF-16 code units,
/// not bytes, so it undercounts any non-ASCII description or schema (an emoji
/// is 2, an Arabic letter 1, but 3 and 2 bytes). The list-size budgets still
/// use this number; task 00 kept it under an explicit name so the encoding
/// correction below can never be misreported as tool growth.
int toolListChars(Map<String, dynamic> tool) =>
    jsonEncode(toolModelProjection(tool)).length;

/// [toolListChars] summed over [tools].
int toolListTotalChars(Iterable<Map<String, dynamic>> tools) =>
    tools.fold(0, (sum, tool) => sum + toolListChars(tool));

/// UTF-8 bytes of the serialized model-facing projection.
///
/// The bytes that actually cross the wire for the part the model reads, as
/// opposed to [toolListChars]'s code units.
int toolListUtf8Bytes(Map<String, dynamic> tool) =>
    utf8.encode(jsonEncode(toolModelProjection(tool))).length;

/// [toolListUtf8Bytes] summed over [tools].
int toolListTotalUtf8Bytes(Iterable<Map<String, dynamic>> tools) =>
    tools.fold(0, (sum, tool) => sum + toolListUtf8Bytes(tool));

/// The full wire size of [tool] as sent in `tools/list`: the whole JSON
/// object, annotations included, in UTF-8 bytes.
///
/// The client receives this; a model usually receives only the projection
/// measured by [toolListUtf8Bytes]. Neither is a universal measure of what
/// every client sends to its model.
int toolListWireBytes(Map<String, dynamic> tool) =>
    utf8.encode(jsonEncode(tool)).length;

/// [toolListWireBytes] summed over [tools].
int toolListTotalWireBytes(Iterable<Map<String, dynamic>> tools) =>
    tools.fold(0, (sum, tool) => sum + toolListWireBytes(tool));

/// An **estimated** token count for [utf8Bytes] bytes of tool JSON.
///
/// A rough estimate (four UTF-8 bytes per token), not billed token usage.
int toolListTokens(int utf8Bytes) => utf8Bytes ~/ 4;
