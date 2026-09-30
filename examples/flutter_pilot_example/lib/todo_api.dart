import 'package:dio/dio.dart';

class Todo {
  const Todo({required this.id, required this.title, required this.done});

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
    id: json['id'] as int,
    title: json['title'] as String,
    done: json['completed'] as bool,
  );

  final int id;
  final String title;
  final bool done;

  Todo copyWith({bool? done}) =>
      Todo(id: id, title: title, done: done ?? this.done);
}

/// JSONPlaceholder's fake todo API: reads are real, writes are echoed back
/// without being stored, so the app keeps its own list after the first load.
class TodoApi {
  TodoApi(this._dio);

  final Dio _dio;

  Future<List<Todo>> fetchTodos() async {
    final response = await _dio.get<List<dynamic>>(
      '/todos',
      queryParameters: {'_limit': 15},
    );
    return [
      for (final json in response.data!)
        Todo.fromJson((json as Map).cast<String, dynamic>()),
    ];
  }

  Future<Todo> addTodo(String title) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/todos',
      data: {'title': title, 'completed': false, 'userId': 1},
    );
    return Todo.fromJson(response.data!);
  }

  Future<void> setDone(int id, bool done) =>
      _dio.patch<void>('/todos/$id', data: {'completed': done});
}
