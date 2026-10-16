import 'build_mode.dart';
import 'plugin_tools.dart';
import 'tool_list_bytes.dart';
import 'zero_code.dart';

/// The app shapes the surface report measures, so task 04 can decide which
/// tools to merge from numbers instead of taste.
enum AppProfile {
  all('all', 'every tool (--static-tools)'),
  sdkNoPlugins('sdk_no_plugins', 'fp_sdk, no plugin'),
  sdkDio('sdk_dio', 'fp_sdk + fp_dio'),
  sdkLabShop('sdk_lab_shop', 'fp_lab_shop plugins'),
  sdkLabNotes('sdk_lab_notes', 'fp_lab_notes plugins'),
  zeroCode('zero_code', 'no fp_sdk'),
  profileBuild('profile_build', 'sdk_lab_shop, profile build');

  const AppProfile(this.id, this.description);

  /// The name the report prints and the JSON keys use.
  final String id;

  /// What the profile is, in a few words.
  final String description;
}

/// The service extensions each plugin registers, read from the `extensions`
/// list at the top of `packages/plugins/fp_NAME/lib/fp_NAME.dart`. Only the
/// extensions a tool is gated on matter (`plugin_tools.dart`), but the whole
/// list is kept so a new gate can be checked against it here.
const Map<String, List<String>> pluginExtensions = {
  'bloc': ['ext.flutterpilot.getBlocStates'],
  'connectivity': [
    'ext.flutterpilot.getConnectivity',
    'ext.flutterpilot.getConnectivityHistory',
  ],
  'dio': [
    'ext.flutterpilot.getNetworkLogs',
    'ext.flutterpilot.simulateNetwork',
    'ext.flutterpilot.addHttpMock',
    'ext.flutterpilot.getHttpMocks',
    'ext.flutterpilot.clearHttpMocks',
  ],
  'drift': [
    'ext.flutterpilot.listDriftTables',
    'ext.flutterpilot.queryDrift',
    'ext.flutterpilot.dumpDrift',
    'ext.flutterpilot.restoreDrift',
  ],
  'firebase': [
    'ext.flutterpilot.getFirebaseAuth',
    'ext.flutterpilot.queryFirestore',
  ],
  'gorouter': [
    'ext.flutterpilot.getGoRouterConfig',
    'ext.flutterpilot.getGoRouterHistory',
    'ext.flutterpilot.getGoRouterState',
    'ext.flutterpilot.goRouterNavigate',
  ],
  'hive': [
    'ext.flutterpilot.getHiveContents',
    'ext.flutterpilot.dumpHive',
    'ext.flutterpilot.restoreHive',
  ],
  'riverpod': ['ext.flutterpilot.getRiverpodStates'],
  'secure_storage': [
    'ext.flutterpilot.getSecureStorageKeys',
    'ext.flutterpilot.readSecureStorageKey',
    'ext.flutterpilot.setSecureStorageKey',
    'ext.flutterpilot.deleteSecureStorageKey',
  ],
  'shared_preferences': [
    'ext.flutterpilot.getSharedPreferences',
    'ext.flutterpilot.setSharedPreference',
    'ext.flutterpilot.clearSharedPreferences',
  ],
  'sqflite': [
    'ext.flutterpilot.listSqfliteDatabases',
    'ext.flutterpilot.listSqfliteTables',
    'ext.flutterpilot.querySqflite',
    'ext.flutterpilot.dumpSqflite',
    'ext.flutterpilot.restoreSqflite',
  ],
  'supabase': [
    'ext.flutterpilot.getSupabaseAuth',
    'ext.flutterpilot.getSupabaseRealtime',
    'ext.flutterpilot.querySupabaseTable',
    'ext.flutterpilot.supabaseRefreshSession',
    'ext.flutterpilot.supabaseSignOut',
  ],
};

/// fp_lab_shop's plugins.
const _labShopPlugins = [
  'dio',
  'gorouter',
  'riverpod',
  'sqflite',
  'shared_preferences',
];

/// fp_lab_notes' plugins.
const _labNotesPlugins = [
  'bloc',
  'drift',
  'hive',
  'secure_storage',
  'connectivity',
];

Set<String> _extensionsOf(Iterable<String> plugins) => {
  for (final plugin in plugins) ...pluginExtensions[plugin]!,
};

/// The tools an app of [profile] sees, by name, sorted.
///
/// Mirrors the visibility rule in `updateToolVisibility`: with the SDK an app
/// sees the SDK tools plus the plugin tools whose plugin registered an
/// extension, native tools are platform-gated and left out, and the zero-code
/// set is [zeroCodeTools]. Formula rather than a live connection so the
/// report can describe an app this checkout never runs.
List<String> profileToolNames(AppProfile profile, Iterable<String> all) {
  final names = all.toSet();
  final base = names
      .where(
        (name) =>
            !pluginToolExtensions.containsKey(name) &&
            !name.startsWith('native_'),
      )
      .toSet();
  Set<String> withPlugins(Set<String> extensions) => {
    ...base,
    for (final name in names)
      if (pluginToolExtensions[name]?.any(extensions.contains) ?? false) name,
  };
  final shop = withPlugins(_extensionsOf(_labShopPlugins));
  return switch (profile) {
    AppProfile.all => names.toList()..sort(),
    AppProfile.sdkNoPlugins => base.toList()..sort(),
    AppProfile.sdkDio => withPlugins(
      _extensionsOf(const ['dio']),
    ).toList()..sort(),
    AppProfile.sdkLabShop => shop.toList()..sort(),
    AppProfile.sdkLabNotes => withPlugins(
      _extensionsOf(_labNotesPlugins),
    ).toList()..sort(),
    AppProfile.zeroCode => names.where(zeroCodeTools.contains).toList()..sort(),
    AppProfile.profileBuild =>
      shop.where((name) => !debugOnlyTools.contains(name)).toList()..sort(),
  };
}

/// What [profile] costs: the tools it lists, the bytes they add to
/// `tools/list`, and a token estimate (bytes / 4, an estimate and labelled as
/// one). [listJson] is the server's `toolListJson`.
({int tools, int bytes, int tokens, List<({String name, int bytes})> perTool})
profileCost(
  AppProfile profile,
  Iterable<String> all,
  List<Map<String, dynamic>> Function(Iterable<String> names) listJson,
) {
  final entries = listJson(profileToolNames(profile, all));
  final perTool = [
    for (final entry in entries)
      (name: entry['name'] as String, bytes: toolListBytes(entry)),
  ]..sort((a, b) => b.bytes.compareTo(a.bytes));
  final bytes = perTool.fold(0, (sum, tool) => sum + tool.bytes);
  return (
    tools: perTool.length,
    bytes: bytes,
    tokens: bytes ~/ 4,
    perTool: perTool,
  );
}
