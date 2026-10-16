# Releasing FlutterPilot to pub.dev

All 15 packages are released together with one version number (the SDK,
12 plugins, the server, the CLI). Publishing is permanent: a version can be
retracted but never deleted or re-uploaded.

## Check

```bash
dart run tool/publish_check.dart
```

It dry-runs every package in publish order and fails on any warning. Commit
first: uncommitted changes are a warning. The plugins show a hint about
`pubspec_overrides.yaml`. That's expected: pub.dev has no `fp_sdk`
yet, so the check points them at the checkout's.

## Version bump (later releases)

Set the same `version:` in all 15 `pubspec.yaml` files, the plugins'
`fp_sdk: ^x.y.z` constraint, and `flutterpilotVersion` in
`packages/fp_cli/lib/src/version.dart` (a test keeps it equal to
the CLI's pubspec). Add a CHANGELOG entry to each package.

## Publish (in this order)

```bash
dart pub login   # once, with the account that should own the packages
cd packages/fp_sdk && flutter pub publish && cd -
for p in packages/plugins/*/; do (cd "$p" && flutter pub publish); done
cd packages/fp_server && dart pub publish && cd -
cd packages/fp_cli && dart pub publish && cd -
```

The SDK comes first because the plugins depend on it. Wait until it shows on
pub.dev before publishing a plugin. The server and CLI come last.

Consider creating a verified publisher on pub.dev first and transferring
the packages to it.

## After publishing

- `flutterpilot init` now uses pub.dev by itself. Its default `--source
  auto` checks whether `fp_sdk` is there, so nothing needs
  changing.
- `dart pub global activate fp_cli` installs the CLI. Its `mcp
  install` builds the server from a small package depending on
  `fp_server` in `~/.flutterpilot/server`.
- Tag the release: `git tag v0.1.0 && git push origin v0.1.0`.
