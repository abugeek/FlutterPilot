import 'dart:convert';

/// What one tool adds to `tools/list`: its name, description and input schema
/// as JSON, without `annotations` — those go to the client, not the model.
///
/// The one measure the server's list-size budget (`tool_registration_test`)
/// and the surface report (`tool/tool_list_report.dart`) share, so the two
/// numbers can't drift apart.
int toolListBytes(Map<String, dynamic> tool) =>
    jsonEncode(Map<String, dynamic>.from(tool)..remove('annotations')).length;

/// [toolListBytes] summed over [tools].
int toolListTotal(Iterable<Map<String, dynamic>> tools) =>
    tools.fold(0, (sum, tool) => sum + toolListBytes(tool));
