// Raw-suite entry point for the shared stdout-hygiene helpers (task 03).
//
// The implementation lives under `tool/support/` so the task-09 startup
// benchmark can reuse the exact same framing rules; this file only re-exports
// it, keeping the suite's `support/stdout_hygiene.dart` import stable.
library;

export '../../tool/support/stdio_hygiene.dart';
