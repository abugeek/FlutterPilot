/// Tools that only work when a FlutterPilot plugin is registered in the app,
/// with the service extensions that plugin registers. A tool is listed once
/// the app has registered any of its extensions, so an app without Supabase,
/// Firebase or Hive never pays for those tools' descriptions.
const Map<String, List<String>> pluginToolExtensions = {
  // flutterpilot_riverpod / flutterpilot_bloc
  // (set_* go through the SDK's generic setState, but need the plugin.)
  'get_riverpod_state': ['ext.flutterpilot.getRiverpodStates'],
  'set_riverpod_state': ['ext.flutterpilot.getRiverpodStates'],
  'get_bloc_state': ['ext.flutterpilot.getBlocStates'],
  'set_bloc_state': ['ext.flutterpilot.getBlocStates'],
  'batch_set_state': [
    'ext.flutterpilot.getRiverpodStates',
    'ext.flutterpilot.getBlocStates',
  ],
  'wait_for_state': [
    'ext.flutterpilot.getRiverpodStates',
    'ext.flutterpilot.getBlocStates',
  ],
  // flutterpilot_dio
  'get_network_logs': ['ext.flutterpilot.getNetworkLogs'],
  'simulate_network': ['ext.flutterpilot.simulateNetwork'],
  'mock_http_response': ['ext.flutterpilot.addHttpMock'],
  'clear_http_mocks': ['ext.flutterpilot.clearHttpMocks'],
  // flutterpilot_hive
  'get_hive_contents': ['ext.flutterpilot.getHiveContents'],
  // flutterpilot_drift / flutterpilot_sqflite
  'list_drift_tables': ['ext.flutterpilot.listDriftTables'],
  'list_sqflite_databases': ['ext.flutterpilot.listSqfliteDatabases'],
  'list_sqflite_tables': ['ext.flutterpilot.listSqfliteTables'],
  'exec_sql_query': [
    'ext.flutterpilot.queryDrift',
    'ext.flutterpilot.querySqflite',
  ],
  // flutterpilot_shared_preferences
  'get_shared_preferences': ['ext.flutterpilot.getSharedPreferences'],
  'set_shared_preference': ['ext.flutterpilot.setSharedPreference'],
  'clear_shared_preferences': ['ext.flutterpilot.clearSharedPreferences'],
  // flutterpilot_supabase
  'get_supabase_auth': ['ext.flutterpilot.getSupabaseAuth'],
  'get_supabase_realtime': ['ext.flutterpilot.getSupabaseRealtime'],
  'query_supabase_table': ['ext.flutterpilot.querySupabaseTable'],
  'supabase_sign_out': ['ext.flutterpilot.supabaseSignOut'],
  'supabase_refresh_session': ['ext.flutterpilot.supabaseRefreshSession'],
  // flutterpilot_gorouter
  'get_gorouter_state': ['ext.flutterpilot.getGoRouterState'],
  'get_gorouter_config': ['ext.flutterpilot.getGoRouterConfig'],
  'get_gorouter_history': ['ext.flutterpilot.getGoRouterHistory'],
  'gorouter_navigate': ['ext.flutterpilot.goRouterNavigate'],
  // flutterpilot_connectivity
  'get_connectivity': ['ext.flutterpilot.getConnectivity'],
  'get_connectivity_history': ['ext.flutterpilot.getConnectivityHistory'],
  // flutterpilot_firebase
  'get_firebase_auth': ['ext.flutterpilot.getFirebaseAuth'],
  'query_firestore': ['ext.flutterpilot.queryFirestore'],
  // flutterpilot_secure_storage
  'get_secure_storage_keys': ['ext.flutterpilot.getSecureStorageKeys'],
  'read_secure_storage_key': ['ext.flutterpilot.readSecureStorageKey'],
  'set_secure_storage_key': ['ext.flutterpilot.setSecureStorageKey'],
  'delete_secure_storage_key': ['ext.flutterpilot.deleteSecureStorageKey'],
};
