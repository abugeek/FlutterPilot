# Publish FlutterPilot 0.1.0

FlutterPilot's first pub.dev release contains 15 packages: the SDK, 12
plugins, the MCP server, and the CLI. All packages use version `0.1.0`.
Published versions cannot be replaced or deleted, so publish only after every
check passes.

## Validate

Run from the repository root with a clean worktree:

```bash
dart run tool/package_test_runner.dart
dart run tool/publish_check.dart
```

The test runner fails if a package is missing its test dependencies or if any
suite fails. The publish checker runs a dry run for all 15 packages in
dependency order. Plugin dry runs temporarily point `fp_sdk` at this checkout;
the actual plugin releases resolve the hosted `fp_sdk`.

Confirm all package manifests and changelogs describe `0.1.0`. Every package
name must be available to the pub.dev account that will publish it.

## Sign in

Use the Google account that should own the packages:

```bash
dart pub login
```

Choose the account or verified publisher before publishing. A verified
publisher requires a domain you control; pub.dev can transfer packages to it
after an initial account publication.

## Publish

Publish `fp_sdk` first. Wait until its page is available on pub.dev before
publishing plugins, because each plugin depends on the hosted SDK. Publish each
package separately and inspect pub's file list before confirming.

```bash
cd packages/fp_sdk && flutter pub publish
```

Then publish the 12 plugins, one at a time:

```bash
cd packages/plugins/fp_bloc && flutter pub publish
cd ../fp_connectivity && flutter pub publish
cd ../fp_dio && flutter pub publish
cd ../fp_drift && flutter pub publish
cd ../fp_firebase && flutter pub publish
cd ../fp_gorouter && flutter pub publish
cd ../fp_hive && flutter pub publish
cd ../fp_riverpod && flutter pub publish
cd ../fp_secure_storage && flutter pub publish
cd ../fp_shared_preferences && flutter pub publish
cd ../fp_sqflite && flutter pub publish
cd ../fp_supabase && flutter pub publish
cd ../../fp_server && dart pub publish
cd ../fp_cli && dart pub publish
```

Verify every package page and version after publishing. In a clean Flutter
project, confirm the new-user workflow:

```bash
dart pub global activate fp_cli
fp init
fp mcp install
flutter run
```

`fp init` selects hosted packages once `fp_sdk` is available. It detects
supported integrations and prints any plugin wiring the app still needs.

## Replace the old GitHub pre-release

The existing GitHub `v0.1.0` pre-release points to legacy package names and
older source. After the packages publish and the release commit is pushed,
replace that release and tag with the current source:

```bash
gh release delete v0.1.0 --cleanup-tag --yes
git tag -fa v0.1.0 -m "FlutterPilot 0.1.0"
git push origin v0.1.0
```

Create a non-prerelease GitHub release for `v0.1.0` with notes describing the
15 packages, the MCP/CLI setup, and the current tool inventory.

## Later releases

Bump all 15 package versions together. Update plugin constraints on `fp_sdk`,
`flutterpilotVersion` in `packages/fp_cli/lib/src/version.dart`, and each
package changelog. Run both validation commands above before publishing the
new versions.
