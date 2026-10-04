import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  // Octana's home: a full-screen GestureDetector (tap to dismiss the
  // keyboard) around a page with a NavigationBar. The tappable list names a
  // destination "Inventory Tab 3 of 5"; tapping by that name hit the centre
  // of the screen, where the End Shift button is.
  testWidgets('a tab named as the tappable list names it is the tab', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: GestureDetector(
          onTap: () {},
          child: Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {},
                child: const Text('End shift'),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(
                  icon: Icon(Icons.receipt),
                  label: 'Sales',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory),
                  label: 'Inventory',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final element = PilotWidgetInspector.findElement('Inventory Tab 3 of 3');
    final box = element?.renderObject as RenderBox?;
    expect(element, isNotNull);
    expect(box!.size.height, lessThan(200), reason: '${element!.widget}');
    expect(box.localToGlobal(Offset.zero).dy, greaterThan(400));

    // A phrase only the page as a whole contains names no control.
    expect(PilotWidgetInspector.findElement('shift Home'), isNull);
    handle.dispose();
  });
}
