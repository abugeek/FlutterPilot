/// No dart:io (web): requests can't be intercepted below the app's client.
void installHttpOverrides() {}

bool get httpOverridesActive => false;
