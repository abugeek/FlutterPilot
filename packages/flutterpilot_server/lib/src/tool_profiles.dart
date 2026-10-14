/// A client that counts tools across every MCP server it runs (Cursor has
/// historically capped around 40) can start FlutterPilot with
/// `--tools core` and get a smaller list. `all` is the default: nothing
/// changes for existing users.
library;

/// Which set of tools the server lists.
enum ToolProfile {
  /// Only [coreTools] (intersected with what works for the app).
  core,

  /// Every tool that works for the app.
  all;

  static ToolProfile byName(String name) =>
      values.firstWhere((p) => p.name == name);
}

/// The tools a Flutter session needs most, chosen from data rather than
/// taste:
///
/// * every tool task 01's 14 eval tasks name in `expected_tools`, so the core
///   profile doesn't fail them by construction;
/// * the tools an agent needs to see what it broke and recover:
///   `get_app_summary`, `get_errors`, `get_debug_logs`, `hot_reload`,
///   `launch_app`;
/// * the interaction basics from task 08's starting list (`tap_widget`,
///   `enter_text`, `press_key`, `scroll_into_view`, `fill_form`,
///   `execute_action_chain`, `navigate_to`, `wait_for`, `assert_widget`) and
///   the two inspection readers (`capture_screenshot`, `get_widget_tree`).
///
/// 29 names. Task 08's starting list was 20, but that set fails 8 of the 14
/// eval tasks (they name `set_app_settings`, `get_network_logs`,
/// `simulate_network`, `toggle_checkbox`, `get_shared_preferences`,
/// `profile_action`, `get_memory_details`, `exec_sql_query` or
/// `get_secure_storage`), and the task calls a set that fails more than 2
/// "the wrong core set". 29 + the Dart MCP server's ~5 code tools still fits
/// under Cursor's ~40.
///
/// This is a *subset* request, not a promise: a zero-code app with
/// `--tools core` sees `coreTools` ∩ `zeroCodeTools`.
const Set<String> coreTools = {
  // Recovery and orientation.
  'launch_app',
  'get_app_summary',
  'get_errors',
  'get_debug_logs',
  'hot_reload',
  // Inspecting what is on screen.
  'capture_screenshot',
  'get_widget_tree',
  'inspect_widget',
  'audit_screen_health',
  // Acting on it.
  'tap_widget',
  'enter_text',
  'press_key',
  'scroll_into_view',
  'fill_form',
  'execute_action_chain',
  'navigate_to',
  'toggle_checkbox',
  // Waiting and checking.
  'wait_for',
  'assert_widget',
  // A short loop: answer a request, keep a preference, see state.
  'mock_http_response',
  'simulate_network',
  'get_network_logs',
  'set_app_settings',
  'get_shared_preferences',
  'get_secure_storage',
  'get_state',
  'exec_sql_query',
  'get_memory_details',
  'profile_action',
};
