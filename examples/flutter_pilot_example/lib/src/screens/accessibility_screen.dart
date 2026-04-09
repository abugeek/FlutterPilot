import 'package:flutter/material.dart';

/// Demonstrates accessibility and widget-assertion tools:
///
/// | Tool                    | Demonstrated By                          |
/// |-------------------------|------------------------------------------|
/// | get_semantics_tree      | hint + annotated widget tree             |
/// | set_text_scale_factor   | live text scale slider                   |
/// | assert_widget_enabled   | enabled button assertion hint            |
/// | assert_widget_disabled  | disabled button assertion hint           |
class AccessibilityScreen extends StatefulWidget {
  const AccessibilityScreen({super.key});

  @override
  State<AccessibilityScreen> createState() => _AccessibilityScreenState();
}

class _AccessibilityScreenState extends State<AccessibilityScreen> {
  double _textScale = 1.0;
  bool _formEnabled = true;
  bool _showSemanticLabels = false;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_textScale)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Accessibility')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _aiHint(
                'AI Agent tools on this screen:\n'
                '  get_semantics_tree            // accessibility layer\n'
                '  set_text_scale_factor(1.5)    // simulate large text\n'
                '  assert_widget_enabled("submit_button")\n'
                '  assert_widget_disabled("locked_button")',
              ),
              const SizedBox(height: 16),

              // -- Text Scale -----------------------------------------------
              _sectionHeader('Text Scale Factor', 'set_text_scale_factor'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current scale: ${_textScale.toStringAsFixed(1)}x',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Slider(
                        key: const Key('text_scale_slider'),
                        value: _textScale,
                        min: 0.7,
                        max: 3.0,
                        divisions: 23,
                        label: '${_textScale.toStringAsFixed(1)}x',
                        onChanged: (v) => setState(() => _textScale = v),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This paragraph scales with the slider above. '
                        'AI can call set_text_scale_factor(2.0) to simulate '
                        'users who prefer larger system fonts.',
                        style: TextStyle(fontSize: 14 * _textScale.clamp(0.8, 1.5)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _scalePreset('Small\n0.8x', 0.8),
                          _scalePreset('Normal\n1.0x', 1.0),
                          _scalePreset('Large\n1.5x', 1.5),
                          _scalePreset('XL\n2.0x', 2.0),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // -- Semantics ------------------------------------------------
              _sectionHeader('Semantics Tree', 'get_semantics_tree'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'get_semantics_tree returns the accessibility tree — what\n'
                        'screen readers like TalkBack and VoiceOver see.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        key: const Key('show_semantic_labels_switch'),
                        title: const Text('Show Semantic Labels'),
                        subtitle: const Text(
                            'Overlay semantic descriptions on widgets'),
                        value: _showSemanticLabels,
                        onChanged: (v) =>
                            setState(() => _showSemanticLabels = v),
                      ),
                      if (_showSemanticLabels) ...[
                        const Divider(),
                        const Text(
                          'Example widget tree with semantics:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        _SemanticsWidget(
                          semanticsLabel: 'Submit button, double-press to confirm',
                          role: 'Button',
                          child: ElevatedButton(
                            key: const Key('semantics_submit_button'),
                            onPressed: () {},
                            child: const Text('Submit'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _SemanticsWidget(
                          semanticsLabel: 'User avatar image, John Doe',
                          role: 'Image',
                          child: Semantics(
                            label: 'User avatar image, John Doe',
                            child: CircleAvatar(
                              key: const Key('user_avatar'),
                              backgroundColor: Colors.indigo,
                              child: const Text('JD'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _SemanticsWidget(
                          semanticsLabel: 'Email field, required',
                          role: 'TextField',
                          child: Semantics(
                            label: 'Email field, required',
                            child: const TextField(
                              key: Key('accessible_email_field'),
                              decoration: InputDecoration(
                                labelText: 'Email',
                                hintText: 'user@example.com',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _codeBox(
                        'get_semantics_tree          // full accessibility tree\n'
                        'get_semantics_tree(maxDepth: 5)  // limited depth',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // -- Widget Assertions ----------------------------------------
              _sectionHeader(
                  'Widget Assertions',
                  'assert_widget_enabled · assert_widget_disabled'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI agents can assert a widget is enabled or disabled\n'
                        'to verify UI state without reading full widget tree.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        key: const Key('form_enabled_switch'),
                        title: const Text('Form enabled'),
                        value: _formEnabled,
                        onChanged: (v) => setState(() => _formEnabled = v),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton(
                            key: const Key('submit_button'),
                            onPressed: _formEnabled ? () {} : null,
                            child: const Text('Submit (key: submit_button)'),
                          ),
                          ElevatedButton(
                            key: const Key('locked_button'),
                            onPressed: !_formEnabled ? () {} : null,
                            child: const Text('Locked (key: locked_button)'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _codeBox(
                        '// When form enabled:\n'
                        'assert_widget_enabled("submit_button")  // passes\n'
                        'assert_widget_disabled("locked_button") // passes\n\n'
                        '// When form disabled:\n'
                        'assert_widget_disabled("submit_button") // passes\n'
                        'assert_widget_enabled("locked_button")  // passes',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // -- Accessibility Tips ---------------------------------------
              _sectionHeader('Accessibility Best Practices', 'audit tips'),
              Card(
                color: Colors.teal.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI-driven accessibility audit checklist:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _codeBox(
                        '1. get_semantics_tree       // check all nodes have labels\n'
                        '2. set_text_scale_factor(2.0)  // test large text overflow\n'
                        '3. capture_screenshot          // verify layout at 2x\n'
                        '4. set_text_scale_factor(1.0)  // restore\n'
                        '5. assert_widget_enabled("submit_btn")  // check state\n'
                        '6. get_widget_properties("submit_btn")  // read details',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scalePreset(String label, double scale) => ElevatedButton(
        key: Key('scale_${scale.toString().replaceAll(".", "_")}_button'),
        onPressed: () => setState(() => _textScale = scale),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              _textScale == scale ? Colors.indigo : Colors.grey.shade100,
          foregroundColor:
              _textScale == scale ? Colors.white : Colors.black87,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
      );

  Widget _sectionHeader(String title, String tools) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(tools,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace')),
          ],
        ),
      );

  Widget _aiHint(String text) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.smart_toy, color: Colors.blue, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blue,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      );

  Widget _codeBox(String code) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(code,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      );
}

// ---------------------------------------------------------------------------
// Helper widget that shows a semantic label badge on top of a widget
// ---------------------------------------------------------------------------
class _SemanticsWidget extends StatelessWidget {
  final String semanticsLabel;
  final String role;
  final Widget child;

  const _SemanticsWidget({
    required this.semanticsLabel,
    required this.role,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.teal.shade200),
        borderRadius: BorderRadius.circular(6),
        color: Colors.teal.shade50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(role,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  semanticsLabel,
                  style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
