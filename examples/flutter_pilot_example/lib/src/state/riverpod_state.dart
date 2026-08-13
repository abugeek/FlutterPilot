import 'package:flutter_riverpod/flutter_riverpod.dart';

class CounterNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final counterProvider = NotifierProvider<CounterNotifier, int>(
  CounterNotifier.new,
);

class AuthNotifier extends Notifier<bool> {
  @override
  bool build() => false;
}

final authProvider = NotifierProvider<AuthNotifier, bool>(AuthNotifier.new);

class User {
  final String name;
  final String email;
  User({required this.name, required this.email});
  Map<String, dynamic> toJson() => {'name': name, 'email': email};
  @override
  String toString() => 'User(name: $name, email: $email)';
}

class UserNotifier extends Notifier<User?> {
  @override
  User? build() => null;
}

final userProvider = NotifierProvider<UserNotifier, User?>(UserNotifier.new);
