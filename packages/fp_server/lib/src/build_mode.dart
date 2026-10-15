import 'package:vm_service/vm_service.dart';

/// How the app was built, as far as tools care: debug (JIT, hot reload,
/// source locations, slow frames) or profile (AOT, release-like timings,
/// none of those). Release builds have no VM service to connect to.
enum BuildMode { debug, profile }

/// From the VM's flags: profile builds run precompiled (AOT) code.
BuildMode buildModeFromFlags(List<Flag> flags) {
  final precompiled = flags
      .where((f) => f.name == 'precompiled_mode')
      .map((f) => f.valueAsString)
      .firstOrNull;
  return precompiled == 'true' ? BuildMode.profile : BuildMode.debug;
}

/// Tools that need a debug build: hot reload and restart (JIT), and what is
/// built on them (recording from a restart, loading a scenario).
const debugOnlyTools = {'hot_reload', 'generate_test', 'scenario'};

const profileBuildNote =
    'Profile build: timings are close to release (build tracing adds a '
    'little).';

const debugBuildNote =
    'Debug build: times run several times slower than release (widget '
    'build tracing adds some); confirm jank on a "flutter run --profile" '
    'build.';
