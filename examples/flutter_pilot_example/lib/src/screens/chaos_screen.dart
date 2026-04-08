import 'package:flutter/material.dart';

class ChaosScreen extends StatefulWidget {
  const ChaosScreen({super.key});

  @override
  State<ChaosScreen> createState() => _ChaosScreenState();
}

class _ChaosScreenState extends State<ChaosScreen> {
  void _triggerSyncError() {
    throw StateError('This is a simulated synchronous crash from ChaosScreen.');
  }

  void _triggerAsyncError() async {
    await Future.delayed(const Duration(milliseconds: 500));
    throw Exception('This is a simulated asynchronous crash from ChaosScreen.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chaos & Self-Heal')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 80, color: Colors.orange),
            const SizedBox(height: 20),
            const Text('Test the Self-Heal loop by crashing the app.'),
            const SizedBox(height: 40),
            ElevatedButton(
              key: const Key('trigger_sync_error_button'),
              onPressed: _triggerSyncError,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Trigger Sync Error'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              key: const Key('trigger_async_error_button'),
              onPressed: _triggerAsyncError,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              child: const Text('Trigger Async Error'),
            ),
          ],
        ),
      ),
    );
  }
}
