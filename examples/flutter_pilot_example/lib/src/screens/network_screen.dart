import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

/// Demonstrates the FlutterPilot Dio interceptor for network introspection.
///
/// Makes real HTTP requests using Dio. The [DioPilotInterceptor] (added
/// in main.dart) automatically captures all traffic so an AI agent can
/// call `ext.flutterpilot.getNetworkLogs` to review it.
class NetworkScreen extends StatefulWidget {
  final Dio dio;
  const NetworkScreen({super.key, required this.dio});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final List<_RequestResult> _results = [];
  bool _loading = false;

  Future<void> _makeRequest(String url, {String label = ''}) async {
    setState(() => _loading = true);
    try {
      final stopwatch = Stopwatch()..start();
      final response = await widget.dio.get(url);
      stopwatch.stop();
      setState(() {
        _results.insert(
          0,
          _RequestResult(
            label: label.isNotEmpty ? label : url,
            statusCode: response.statusCode ?? 0,
            duration: stopwatch.elapsed,
            error: null,
          ),
        );
      });
    } on DioException catch (e) {
      setState(() {
        _results.insert(
          0,
          _RequestResult(
            label: label.isNotEmpty ? label : url,
            statusCode: e.response?.statusCode ?? 0,
            duration: Duration.zero,
            error: e.message ?? 'Unknown error',
          ),
        );
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network & Logs')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.blue.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.smart_toy, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI Agent: call ext.flutterpilot.getNetworkLogs '
                        'to inspect captured traffic.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  key: const Key('fetch_posts_button'),
                  onPressed: _loading
                      ? null
                      : () => _makeRequest(
                          'https://jsonplaceholder.typicode.com/posts/1',
                          label: 'GET /posts/1',
                        ),
                  icon: const Icon(Icons.download),
                  label: const Text('Fetch Post'),
                ),
                ElevatedButton.icon(
                  key: const Key('fetch_users_button'),
                  onPressed: _loading
                      ? null
                      : () => _makeRequest(
                          'https://jsonplaceholder.typicode.com/users/1',
                          label: 'GET /users/1',
                        ),
                  icon: const Icon(Icons.person),
                  label: const Text('Fetch User'),
                ),
                ElevatedButton.icon(
                  key: const Key('fetch_404_button'),
                  onPressed: _loading
                      ? null
                      : () => _makeRequest(
                          'https://jsonplaceholder.typicode.com/posts/99999',
                          label: 'GET /posts/99999',
                        ),
                  icon: const Icon(Icons.error_outline),
                  label: const Text('404 Request'),
                ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 16),
            Text(
              'Request History (${_results.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            Expanded(
              child: _results.isEmpty
                  ? const Center(
                      child: Text(
                        'No requests yet. Tap a button above.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('network_log_list'),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final r = _results[index];
                        return ListTile(
                          leading: Icon(
                            r.error != null ? Icons.error : Icons.check_circle,
                            color: r.error != null ? Colors.red : Colors.green,
                          ),
                          title: Text(r.label),
                          subtitle: Text(
                            r.error ??
                                '${r.statusCode} • ${r.duration.inMilliseconds}ms',
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestResult {
  final String label;
  final int statusCode;
  final Duration duration;
  final String? error;

  _RequestResult({
    required this.label,
    required this.statusCode,
    required this.duration,
    this.error,
  });
}
