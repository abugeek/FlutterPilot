import 'package:flutter/foundation.dart';
import 'ring_buffer.dart';
import 'diagnostic_payload.dart';
import 'frame_budget_profiler.dart';
import 'ui_health_auditor.dart';

/// Severity level for issues automatically detected by FlutterPilot.
enum IssueSeverity {
  /// Informational observation (subtle telemetry, low impact). Suppressed from main alerts.
  info,

  /// Warning: noticeable degradation that hurts UX, performance, or accessibility without crashing.
  warning,

  /// Critical: severe breakage (RenderFlex overflow, uncaught crash, database RLS denied, network offline).
  critical;

  bool operator >=(IssueSeverity other) => index >= other.index;
  bool operator >(IssueSeverity other) => index > other.index;
  bool operator <=(IssueSeverity other) => index <= other.index;
  bool operator <(IssueSeverity other) => index < other.index;
}

/// Category of an application issue.
enum IssueCategory {
  /// Visual layout overflow, RenderFlex stripes, clipped content, touch target violations.
  uiLayout,

  /// Frame drops, animation jank, UI-thread build bottlenecks, GPU raster overload.
  performance,

  /// Network failures (4xx, 5xx, timeouts), database errors, offline sync conflicts, Supabase/Firebase RLS.
  dataSync,

  /// Unhandled Dart/Flutter exceptions, StateErrors, RangeErrors, platform channel failures.
  runtime,

  /// Excessive image decoding, memory pressure, cache overflows.
  memory,
}

/// Represents an automatically detected or recorded application issue.
class AppIssue {
  final String id;
  final IssueSeverity severity;
  final IssueCategory category;
  final String title;
  final String details;
  final DateTime timestamp;
  DateTime lastSeen;
  int occurrenceCount;
  final Map<String, dynamic> metadata;
  bool seenByAgent;
  bool isResolved;

  AppIssue({
    String? id,
    required this.severity,
    required this.category,
    required this.title,
    this.details = '',
    DateTime? timestamp,
    DateTime? lastSeen,
    this.occurrenceCount = 1,
    Map<String, dynamic>? metadata,
    this.seenByAgent = false,
    this.isResolved = false,
  })  : id = id ?? _generateSignature(category, title),
        timestamp = timestamp ?? DateTime.now(),
        lastSeen = lastSeen ?? (timestamp ?? DateTime.now()),
        metadata = metadata != null ? DiagnosticPayload.boundedMap(metadata) : const {};

