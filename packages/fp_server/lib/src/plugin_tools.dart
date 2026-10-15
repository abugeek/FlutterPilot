/// Tools that only work when a FlutterPilot plugin is registered in the app,
/// with the service extensions that plugin registers. A tool is listed once
/// the app has registered any of its extensions, so an app without Supabase,
/// Firebase or Hive never pays for those tools' descriptions.
const Map<String, List<String>> pluginToolExtensions = {
  // fp_riverpod / fp_bloc
  // (set_state goes through the SDK's generic setState, but needs a plugin.)
  'get_state': [
    'ext.flutterpilot.getRiverpodStates',
    'ext.flutterpilot.getBlocStates',
  ],
  'set_state': [
    'ext.flutterpilot.getRiverpodStates',
    'ext.flutterpilot.getBlocStates',
  ],
  // fp_dio
  'get_network_logs': ['ext.flutterpilot.getNetworkLogs'],
  'simulate_network': ['ext.flutterpilot.simulateNetwork'],
  'mock_http_response': ['ext.flutterpilot.addHttpMock'],
  // fp_hive
  'get_hive_contents': ['ext.flutterpilot.getHiveContents'],
  // fp_drift / fp_sqflite
  'exec_sql_query': [
    'ext.flutterpilot.queryDrift',
    'ext.flutterpilot.querySqflite',
  ],
  // fp_shared_preferences
  'get_shared_preferences': ['ext.flutterpilot.getSharedPreferences'],
  'set_shared_preference': ['ext.flutterpilot.setSharedPreference'],
  // fp_supabase
  'get_supabase_auth': ['ext.flutterpilot.getSupabaseAuth'],
  'query_supabase_table': ['ext.flutterpilot.querySupabaseTable'],
  'supabase_session': ['ext.flutterpilot.supabaseSignOut'],
  // fp_connectivity
  'get_connectivity': ['ext.flutterpilot.getConnectivity'],
  // fp_firebase
  'get_firebase_auth': ['ext.flutterpilot.getFirebaseAuth'],
  'query_firestore': ['ext.flutterpilot.queryFirestore'],
  // fp_secure_storage
  'get_secure_storage': ['ext.flutterpilot.getSecureStorageKeys'],
  'set_secure_storage_key': ['ext.flutterpilot.setSecureStorageKey'],
};
