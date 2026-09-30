import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'state.dart';
import 'todo_api.dart';

class TodoListScreen extends ConsumerWidget {
  const TodoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todosProvider);
    final filter = ref.watch(filterProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_todo'),
        onPressed: () => context.push('/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add todo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in Filter.values)
                  ChoiceChip(
                    label: Text(switch (f) {
                      Filter.all => 'All',
                      Filter.open => 'Open',
                      Filter.done => 'Done',
                    }),
                    selected: filter == f,
                    onSelected: (_) => ref.read(filterProvider.notifier).set(f),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (todos) {
              AsyncData(:final value) => _TodoList(
                todos: [
                  for (final t in value)
                    if (filter == Filter.all ||
                        (filter == Filter.done) == t.done)
                      t,
                ],
              ),
              AsyncError(:final error) => _LoadError(error: error),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _TodoList extends ConsumerWidget {
  const _TodoList({required this.todos});

  final List<Todo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (todos.isEmpty) return const Center(child: Text('Nothing here'));
    return RefreshIndicator(
      // A failed refresh is shown by the provider's error state.
      onRefresh: () => ref
          .refresh(todosProvider.future)
          .then((_) {}, onError: (Object _) {}),
      child: ListView.builder(
        itemCount: todos.length,
        itemBuilder: (context, i) {
          final todo = todos[i];
          return ListTile(
            key: Key('todo_${todo.id}'),
            leading: Checkbox(
              value: todo.done,
              semanticLabel: 'Done: ${todo.title}',
              onChanged: (_) =>
                  ref.read(todosProvider.notifier).toggle(todo.id),
            ),
            title: Text(
              todo.title,
              style: todo.done
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            onTap: () => context.push('/todo/${todo.id}'),
          );
        },
      ),
    );
  }
}

class _LoadError extends ConsumerWidget {
  const _LoadError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = error is DioException
        ? (error as DioException).response?.statusCode
        : null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status == null
                ? "Couldn't load todos"
                : "Couldn't load todos (HTTP $status)",
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => ref.invalidate(todosProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class AddTodoScreen extends ConsumerStatefulWidget {
  const AddTodoScreen({super.key});

  @override
  ConsumerState<AddTodoScreen> createState() => _AddTodoScreenState();
}

class _AddTodoScreenState extends ConsumerState<AddTodoScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(todosProvider.notifier).add(_title.text.trim());
      if (mounted) context.pop();
    } on DioException catch (e) {
      setState(() => _error = "Couldn't save (${e.response?.statusCode})");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New todo')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('title_field'),
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
              onFieldSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('save_button'),
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class TodoScreen extends ConsumerWidget {
  const TodoScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todo = ref
        .watch(todosProvider)
        .value
        ?.where((t) => t.id == id)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('Todo #$id')),
      body: todo == null
          ? const Center(child: Text('No such todo'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todo.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(todo.done ? 'Done' : 'Open'),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(todosProvider.notifier).toggle(id),
                    child: Text(todo.done ? 'Mark as open' : 'Mark as done'),
                  ),
                ],
              ),
            ),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SwitchListTile(
        title: const Text('Dark mode'),
        value: ref.watch(darkModeProvider),
        onChanged: (v) => ref.read(darkModeProvider.notifier).set(v),
      ),
    );
  }
}
