import 'package:mcp_dart/mcp_dart.dart';

/// What a tool does to the app, as MCP clients are told (tool annotations):
/// they run [reads] tools without asking and in parallel, and ask before a
/// [destructive] one.
enum ToolEffect {
  /// Returns what the app shows or holds and changes nothing in it. Some
  /// take `clear: true`, which empties FlutterPilot's own capture of logs,
  /// requests or state changes, not anything of the app's.
  reads,

  /// Drives the app as a user or developer would (taps, text, navigation,
  /// settings, mocks, a hot reload) or writes a new file (a test, a report).
  /// What the app does in response is the app's own.
  acts,

  /// Replaces or deletes stored data, which the server refuses without
  /// `--allow-destructive`, or runs app code the server can't see into.
  destructive,
}

/// Every tool's effect. A tool without an entry can't be registered, so a new
/// one is never listed with the MCP defaults (not read-only, destructive).
const toolEffects = <String, ToolEffect>{
  // Connection and fleet
  'connect_app': ToolEffect.acts,
  'list_connected_devices': ToolEffect.reads,
  'register_device': ToolEffect.acts,
  'switch_device': ToolEffect.acts,
  'run_on_devices': ToolEffect.acts,

  // Looking at the app
  'get_app_summary': ToolEffect.reads,
  'get_interactive_elements': ToolEffect.reads,
  'get_widget_tree': ToolEffect.reads,
  'get_widget_properties': ToolEffect.reads,
  'get_semantics_tree': ToolEffect.reads,
  'get_navigation_stack': ToolEffect.reads,
  'get_errors': ToolEffect.reads,
  'get_debug_logs': ToolEffect.reads,
  'inspect_widget': ToolEffect.reads,
  'capture_screenshot': ToolEffect.reads,
  'audit_screen_health': ToolEffect.reads,
  'assert_widget': ToolEffect.reads,
  'wait_for': ToolEffect.reads,
  'native_screenshot': ToolEffect.reads,
  'native_describe_screen': ToolEffect.reads,

  // Driving it
  'tap_widget': ToolEffect.acts,
  'enter_text': ToolEffect.acts,
  'press_key': ToolEffect.acts,
  'pinch_zoom': ToolEffect.acts,
  'scroll_into_view': ToolEffect.acts,
  'swipe_widget': ToolEffect.acts,
  'drag_widget': ToolEffect.acts,
  'focus_widget': ToolEffect.acts,
  'set_slider_value': ToolEffect.acts,
  'toggle_checkbox': ToolEffect.acts,
  'fill_form': ToolEffect.acts,
  'execute_action_chain': ToolEffect.acts,
  'navigate_to': ToolEffect.acts,
  'set_app_settings': ToolEffect.acts,
  'native_tap': ToolEffect.acts,
  'native_text': ToolEffect.acts,
  'native_button': ToolEffect.acts,
  'native_open_app': ToolEffect.acts,
  'hot_reload': ToolEffect.acts,

  // State, storage and network
  'get_state': ToolEffect.reads,
  'set_state': ToolEffect.acts,
  'get_network_logs': ToolEffect.reads,
  'get_http_profile': ToolEffect.reads,
  'get_hive_contents': ToolEffect.reads,
  'exec_sql_query': ToolEffect.reads,
  'get_shared_preferences': ToolEffect.reads,
  'set_shared_preference': ToolEffect.destructive,
  'get_secure_storage': ToolEffect.reads,
  'set_secure_storage_key': ToolEffect.destructive,
  'simulate_network': ToolEffect.acts,
  'mock_http_response': ToolEffect.acts,
  'mock_platform_channel': ToolEffect.acts,
  'get_connectivity': ToolEffect.reads,
  'get_supabase_auth': ToolEffect.reads,
  'query_supabase_table': ToolEffect.reads,
  'supabase_session': ToolEffect.destructive,
  'get_firebase_auth': ToolEffect.reads,
  'query_firestore': ToolEffect.reads,
  'call_custom_tool': ToolEffect.destructive,

  // Performance: the profilers run the actions they are given.
  'profile_frame_budget': ToolEffect.reads,
  'profile_action': ToolEffect.acts,
  'get_memory_details': ToolEffect.acts,

  // Regression and verification
  'compare_screenshot': ToolEffect.acts,
  'generate_test': ToolEffect.acts,
  'verify_feature': ToolEffect.acts,
  'scenario': ToolEffect.destructive,
};

/// Tools that leave the app as it is when called again with the same
/// arguments.
const idempotentTools = <String>{
  'connect_app',
  'register_device',
  'switch_device',
  'scroll_into_view',
  'focus_widget',
  'set_slider_value',
  'set_app_settings',
  'set_state',
  'set_shared_preference',
  'set_secure_storage_key',
  'simulate_network',
  'mock_http_response',
  'native_open_app',
};

/// Tools that reach a service outside the app and the machine it runs on.
const openWorldTools = <String>{
  'query_supabase_table',
  'supabase_session',
  'query_firestore',
};

/// The MCP annotations of the tool called [name].
ToolAnnotations toolAnnotations(String name) {
  final effect = toolEffects[name];
  if (effect == null) {
    throw StateError(
      'Tool "$name" has no entry in toolEffects (tool_annotations.dart).',
    );
  }
  return ToolAnnotations(
    readOnlyHint: effect == ToolEffect.reads,
    destructiveHint: effect == ToolEffect.destructive,
    idempotentHint:
        effect == ToolEffect.reads || idempotentTools.contains(name),
    openWorldHint: openWorldTools.contains(name),
  );
}