  static String _generateSignature(IssueCategory category, String title) {
    final sanitized = title
        .replaceAll(RegExp(r'[0-9]+(\.[0-9]+)?(px|ms|%)?'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        .toLowerCase();
    return '${category.name}_$sanitized';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity.name,
        'category': category.name,
        'title': title,
        'details': details,
        'timestamp': timestamp.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'occurrenceCount': occurrenceCount,
        'metadata': metadata,
        'seenByAgent': seenByAgent,
        'isResolved': isResolved,
      };
}

/// Centralized, high-performance automatic issue detection engine.
///
/// Continuously aggregates and analyzes telemetry signals across:
/// 1. Network & Database (Supabase RLS, Firebase permissions, HTTP 4xx/5xx, timeouts)
/// 2. Layout & UI (RenderFlex overflow stripes, touch target sizing)
/// 3. Performance & Animation (Frame budget, jank rate, build vs raster bottlenecks)
/// 4. Runtime Exceptions (FlutterError, StateError, unhandled platform errors)
/// 5. Memory & Resources (Oversized texture decodes, image cache overruns)
///
/// Designed for zero overhead (<0.05ms execution) and zero token waste
/// (silent when clean, deduplicated when repeated, and granularly categorized).
class IssueDetector {
  static const int maxIssues = 50;
  static final RingBuffer<AppIssue> _issueHistory = RingBuffer<AppIssue>(maxIssues);
  static final Map<String, AppIssue> _activeIssues = {};
  static bool _initialized = false;

  /// Initializes the centralized issue detector.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
  }

  /// Records an issue directly into the hub with automatic deduplication.
  static AppIssue recordIssue({
    required IssueSeverity severity,
    required IssueCategory category,
    required String title,
    String details = '',
    Map<String, dynamic>? metadata,
  }) {
    final sig = AppIssue._generateSignature(category, title);
    final now = DateTime.now();

    final existing = _activeIssues[sig];
    if (existing != null && !existing.isResolved) {
      existing.occurrenceCount++;
      existing.lastSeen = now;
      if (details.isNotEmpty && details != existing.details) {
        // Keep latest details if changed
      }
      return existing;
    }

    final issue = AppIssue(
      id: sig,
      severity: severity,
      category: category,
      title: title,
      details: details,
      timestamp: now,
      lastSeen: now,
      metadata: metadata,
      seenByAgent: false,
      isResolved: false,
    );

    _activeIssues[sig] = issue;
    _issueHistory.add(issue);
    return issue;
  }

  /// Sniffs a raw console log line (from print/debugPrint/logger) for known defect signatures.
  /// Extremely fast substring matching (<0.01ms) executed before running any heavy logic.
  static void sniffLog(String message, {String level = 'info'}) {
    if (message.isEmpty) return;

    // 1. Supabase / PostgREST Row Level Security (RLS) Violation
    if (message.contains('violates row-level security policy') ||
        message.contains('PGRST301') ||
        message.contains('PGRST116') ||
        (message.contains('PostgrestException') && message.contains('permission denied'))) {
      recordIssue(
        severity: IssueSeverity.critical,
        category: IssueCategory.dataSync,
        title: 'Supabase RLS Policy Violation (Permission Denied)',
        details: message,
        metadata: {'origin': 'supabase_postgrest', 'level': level},
      );
      return;
    }

    // 2. Firebase Security Rules / Permission Denied
    if (message.contains('cloud_firestore/permission-denied') ||
        message.contains('PERMISSION_DENIED') ||
        (message.contains('FirebaseException') && message.contains('permission-denied'))) {
      recordIssue(
        severity: IssueSeverity.critical,
        category: IssueCategory.dataSync,
        title: 'Firebase Permission Denied (Security Rule Violation)',
        details: message,
        metadata: {'origin': 'firebase', 'level': level},
      );
      return;
    }

    // 3. RenderFlex Layout Overflow (Stripes)
    if (message.contains('A RenderFlex overflowed by') || message.contains('OVERFLOWING')) {
      final match = RegExp(r'overflowed by ([0-9.]+) pixels').firstMatch(message);
      final px = match != null ? '${match.group(1)}px' : 'pixels';
      recordIssue(
        severity: IssueSeverity.critical,
        category: IssueCategory.uiLayout,
        title: 'RenderFlex Overflow ($px on screen)',
        details: message,
        metadata: {'origin': 'renderflex', 'overflow': px},
      );
      return;
    }

    // 4. HTTP / Network failures (Dio, http, SocketException)
    if (message.contains('DioException') ||
        message.contains('SocketException') ||
        message.contains('HttpException') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection refused') ||
        message.contains('Network is unreachable') ||
        message.contains('ClientException with SocketException')) {
      final isOffline = message.contains('SocketException') ||
          message.contains('Failed host lookup') ||
          message.contains('Network is unreachable') ||
          message.contains('Connection refused');

      recordIssue(
        severity: isOffline ? IssueSeverity.critical : IssueSeverity.warning,
        category: IssueCategory.dataSync,
        title: isOffline
            ? 'Network Unreachable / Offline Connection Failure'
            : 'HTTP Network Client Error',
        details: message,
        metadata: {'origin': 'network_client', 'isOffline': isOffline},
      );
      return;
    }

    // 5. Database & Offline Sync Conflicts
    if (message.contains('SqliteException') ||
        message.contains('DatabaseException') ||
        message.contains('SyncConflict') ||
        message.contains('offline sync failed') ||
        message.contains('database is locked')) {
      recordIssue(
        severity: IssueSeverity.critical,
        category: IssueCategory.dataSync,
        title: 'Database / Offline Sync Storage Error',
        details: message,
        metadata: {'origin': 'database_sync'},
      );
      return;
    }

    // 6. Flutter Lifecycle & Leak Warnings
    if (message.contains('setState() called after dispose()')) {
      recordIssue(
        severity: IssueSeverity.warning,
        category: IssueCategory.runtime,
        title: 'setState() called after dispose() (Resource Leak)',
        details: message,
        metadata: {'origin': 'lifecycle'},
      );
      return;
    }

    if (message.contains('Cannot add new events after calling close')) {
      recordIssue(
        severity: IssueSeverity.warning,
        category: IssueCategory.dataSync,
        title: 'StreamController closed before asynchronous operation completed',
        details: message,
        metadata: {'origin': 'stream_lifecycle'},
      );
      return;
    }
  }

  /// Sniffs an uncaught Flutter framework error.
  static void sniffError(FlutterErrorDetails details) {
    final expStr = details.exceptionAsString();
    final lib = details.library ?? '';

    if (expStr.contains('A RenderFlex overflowed by') || expStr.contains('OVERFLOWING')) {
      final match = RegExp(r'overflowed by ([0-9.]+) pixels').firstMatch(expStr);
      final px = match != null ? '${match.group(1)}px' : 'pixels';
      recordIssue(
        severity: IssueSeverity.critical,
        category: IssueCategory.uiLayout,
        title: 'RenderFlex Layout Overflow ($px)',
        details: expStr,
        metadata: {'context': details.context?.toString()},
      );
      return;
    }

    // Network / Socket error routed through framework
    if (expStr.contains('SocketException') || expStr.contains('HttpException')) {
      recordIssue(
        severity: IssueSeverity.critical,
        category: IssueCategory.dataSync,
        title: 'Uncaught Network Error: $expStr',
        details: expStr,
      );
      return;
    }

    // Generic uncaught runtime exception
    recordIssue(
      severity: IssueSeverity.critical,
      category: IssueCategory.runtime,
      title: 'Uncaught Exception ($lib): ${expStr.split('\n').first}',
      details: expStr,
      metadata: {'library': lib, 'context': details.context?.toString()},
    );
  }

  /// Audits frame timings and updates performance issue state.
  static void auditPerformance() {
    try {
      final profile = FrameBudgetProfiler.getProfile();
      final sampleCount = (profile['sampleCount'] as num?)?.toInt() ?? 0;
      if (sampleCount < 10) return; // Prevent false alarms during initial startup / warmup frames

      final jankPct = (profile['jankPercentage'] as num?)?.toDouble() ?? 0.0;
      final avgMs = (profile['avgFrameDurationMs'] as num?)?.toDouble() ?? 0.0;
      final diagnosis = profile['diagnosis']?.toString() ?? '';

      final sig = AppIssue._generateSignature(
          IssueCategory.performance, 'Animation Jank Dropping Frames');

      if (jankPct >= 50.0 || (avgMs >= 32.0 && jankPct >= 25.0)) {
        // Severe jank
        recordIssue(
          severity: IssueSeverity.critical,
          category: IssueCategory.performance,
          title:
              'Severe Animation Jank (${jankPct.toStringAsFixed(1)}% dropped, avg ${avgMs.toStringAsFixed(1)}ms)',
          details: diagnosis,
          metadata: profile,
        );
      } else if (jankPct >= 20.0 || (avgMs >= 20.0 && jankPct >= 15.0)) {
        // Moderate jank
        recordIssue(
          severity: IssueSeverity.warning,
          category: IssueCategory.performance,
          title:
              'Moderate Animation Jank (${jankPct.toStringAsFixed(1)}% dropped, avg ${avgMs.toStringAsFixed(1)}ms)',
          details: diagnosis,
          metadata: profile,
        );
      } else if (jankPct < 10.0 && _activeIssues.containsKey(sig)) {
        // Smooth performance: mark previous jank issue resolved
        _activeIssues[sig]?.isResolved = true;
      }
    } catch (_) {}
  }

  /// Audits active UI tree for overflows and touch target compliance.
  static void auditUiTree() {
    try {
      final res = UiHealthAuditor.audit();
      final overflows = res['overflows'] as List?;
      if (overflows != null && overflows.isNotEmpty) {
        for (final o in overflows) {
          final type = o['type'] ?? 'Widget';
          recordIssue(
            severity: IssueSeverity.critical,
            category: IssueCategory.uiLayout,
            title: 'RenderFlex Overflow on $type',
            details: o['details']?.toString() ?? '',
            metadata: Map<String, dynamic>.from(o as Map),
          );
        }
      }

      final access = res['accessibilityIssues'] as List?;
      if (access != null && access.isNotEmpty) {
        for (final a in access) {
          final target = a['target'] ?? 'Button';
          recordIssue(
            severity: IssueSeverity.warning,
            category: IssueCategory.uiLayout,
            title: 'Touch target too small on $target (<48dp)',
            details: a['issue']?.toString() ?? '',
            metadata: Map<String, dynamic>.from(a as Map),
          );
        }
      }

      final design = res['designIssues'] as List?;
      if (design != null && design.isNotEmpty) {
        for (final d in design) {
          final target = d['target'] ?? 'Element';
          final type = d['type'] ?? 'Widget';
          final cat = d['category'] ?? 'design';
          final msg = d['message'] ?? '';
          final rec = d['recommendation'] ?? '';
          recordIssue(
            severity: IssueSeverity.warning,
            category: IssueCategory.uiLayout,
            title: 'Design/Layout [$cat]: $type $target',
            details: '$msg\nRecommendation: $rec',
            metadata: Map<String, dynamic>.from(d as Map),
          );
        }
      }
    } catch (_) {}
  }

  /// Returns a concise, token-efficient single-line or small bullet summary
  /// for injection into post-action state. Returns null if completely clean (0 tokens!).
  static String? getActionAlertSummary({bool markSeen = true}) {
    auditPerformance();

    final activeList = _activeIssues.values
        .where((i) => !i.isResolved && (!i.seenByAgent || i.severity == IssueSeverity.critical))
        .toList();

    if (activeList.isEmpty) return null;

    // Sort critical first, then warning
    activeList.sort((a, b) => b.severity.index.compareTo(a.severity.index));

    final buffer = StringBuffer();
    for (final issue in activeList.take(3)) {
      final icon = issue.severity == IssueSeverity.critical ? '🚨 CRITICAL' : '⚠️ WARNING';
      final cat = issue.category.name;
      final count = issue.occurrenceCount > 1 ? ' (x${issue.occurrenceCount})' : '';
      buffer.writeln('$icon [$cat]: ${issue.title}$count');
      if (markSeen) issue.seenByAgent = true;
    }

    if (activeList.length > 3) {
      buffer.writeln('  ... and ${activeList.length - 3} more issues (call get_app_issues to inspect)');
    }

    return buffer.toString().trim();
  }

  /// Returns a consolidated health summary payload suitable for snapshots and diagnostics.
  static Map<String, dynamic> getSummaryJson({
    IssueSeverity minSeverity = IssueSeverity.warning,
    bool unseenOnly = false,
  }) {
    auditPerformance();

    final all = _activeIssues.values.where((i) => !i.isResolved).toList();
    final filtered = all.where((i) {
      if (i.severity < minSeverity) return false;
      if (unseenOnly && i.seenByAgent) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.severity.index.compareTo(a.severity.index));

    final criticalCount = all.where((i) => i.severity == IssueSeverity.critical).length;
    final warningCount = all.where((i) => i.severity == IssueSeverity.warning).length;
    final infoCount = all.where((i) => i.severity == IssueSeverity.info).length;

    return {
      'isHealthy': criticalCount == 0 && warningCount == 0,
      'criticalCount': criticalCount,
      'warningCount': warningCount,
      'infoCount': infoCount,
      'totalActive': all.length,
      'issues': filtered.map((e) => e.toJson()).toList(),
    };
  }

  /// Clears active issues or marks them resolved.
  static void clear() {
    _activeIssues.clear();
    _issueHistory.clear();
  }
}
