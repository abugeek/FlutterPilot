import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/form_inspector.dart';

void main() {
  final formKey = GlobalKey<FormState>();

  // A sign-up form: two validated fields, one plain TextField whose error
  // the app sets itself, and a field with nothing to complain about.
  Widget form({String? couponError}) => MaterialApp(
    home: Scaffold(
      body: Form(
        key: formKey,
        child: Column(
          children: [
            TextFormField(
              key: const ValueKey('email'),
              initialValue: 'test@',
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) =>
                  v != null && v.contains('.') ? null : 'Enter a valid email',
            ),
            TextFormField(
              key: const ValueKey('phone'),
              decoration: const InputDecoration(hintText: 'Phone'),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Phone number is required' : null,
            ),
            TextFormField(
              key: const ValueKey('name'),
              initialValue: 'Ann',
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            TextField(
              key: const ValueKey('coupon'),
              decoration: InputDecoration(
                labelText: 'Coupon',
                errorText: couponError,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Element el(WidgetTester tester, String key) =>
      tester.element(find.byKey(ValueKey(key)));

  testWidgets('before the form shows anything: what would fail', (
    tester,
  ) async {
    await tester.pumpWidget(form());
    expect(FormInspector.of(el(tester, 'email')), (
      shown: null,
      pending: 'Enter a valid email',
    ));
    expect(FormInspector.of(el(tester, 'name')), isNull);
    expect(FormInspector.of(el(tester, 'coupon')), isNull);
    expect(FormInspector.problemsOnScreen(), [
      'Email: "Enter a valid email"',
      'Phone: "Phone number is required"',
    ]);
    // Asking did not make the form show its errors.
    expect(find.text('Enter a valid email'), findsNothing);
  });

  testWidgets('after validation: the errors on screen, per field', (
    tester,
  ) async {
    await tester.pumpWidget(form(couponError: 'Unknown coupon'));
    formKey.currentState!.validate();
    await tester.pump();

    expect(FormInspector.of(el(tester, 'phone')), (
      shown: 'Phone number is required',
      pending: null,
    ));
    // The inner TextField of a TextFormField answers for its field.
    final inner = tester.element(
      find.descendant(
        of: find.byKey(const ValueKey('email')),
        matching: find.byType(TextField),
      ),
    );
    expect(FormInspector.of(inner)?.shown, 'Enter a valid email');
    // A plain TextField with an errorText of the app's own.
    expect(FormInspector.of(el(tester, 'coupon'))?.shown, 'Unknown coupon');
    expect(FormInspector.problemsOnScreen(), [
      'Email: "Enter a valid email"',
      'Phone: "Phone number is required"',
      'Coupon: "Unknown coupon"',
    ]);
  });

  testWidgets('a container of fields has no error of its own', (tester) async {
    await tester.pumpWidget(form());
    formKey.currentState!.validate();
    await tester.pump();
    expect(FormInspector.of(tester.element(find.byType(Column))), isNull);
    expect(FormInspector.of(tester.element(find.byType(Scaffold))), isNull);
  });
}
