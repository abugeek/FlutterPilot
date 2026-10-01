import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  // get_semantics_tree was ~10 KB for one screen, most of it `false` flags
  // and `null` texts (field test #292).
  testWidgets('a semantics node lists only what is set', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('Send')),
              const ElevatedButton(onPressed: null, child: Text('Off')),
              Checkbox(value: false, onChanged: (_) {}),
              const Text('Plain'),
            ],
          ),
        ),
      ),
    );
    final root = tester
        .binding
        .renderViews
        .first
        .owner!
        .semanticsOwner!
        .rootSemanticsNode!;
    final nodes = <Map<String, dynamic>>[];
    void flatten(Map<String, dynamic> node) {
      nodes.add(node);
      for (final child in (node['children'] as List?) ?? const []) {
        flatten(child as Map<String, dynamic>);
      }
    }

    final tree = debugSemanticsNodeToMap(root);
    flatten(tree);
    Map<String, dynamic> labelled(String label) =>
        nodes.singleWhere((n) => n['label'] == label);

    // A button: its role, and nothing that is false or empty.
    expect(labelled('Send').keys, {'id', 'label', 'isButton', 'rect'});
    // Disabled is said; enabled is the default and is not.
    expect(labelled('Off')['isEnabled'], false);
    // An unchecked checkbox still says it is one.
    expect(nodes.where((n) => n['isChecked'] == false), hasLength(1));
    expect(labelled('Plain').keys, {'id', 'label', 'rect'});
    expect(json.encode(tree), isNot(contains('null')));

    expect(
      debugSemanticsNodeToMap(root, maxDepth: 0),
      isNot(contains('children')),
    );
    handle.dispose();
  });
}
