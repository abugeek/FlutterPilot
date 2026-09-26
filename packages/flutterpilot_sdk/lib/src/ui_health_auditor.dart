import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Scans the active Flutter widget and render tree for layout overflow errors,
/// accessibility touch-target violations, micro-typography, component role mismatches,
/// and asymmetric layout dead-space defects.
class UiHealthAuditor {
  static const double minTouchTargetSize = 48.0;
  static const double minLegibleFontSize = 11.0;

  /// Performs a comprehensive health and visual design audit on the current screen.
  static Map<String, dynamic> audit() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return {
        'isHealthy': false,
        'designScore': 0,
        'designGrade': 'F',
        'error': 'No root element found.',
        'overflows': [],
        'accessibilityIssues': [],
        'designIssues': [],
      };
    }

    final List<Map<String, dynamic>> overflows = [];
    final List<Map<String, dynamic>> accessibilityIssues = [];
    final List<Map<String, dynamic>> designIssues = [];

    void checkElement(Element element) {
      final ro = element.renderObject;
      final widget = element.widget;
      final typeName = widget.runtimeType.toString();

      // 1. Check for layout overflow issues
      if (ro is RenderBox && ro.hasSize && ro.attached) {
        final boxSize = ro.size;
        final globalOffset = ro.localToGlobal(Offset.zero);

        if (ro is RenderFlex) {
          final diag = ro.toString();
          if (diag.contains('overflowed by') || diag.contains('OVERFLOWING')) {
            overflows.add({
              'type': typeName,
              'details': diag,
              'location': _extractLocation(widget),
            });
          }
        }

        // 2. Check for small touch targets on clickables (<48x48 dp)
        if (_isClickableWidget(widget, typeName)) {
          if (boxSize.width > 0 &&
              boxSize.height > 0 &&
              (boxSize.width < minTouchTargetSize ||
                  boxSize.height < minTouchTargetSize)) {
            final keyStr = widget.key?.toString() ?? typeName;
            accessibilityIssues.add({
              'target': keyStr,
              'type': typeName,
              'width': boxSize.width,
              'height': boxSize.height,
              'issue':
                  'Touch target size (${boxSize.width.toStringAsFixed(1)}x${boxSize.height.toStringAsFixed(1)}) is smaller than recommended minimum (${minTouchTargetSize}x$minTouchTargetSize dp).',
            });
          }
        }

        // 3. Component Role Mismatch: Buttons containing multi-line card content
        if (_isActionButton(widget, typeName)) {
          bool hasMultiLineColumn = false;
          void searchDescendants(Element el) {
            if (el.widget is Column) {
              int textCount = 0;
              void countTexts(Element c) {
                if (c.widget is Text || c.widget is RichText) textCount++;
                c.visitChildren(countTexts);
              }

              el.visitChildren(countTexts);
              if (textCount >= 2) {
                hasMultiLineColumn = true;
                return;
              }
            }
            if (!hasMultiLineColumn) {
              el.visitChildren(searchDescendants);
            }
          }

          element.visitChildren(searchDescendants);

          if (hasMultiLineColumn) {
            designIssues.add({
              'category': 'component_role_mismatch',
              'severity': 'warning',
              'target': widget.key?.toString() ?? typeName,
              'type': typeName,
              'message':
                  'Action button contains multi-line card content (Column with multiple Text widgets). Material Design guidelines recommend using Card or ListTile with InkWell for multi-line informational cards.',
              'recommendation':
                  'Refactor into a Material Card or ListTile with InkWell to provide proper visual hierarchy, padding, and screen-reader semantics.',
            });
          }
        }

        // 4. Wrap layout heuristics: Asymmetric margins / uncentered dead space / rigid widths
        if (widget is Wrap && boxSize.width > 100) {
          final childBoxes = <RenderBox>[];
          element.visitChildren((childEl) {
            final childRo = childEl.renderObject;
            if (childRo is RenderBox && childRo.hasSize && childRo.attached) {
              childBoxes.add(childRo);
            }
          });

          if (childBoxes.length >= 2) {
            final rows = <List<RenderBox>>[];
            for (final cb in childBoxes) {
              final cbOffset = cb.localToGlobal(Offset.zero);
              var placed = false;
              for (final row in rows) {
                final rowY = row.first.localToGlobal(Offset.zero).dy;
                if ((cbOffset.dy - rowY).abs() < 12.0) {
                  row.add(cb);
                  placed = true;
                  break;
                }
              }
              if (!placed) rows.add([cb]);
            }

            for (final row in rows) {
              if (row.length >= 2) {
                double minLeft = double.infinity;
                double maxRight = -double.infinity;
                for (final cb in row) {
                  final off = cb.localToGlobal(Offset.zero);
                  if (off.dx < minLeft) minLeft = off.dx;
                  if (off.dx + cb.size.width > maxRight) {
                    maxRight = off.dx + cb.size.width;
                  }
                }

                final leftGap = minLeft - globalOffset.dx;
                final rightGap = (globalOffset.dx + boxSize.width) - maxRight;

                if (rightGap > 35.0 && leftGap < 25.0) {
                  designIssues.add({
                    'category': 'asymmetric_spacing',
                    'severity': 'warning',
                    'target': widget.key?.toString() ?? 'Wrap',
                    'type': 'Wrap',
                    'message':
                        'Asymmetric horizontal spacing: Left margin is ${leftGap.toStringAsFixed(0)}dp, but right side has a ${rightGap.toStringAsFixed(0)}dp dead space gap. Children do not span or center symmetrically across the container.',
                    'recommendation':
                        'Replace uncentered Wrap with a responsive GridView (crossAxisCount) or LayoutBuilder with flexible cards so widths adapt symmetrically.',
                  });
                  break;
                }
              }
            }

            int fixedWidthCount = 0;
            element.visitChildren((childEl) {
              final cw = childEl.widget;
              if (cw is SizedBox && cw.width != null && cw.width! > 0) {
                fixedWidthCount++;
              }
            });
            if (fixedWidthCount >= 2) {
              designIssues.add({
                'category': 'rigid_child_sizing',
                'severity': 'warning',
                'target': widget.key?.toString() ?? 'Wrap',
                'type': 'Wrap',
                'message':
                    '$fixedWidthCount children have hardcoded fixed widths inside a Wrap. Fixed widths cause awkward gaps or premature wrapping across varying screen sizes.',
                'recommendation':
                    'Use responsive grid columns (e.g. GridView with crossAxisSpacing or LayoutBuilder) instead of fixed SizedBox(width).',
              });
            }
          }
        }
      }

      // 5. Micro-typography check (<11sp)
      if (widget is Text && (widget.data?.isNotEmpty ?? false)) {
        final style = widget.style;
        if (style != null &&
            style.fontSize != null &&
            style.fontSize! < minLegibleFontSize) {
          designIssues.add({
            'category': 'typography_legibility',
            'severity': 'warning',
            'target': '"${widget.data}"',
            'type': 'Text',
            'message':
                'Font size (${style.fontSize}sp) is below the recommended minimum legible threshold (${minLegibleFontSize}sp).',
            'recommendation':
                'Increase font size to at least 11-12sp or use Theme.of(context).textTheme.bodySmall for mobile legibility.',
          });
        }
      }

      element.visitChildren(checkElement);
    }

    checkElement(root);

    // Calculate Design Score (0 - 100)
    int score = 100;
    score -= (overflows.length * 30);
    score -= (accessibilityIssues.length * 10);
    score -= (designIssues
            .where((d) => d['category'] == 'asymmetric_spacing')
            .length *
        15);
    score -= (designIssues
            .where((d) => d['category'] == 'component_role_mismatch')
            .length *
        10);
    score -= (designIssues
            .where((d) => d['category'] == 'rigid_child_sizing')
            .length *
        10);
    score -= (designIssues
            .where((d) => d['category'] == 'typography_legibility')
            .length *
        5);
    score = score.clamp(0, 100);

    final isHealthy =
        overflows.isEmpty && accessibilityIssues.isEmpty && designIssues.isEmpty;

    return {
      'isHealthy': isHealthy,
      'designScore': score,
      'designGrade': _scoreToGrade(score),
      'overflowCount': overflows.length,
      'accessibilityIssueCount': accessibilityIssues.length,
      'designIssueCount': designIssues.length,
      'overflows': overflows,
      'accessibilityIssues': accessibilityIssues,
      'designIssues': designIssues,
    };
  }

  static String _scoreToGrade(int score) {
    if (score == 100) return 'A+ (Pristine)';
    if (score >= 90) return 'A (Clean & Balanced)';
    if (score >= 80) return 'B (Good, minor polish needed)';
    if (score >= 70) return 'C (Suboptimal layout & UX)';
    return 'F (Severe layout or design defects)';
  }

  static bool _isClickableWidget(Widget widget, String typeName) {
    return widget is IconButton ||
        widget is ElevatedButton ||
        widget is TextButton ||
        widget is OutlinedButton ||
        widget is FloatingActionButton ||
        widget is InkWell ||
        widget is GestureDetector ||
        typeName.contains('Button');
  }

  static bool _isActionButton(Widget widget, String typeName) {
    return widget is ElevatedButton ||
        widget is OutlinedButton ||
        widget is TextButton ||
        typeName == 'FilledButton' ||
        typeName == 'FilledButtonTone';
  }

  static Map<String, dynamic>? _extractLocation(Widget widget) {
    try {
      final dynamic loc = (widget as dynamic)._location;
      if (loc != null) {
        return {
          'file': loc.file?.toString(),
          'line': loc.line,
          'column': loc.column,
        };
      }
    } catch (_) {}
    return null;
  }
}
