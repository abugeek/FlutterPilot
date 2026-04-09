# Contributing to FlutterPilot

Thank you for your interest in contributing to FlutterPilot! This guide will help you get started.

## Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) >= 3.0.0
- [Dart SDK](https://dart.dev/get-dart) >= 3.11.0
- [Melos](https://melos.invertase.dev/) for monorepo management
- [Node.js](https://nodejs.org/) (for VS Code extension development)

## Getting Started

### 1. Fork and Clone

```bash
git clone https://github.com/<your-username>/flutterpilot.git
cd flutterpilot
```

### 2. Install Melos

```bash
dart pub global activate melos
```

### 3. Bootstrap the Monorepo

```bash
melos bootstrap
```

This links all local packages together so cross-package changes work seamlessly.

### 4. Verify Everything Works

```bash
melos run analyze   # Static analysis
melos run test      # Run all tests
```

## Project Structure

```
FlutterPilot/
├── packages/
│   ├── flutterpilot_sdk/         # Core SDK (in-app, zero deps)
│   ├── flutterpilot_server/      # MCP server bridge
│   ├── flutterpilot_vscode/      # VS Code extension
│   └── plugins/
│       ├── flutterpilot_bloc/    # Bloc state inspector
│       ├── flutterpilot_dio/     # Dio network inspector
│       ├── flutterpilot_drift/   # Drift database inspector
│       ├── flutterpilot_hive/    # Hive storage inspector
│       └── flutterpilot_riverpod/# Riverpod state inspector
├── examples/
│   └── flutter_pilot_example/    # Demo app
└── melos.yaml                    # Monorepo config
```

## Development Workflow

### Running the Example App

```bash
cd examples/flutter_pilot_example
flutter run
```

### Running the MCP Server

```bash
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri <vm-service-uri-from-flutter-run>
```

### Running Tests

```bash
# All packages
melos run test

# Specific package
cd packages/flutterpilot_sdk && flutter test
cd packages/flutterpilot_server && dart test
```

### Code Style

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) conventions
- Run `melos run format` before committing
- Run `melos run analyze` to check for issues
- Keep the SDK dependency-free (only Flutter + `meta`)

## Making Changes

### Bug Fixes

1. Create a branch: `git checkout -b fix/description`
2. Write a test that reproduces the bug
3. Fix the bug
4. Verify all tests pass: `melos run test`
5. Submit a PR

### New Features

1. Open an issue first to discuss the feature
2. Create a branch: `git checkout -b feat/description`
3. Implement with tests
4. Update relevant READMEs
5. Submit a PR

### Adding a New Plugin

1. Create a new package under `packages/plugins/`
2. Follow the existing plugin pattern (see `flutterpilot_bloc` as a reference)
3. Register state setters via `FlutterPilot.registerStateSetter()`
4. Add the package to `melos.yaml`
5. Add tests and a README

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   AI Agent (Claude, etc.)            │
└──────────────────────┬──────────────────────────────┘
                       │ MCP Protocol (JSON-RPC over stdio)
┌──────────────────────▼──────────────────────────────┐
│              flutterpilot_server                     │
│  - 83 MCP tools across 9 categories                 │
│  - Modular tool registration via part files          │
│  - Self-Heal crash detection                        │
│  - VM Service bridge with auto-reconnect            │
└──────────────────────┬──────────────────────────────┘
                       │ VM Service Extensions
┌──────────────────────▼──────────────────────────────┐
│              flutterpilot_sdk (in-app)               │
│  - Service extension registration                   │
│  - Widget tree introspection                        │
│  - Screenshot capture                               │
│  - Error interception                               │
│  - Navigation tracking                              │
│  - UI interaction (tap, scroll, text entry)          │
├─────────────┬──────────┬──────────┬────────┬────────┤
│  bloc plugin│riverpod  │dio plugin│ drift  │ hive   │
│             │  plugin  │          │ plugin │ plugin │
└─────────────┴──────────┴──────────┴────────┴────────┘
```

**Key constraint:** The MCP server uses stdin/stdout for JSON-RPC communication. All logging MUST go to stderr (`stderr.writeln()`), never `print()`.

## Pull Request Guidelines

- Keep PRs focused on a single concern
- Include tests for new functionality
- Update documentation if needed
- Ensure `melos run analyze` passes with no issues
- Ensure `melos run test` passes

## License

By contributing to FlutterPilot, you agree that your contributions will be licensed under the MIT License.
