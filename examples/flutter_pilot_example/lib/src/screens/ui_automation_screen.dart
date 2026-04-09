import 'package:flutter/material.dart';

/// Demonstrates almost every UI-automation tool available in FlutterPilot:
///
/// | Tool                    | Widget demonstrated               |
/// |-------------------------|-----------------------------------|
/// | tap_widget              | all buttons                       |
/// | double_tap_widget       | Double-Tap Me card                |
/// | long_press_widget       | Long-Press Me card                |
/// | enter_text              | text fields                       |
/// | clear_text_field        | any text field                    |
/// | set_slider_value        | brightness / volume sliders       |
/// | toggle_checkbox         | checkboxes + switches             |
/// | scroll_by               | long item list                    |
/// | scroll_into_view        | "Find Me" tile at bottom          |
/// | focus_widget            | any text field                    |
/// | unfocus_all             | dismiss keyboard button           |
/// | set_text_scale_factor   | scale slider (on Accessibility)   |
/// | pump_frames             | animations                        |
/// | tap_at                  | coordinates shown in hint         |
class UiAutomationScreen extends StatefulWidget {
  const UiAutomationScreen({super.key});

  @override
  State<UiAutomationScreen> createState() => _UiAutomationScreenState();
}

class _UiAutomationScreenState extends State<UiAutomationScreen> {
  double _brightness = 0.5;
  double _volume = 0.3;
  bool _notificationsEnabled = true;
  bool _darkMode = false;
  bool _autoSave = true;
  final _textController = TextEditingController();
  final _searchController = TextEditingController();
  final List<String> _log = [];

