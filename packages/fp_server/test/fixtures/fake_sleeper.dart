// A long-lived process the fake Inspector starts so a wrapper test can prove a
// failed probe does not leave a descendant running. Test support, not shipped.
library;

import 'dart:async';

Future<void> main() async {
  await Future<void>.delayed(const Duration(minutes: 5));
}
