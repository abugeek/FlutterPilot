import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pilot_example/main.dart';
import 'package:flutter_pilot_example/state.dart';
import 'package:flutter_pilot_example/todo_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeApi implements TodoApi {
  int? failWith;

  @override
  Future<List<Todo>> fetchTodos() async {
    if (failWith case final status?) {
      final request = RequestOptions(path: '/todos');
      throw DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: status),
      );
    }
    return const [
      Todo(id: 1, title: 'Buy milk', done: false),
      Todo(id: 2, title: 'Walk the dog', done: true),
    ];
  }

  @override
  Future<Todo> addTodo(String title) async =>
      Todo(id: 201, title: title, done: false);

  @override
  Future<void> setDone(int id, bool done) async {}
}

void main() {
  late FakeApi api;

  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          apiProvider.overrideWithValue(api),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: App(router: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => api = FakeApi());

  testWidgets('lists todos and filters them', (tester) async {
    await pumpApp(tester);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Walk the dog'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsNothing);
    expect(find.text('Walk the dog'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Nothing here'), findsOneWidget);
  });

  testWidgets('adds a todo after the title is filled in', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('add_todo')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a title'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('title_field')), 'Call mom');
    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();
    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Call mom'), findsOneWidget);
    // Numbered after the highest id, not the fake API's constant 201.
    expect(find.byKey(const Key('todo_202')), findsOneWidget);
  });

  testWidgets('a server error shows the status and a working Retry', (
    tester,
  ) async {
    api.failWith = 500;
    await pumpApp(tester);
    expect(find.text("Couldn't load todos (HTTP 500)"), findsOneWidget);

    api.failWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('dark mode is saved', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DarkModeNotifier.key), isTrue);
    expect(
      Theme.of(tester.element(find.text('Settings'))).brightness,
      Brightness.dark,
    );
  });
}
