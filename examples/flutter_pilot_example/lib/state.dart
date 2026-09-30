import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'todo_api.dart';

/// Overridden in main() (and in tests) with the real instances.
final apiProvider = Provider<TodoApi>((ref) => throw UnimplementedError());
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);

class TodosNotifier extends AsyncNotifier<List<Todo>> {
  @override
  Future<List<Todo>> build() => ref.watch(apiProvider).fetchTodos();

  Future<void> add(String title) async {
    final todo = await ref.read(apiProvider).addTodo(title);
    // The fake API answers every new todo with the same id: number it here.
    final todos = state.value ?? const [];
    final id = todos.fold(todo.id, (max, t) => t.id > max ? t.id : max) + 1;
    state = AsyncData([Todo(id: id, title: todo.title, done: false), ...todos]);
  }

  Future<void> toggle(int id) async {
    final todos = state.value ?? const [];
    final todo = todos.firstWhere((t) => t.id == id);
    await ref.read(apiProvider).setDone(id, !todo.done);
    state = AsyncData([
      for (final t in todos) t.id == id ? t.copyWith(done: !t.done) : t,
    ]);
  }
}

final todosProvider = AsyncNotifierProvider<TodosNotifier, List<Todo>>(
  TodosNotifier.new,
);

enum Filter { all, open, done }

class FilterNotifier extends Notifier<Filter> {
  @override
  Filter build() => Filter.all;

  void set(Filter filter) => state = filter;
}

final filterProvider = NotifierProvider<FilterNotifier, Filter>(
  FilterNotifier.new,
);

class DarkModeNotifier extends Notifier<bool> {
  static const key = 'dark_mode';

  @override
  bool build() => ref.watch(prefsProvider).getBool(key) ?? false;

  Future<void> set(bool dark) async {
    state = dark;
    await ref.read(prefsProvider).setBool(key, dark);
  }
}

final darkModeProvider = NotifierProvider<DarkModeNotifier, bool>(
  DarkModeNotifier.new,
);
