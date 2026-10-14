FlutterPilot inspects and drives a running Flutter app (flutter run, debug or profile build).
- No app running: launch_app. Start with get_app_summary: route, what can be tapped (labels and keys), errors, logs. Only tools that work for the connected app are listed; without flutterpilot_sdk in the app it can be inspected but not driven, and the summary says so.
- <!-- include: finding-widgets -->
- Actions (tap_widget, enter_text, press_key, fill_form, ...) report what they changed: route, widget diff, what is tappable now, new errors. Read that before taking a screenshot or reading the tree again.
- <!-- include: batching -->
- Check an outcome with assert_widget or wait_for (milliseconds, no sleeping) and layout with audit_screen_health.
- After editing Dart code: hot_reload, then get_errors. hot_reload(restart: true) loads every changed Dart file and runs main() again: use it after a git checkout or for a stuck app. Keep the app running; launch_app(relaunch: true) rebuilds it (minutes): only for pubspec.yaml, assets or native code changes.
