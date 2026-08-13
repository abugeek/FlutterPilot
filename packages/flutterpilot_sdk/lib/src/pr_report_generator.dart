import 'ui_health_auditor.dart';

/// Auto-generates structured GitHub Pull Request descriptions and verification reports.
class PrReportGenerator {
  /// Compiles a comprehensive PR markdown report.
  static String generate({
    required String title,
    String? description,
    Map<String, dynamic>? auditData,
    String? gifPath,
    String? generatedTestPath,
  }) {
    final audit = auditData ?? UiHealthAuditor.audit();
    final isHealthy = audit['isHealthy'] == true;
    final overflowCount = audit['overflowCount'] ?? 0;
    final a11yCount = audit['accessibilityIssueCount'] ?? 0;

    final buffer = StringBuffer();
    buffer.writeln('# 🚀 $title\n');

    if (description != null && description.isNotEmpty) {
      buffer.writeln('## 📝 Description');
      buffer.writeln('$description\n');
    }

    buffer.writeln('## 🏥 Autonomous Quality & Screen Health Audit');
    buffer.writeln('| Check | Status | Details |');
    buffer.writeln('|---|---|---|');
    buffer.writeln(
      '| **Layout Overflows** | ${overflowCount == 0 ? "✅ Passed" : "❌ Failed"} | $overflowCount RenderFlex errors |',
    );
    buffer.writeln(
      '| **Touch Target Accessibility** | ${a11yCount == 0 ? "✅ Passed" : "⚠️ Warnings"} | $a11yCount touch targets <48x48 dp |',
    );
    buffer.writeln(
      '| **Overall Health** | ${isHealthy ? "🟢 Clean & Production Ready" : "🟡 Needs Review"} | Verified via FlutterPilot SDK |',
    );
    buffer.writeln();

    if (gifPath != null && gifPath.isNotEmpty) {
      buffer.writeln('## 🎬 Visual Proof & Session Replay');
      buffer.writeln('![Session Replay]($gifPath)\n');
    }

    if (generatedTestPath != null && generatedTestPath.isNotEmpty) {
      buffer.writeln('## 🧪 Synthesized Automated Test');
      buffer.writeln('Generated test suite available at: `$generatedTestPath`\n');
    }

    buffer.writeln('---');
    buffer.writeln('*Automated verification generated with [FlutterPilot](https://github.com/abugeek/FlutterPilot) 🚀*');

    return buffer.toString();
  }
}
