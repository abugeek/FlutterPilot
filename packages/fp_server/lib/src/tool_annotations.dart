import 'package:mcp_dart/mcp_dart.dart';

/// What a tool does to the app, as MCP clients are told (tool annotations):
/// they run [reads] tools without asking and in parallel, and ask before a
/// [destructive] one.
enum ToolEffect {
  /// Returns what the app shows or holds and changes nothing in it. A tool
  /// that *can* clear FlutterPilot's own capture of logs, requests or state
  /// changes (see [acts]) is not listed here, because the advertised hint must
  /// cover the strongest thing a call may do — even though the clearing mode
  /// touches nothing of the app's.
  reads,

  /// Drives the app as a user or developer would (taps, text, navigation,
  /// settings, mocks, a hot reload, a route sweep that ends by navigating
  /// back) or writes a new file (a test, a report). What the app does in
  /// response is the app's own. Tools whose `clear: true` mode merely empties
  /// FlutterPilot's captured diagnostics are listed here too, under the same
  /// rule: advertise the strongest effect, and let the argument-aware policy
  /// in `effect_policy.dart` treat the non-clearing call as the read it is.
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
  'launch_app': ToolEffect.acts,
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
  'inspect_widget': ToolEffect.reads,
  'capture_screenshot': ToolEffect.reads,
  'assert_widget': ToolEffect.reads,
  'wait_for': ToolEffect.reads,
  'native_screenshot': ToolEffect.reads,
  'native_describe_screen': ToolEffect.reads,

  // Read unless you ask them to clear FlutterPilot's own capture (get_state
  // `clear`, get_debug_logs `clear`, get_http_profile `clear`): the advertised
  // hint covers the clearing mode, and `effect_policy.dart` recognises the
  // non-clearing call as the read it is. `audit_screen_health` is here because
  // `routes` sweeps navigate (and only best-effort return) — the current-screen
  // call observes, the sweep acts.
  'get_state': ToolEffect.acts,
  'get_debug_logs': ToolEffect.acts,
  'get_http_profile': ToolEffect.acts,
  'audit_screen_health': ToolEffect.acts,

  // Driving it
  'tap_widget': ToolEffect.acts,
  'enter_text': ToolEffect.acts,
  'press_key': ToolEffect.acts,
  'gesture_widget': ToolEffect.acts,
  'scroll_into_view': ToolEffect.acts,
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
  'set_state': ToolEffect.acts,
  'get_network_logs': ToolEffect.reads,
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
  'set_app_settings',
  'set_state',
  'set_shared_preference',
  'set_secure_storage_key',
  'simulate_network',
  'mock_http_response',
  'native_open_app',
};

/// Tools that reach a service outside the app and the machine it runs on, or
/// run code whose outbound effects FlutterPilot cannot see: a tap can submit a
/// form, a reload can open a socket, custom code can call anything. The trust
/// boundary is the app's reach, not the server's: the VM Service is local, but
/// what the app does when driven is not. Tools that only read FlutterPilot's
/// own capture, or that set local diagnostic state (mocks, network simulation,
/// settings) without running app code, stay closed-world.
const openWorldTools = <String>{
  // External services FlutterPilot calls itself.
  'query_supabase_table',
  'supabase_session',
  'query_firestore',
  // Everything that drives the app or runs its own code.
  'launch_app',
  'run_on_devices',
  'tap_widget',
  'enter_text',
  'press_key',
  'gesture_widget',
  'scroll_into_view',
  'toggle_checkbox',
  'fill_form',
  'execute_action_chain',
  'navigate_to',
  'native_tap',
  'native_text',
  'native_button',
  'native_open_app',
  'hot_reload',
  'set_state',
  'set_app_settings',
  'call_custom_tool',
  'profile_action',
  'get_memory_details',
  'verify_feature',
  'generate_test',
  'scenario',
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

/// Tools that draw the screen to pixels. On a phone that is off or locked the
/// engine crashes doing that, so they are refused there.
const rasterTools = {
  'capture_screenshot',
  'compare_screenshot',
  'audit_screen_health',
};
