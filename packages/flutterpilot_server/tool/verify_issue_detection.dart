import 'package:vm_service/vm_service_io.dart';

void main() async {
  const wsUri = 'ws://127.0.0.1:60737/NoW6oZ8wAF8=/ws';
  print('Connecting to VM Service at $wsUri...');
  final vm = await vmServiceConnectUri(wsUri);

  final vmData = await vm.getVM();
  final isolateRef = vmData.isolates!.first;
  final isolateId = isolateRef.id!;
  print('Connected to isolate $isolateId');

  Future<Map<String, dynamic>> callExt(String method, [Map<String, dynamic>? args]) async {
    final res = await vm.callServiceExtension(
      method,
      isolateId: isolateId,
      args: args?.map((k, v) => MapEntry(k, v.toString())),
    );
    return res.json ?? <String, dynamic>{};
  }

  // 1. Initial Clean Check
  print('\n--- [1] Initial Issues Check ---');
  final initialIssues = await callExt('ext.flutterpilot.getAppIssues', {'severity': 'all'});
  print('Initial isHealthy: ${initialIssues['isHealthy']} (Total: ${initialIssues['totalActive']})');
  print('Initial Issues: ${initialIssues['issues']}');

  // 2. Simulate Supabase RLS Permission Denied & Network Offline via Log Sniffing
  print('\n--- [2] Simulating Real-World Defects (Supabase RLS, RenderFlex, Offline Network) ---');
  final isolate = await vm.getIsolate(isolateId);
  final rootLibId = isolate.rootLib!.id!;

  await vm.evaluate(
    isolateId,
    rootLibId,
    'debugPrint("PostgrestException(message: new row violates row-level security policy for table \\"orders\\", code: 42501)")',
  );
  await vm.evaluate(
    isolateId,
    rootLibId,
    'debugPrint("[cloud_firestore/permission-denied] Missing or insufficient permissions.")',
  );
  await vm.evaluate(
    isolateId,
    rootLibId,
    'debugPrint("A RenderFlex overflowed by 34.0 pixels on the bottom.")',
  );
  await vm.evaluate(
    isolateId,
    rootLibId,
    'debugPrint("SocketException: Failed host lookup: \\"api.supabase.co\\" (OS Error: No address associated with hostname, errno = 7)")',
  );

  // Allow event loop to process
  await Future.delayed(const Duration(milliseconds: 100));

  // 3. Query getAppIssues
  print('\n--- [3] Centralized Issues Detection Audit ---');
  final detected = await callExt('ext.flutterpilot.getAppIssues', {'severity': 'warning'});
  print('Healthy: ${detected['isHealthy']}');
  print('Critical Count: ${detected['criticalCount']}');
  print('Warning Count: ${detected['warningCount']}');
  final issues = detected['issues'] as List;
  print('Total Detected Issues: ${issues.length}');
  for (final issue in issues) {
    print(' • [${issue['severity'].toString().toUpperCase()}] [${issue['category']}]: ${issue['title']} (x${issue['occurrenceCount']})');
  }

  assert(detected['criticalCount'] >= 3, 'Should detect critical issues across RLS, Firebase, RenderFlex, Network');

  // 4. Test Snapshot Consolidation
  print('\n--- [4] App Snapshot Integration ---');
  final snapshot = await callExt('ext.flutterpilot.getAppSnapshot');
  final snapIssues = snapshot['issues'];
  print('Snapshot issues section:');
  print(' - Healthy: ${snapIssues['isHealthy']}');
  print(' - Critical: ${snapIssues['criticalCount']}');
  print(' - Warning: ${snapIssues['warningCount']}');

  // 5. Test Clear
  print('\n--- [5] Clear App Issues ---');
  final clearRes = await callExt('ext.flutterpilot.clearAppIssues');
  print('Clear result: $clearRes');

  final cleanIssues = await callExt('ext.flutterpilot.getAppIssues');
  print('Post-clear isHealthy: ${cleanIssues['isHealthy']} (Total: ${cleanIssues['totalActive']})');
  assert(cleanIssues['isHealthy'] == true, 'State should be clean after clear');

  print('\n🎉 All live automatic issue detection tests passed on the emulator!');
  await vm.dispose();
}
