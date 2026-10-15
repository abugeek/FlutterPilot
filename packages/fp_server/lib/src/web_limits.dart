/// What a web app's VM service (DWDS, in the browser) doesn't have: CPU
/// samples and the VM timeline (profile_action) and dart:io's HTTP profile
/// (get_http_profile). These tools are not listed for web apps.
const webUnsupportedTools = {'profile_action', 'get_http_profile'};

/// The error when one is called anyway (or get_memory_details' allocation
/// modes, which the browser lacks too).
String notOnWeb(String what, String why) =>
    '$what is not available for web apps: $why. It works on the same app '
    'run on macOS, iOS or Android.';
