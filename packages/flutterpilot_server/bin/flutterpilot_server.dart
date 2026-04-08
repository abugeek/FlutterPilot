import 'dart:io';
import 'package:args/args.dart';
import 'package:flutterpilot_server/flutterpilot_server.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('uri', abbr: 'u', help: 'The VM Service URI of the running Flutter app.')
    ..addFlag('allow-destructive', abbr: 'd', help: 'Allow non-SELECT queries on databases.', negatable: false);

  final results = parser.parse(args);
  final uri = results['uri'];
  final allowDestructive = results['allow-destructive'] as bool;

  if (uri == null) {
    // Usage message goes to stderr — stdout is reserved for MCP JSON-RPC.
    stderr.writeln('Usage: flutterpilot_server --uri <vm-service-uri> [--allow-destructive]');
    exit(1);
  }

  final server = FlutterPilotServer(
    vmServiceUri: uri,
    allowDestructive: allowDestructive,
  );

  // Handle graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    stderr.writeln('Shutting down FlutterPilot server...');
    await server.stop();
    exit(0);
  });

  try {
    await server.start();
  } catch (e, st) {
    stderr.writeln('Error starting server: $e\n$st');
    exit(1);
  }
}