  void _addLog(String msg) => setState(() => _log.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)}  $msg'));

  @override
  void dispose() {
    _textController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UI Automation Tools')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _aiHint(
              'AI Agent: This screen demos tap_widget, enter_text, set_slider_value, toggle_checkbox, scroll_by, scroll_into_view, double_tap_widget, long_press_widget, and more.',
            ),
            const SizedBox(height: 16),

            // ── Text Fields ──────────────────────────────────────────────────
            _sectionHeader('Text Fields', 'enter_text · clear_text_field · focus_widget · unfocus_all'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      key: const Key('main_text_field'),
                      controller: _textController,
                      decoration: const InputDecoration(
                        labelText: 'Main input (key: main_text_field)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('search_field'),
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search (key: search_field)',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _textController.text.isEmpty
                                ? 'No text entered yet'
                                : 'Value: "${_textController.text}"',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ),
                        TextButton.icon(
                          key: const Key('clear_main_text_button'),
                          onPressed: () {
                            _textController.clear();
                            setState(() {});
                            _addLog('Text cleared');
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                        ),
                        TextButton.icon(
                          key: const Key('unfocus_button'),
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            _addLog('Keyboard dismissed');
                          },
                          icon: const Icon(Icons.keyboard_hide),
                          label: const Text('Unfocus All'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Sliders ──────────────────────────────────────────────────────
            _sectionHeader('Sliders', 'set_slider_value'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _SliderRow(
                      label: 'Brightness',
                      icon: Icons.brightness_6,
                      value: _brightness,
                      sliderKey: 'brightness_slider',
                      onChanged: (v) {
                        setState(() => _brightness = v);
                        _addLog('Brightness → ${(v * 100).round()}%');
                      },
                    ),
                    const SizedBox(height: 8),
                    _SliderRow(
                      label: 'Volume',
                      icon: Icons.volume_up,
                      value: _volume,
                      sliderKey: 'volume_slider',
                      onChanged: (v) {
                        setState(() => _volume = v);
                        _addLog('Volume → ${(v * 100).round()}%');
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Toggles / Checkboxes ─────────────────────────────────────────
            _sectionHeader('Checkboxes & Switches', 'toggle_checkbox'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('notifications_switch'),
                    title: const Text('Notifications (key: notifications_switch)'),
                    value: _notificationsEnabled,
                    onChanged: (v) {
                      setState(() => _notificationsEnabled = v);
                      _addLog('Notifications: $v');
                    },
                  ),
                  SwitchListTile(
                    key: const Key('dark_mode_switch'),
                    title: const Text('Dark Mode (key: dark_mode_switch)'),
                    value: _darkMode,
                    onChanged: (v) {
                      setState(() => _darkMode = v);
                      _addLog('Dark mode: $v');
                    },
                  ),
                  CheckboxListTile(
                    key: const Key('auto_save_checkbox'),
                    title: const Text('Auto-Save (key: auto_save_checkbox)'),
                    value: _autoSave,
                    onChanged: (v) {
                      setState(() => _autoSave = v ?? false);
                      _addLog('Auto-save: $v');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Tap Variants ─────────────────────────────────────────────────
            _sectionHeader('Tap Variants', 'tap_widget · double_tap_widget · long_press_widget'),
            Row(
              children: [
                Expanded(
                  child: _TapCard(
                    cardKey: 'tap_card',
                    buttonKey: 'tap_button',
                    icon: Icons.touch_app,
                    label: 'Tap Me',
                    color: Colors.indigo,
                    gesture: 'Single Tap',
                    onActivate: () => _addLog('Single tap triggered'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TapCard(
                    cardKey: 'double_tap_card',
                    buttonKey: 'double_tap_button',
                    icon: Icons.double_arrow,
                    label: 'Double Tap',
                    color: Colors.teal,
                    gesture: 'Double Tap',
                    onActivate: () => _addLog('Double tap triggered'),
                    isDoubleTap: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TapCard(
                    cardKey: 'long_press_card',
                    buttonKey: 'long_press_button',
                    icon: Icons.touch_app_outlined,
                    label: 'Long Press',
                    color: Colors.orange,
                    gesture: 'Long Press',
                    onActivate: () => _addLog('Long press triggered'),
                    isLongPress: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Action Log ───────────────────────────────────────────────────
            _sectionHeader('Action Log', 'watch automated actions here'),
            Container(
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade50,
              ),
              child: _log.isEmpty
                  ? const Center(
                      child: Text(
                        'No actions yet — interact with widgets above.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('action_log_list'),
                      padding: const EdgeInsets.all(8),
                      itemCount: _log.length,
                      itemBuilder: (_, i) => Text(
                        _log[i],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
            ),
            const SizedBox(height: 16),

            // ── Scrollable List ──────────────────────────────────────────────
            _sectionHeader('Scrollable List', 'scroll_by · scroll_into_view'),
            _aiHint(
              'AI: Use scroll_by(0, 300) to scroll this list down, or scroll_into_view("find_me_tile") to jump to the last item.',
            ),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                key: const Key('scrollable_list'),
                itemCount: 25,
                itemBuilder: (_, i) {
                  if (i == 24) {
                    return ListTile(
                      key: const Key('find_me_tile'),
                      leading: const Icon(Icons.flag, color: Colors.green),
                      title: const Text('🎯 Find Me! (key: find_me_tile)'),
                      subtitle: const Text('scroll_into_view("find_me_tile") should jump here'),
                      tileColor: Colors.green.shade50,
                    );
                  }
                  return ListTile(
                    key: Key('list_item_$i'),
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text('Item ${i + 1}'),
                    subtitle: const Text('Scroll past me'),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── Tip ─────────────────────────────────────────────────────────
            _sectionHeader('tap_at by Coordinates', 'tap_at'),
            Card(
              color: Colors.amber.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'tap_at sends a tap to raw screen coordinates.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'First use capture_screenshot to see the screen, then get_widget_properties to find widget bounds, then call tap_at(x, y) to tap a specific pixel.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 80), // bottom padding
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, String tools) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              tools,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontFamily: 'monospace'),
            ),
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
          children: [
            const Icon(Icons.smart_toy, color: Colors.blue, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.blue)),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SliderRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final String sliderKey;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.sliderKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            '$label\n${(value * 100).round()}%',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            key: Key(sliderKey),
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _TapCard extends StatefulWidget {
  final String cardKey;
  final String buttonKey;
  final IconData icon;
  final String label;
  final Color color;
  final String gesture;
  final VoidCallback onActivate;
  final bool isDoubleTap;
  final bool isLongPress;

  const _TapCard({
    required this.cardKey,
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.color,
    required this.gesture,
    required this.onActivate,
    this.isDoubleTap = false,
    this.isLongPress = false,
  });

  @override
  State<_TapCard> createState() => _TapCardState();
}

class _TapCardState extends State<_TapCard> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    final detector = GestureDetector(
      onTap: widget.isDoubleTap || widget.isLongPress ? null : () {
        setState(() => _count++);
        widget.onActivate();
      },
      onDoubleTap: widget.isDoubleTap ? () {
        setState(() => _count++);
        widget.onActivate();
      } : null,
      onLongPress: widget.isLongPress ? () {
        setState(() => _count++);
        widget.onActivate();
      } : null,
      child: Container(
        key: Key(widget.buttonKey),
        height: 90,
        decoration: BoxDecoration(
          color: widget.color.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.color.withAlpha(100)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: widget.color),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.color,
              ),
            ),
            if (_count > 0)
              Text(
                '×$_count',
                style: TextStyle(fontSize: 11, color: widget.color.withAlpha(200)),
              ),
          ],
        ),
      ),
    );

    return Card(key: Key(widget.cardKey), child: Padding(padding: const EdgeInsets.all(4), child: detector));
  }
}
