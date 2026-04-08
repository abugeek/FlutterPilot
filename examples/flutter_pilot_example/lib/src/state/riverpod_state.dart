import 'package:flutter_riverpod/flutter_riverpod.dart';

final counterProvider = StateProvider<int>((ref) => 0);

final authProvider = StateProvider<bool>((ref) => false);

class User {
  final String name;
  final String email;
  User({required this.name, required this.email});
  Map<String, dynamic> toJson() => {'name': name, 'email': email};
  @override
  String toString() => 'User(name: $name, email: $email)';
}

final userProvider = StateProvider<User?>((ref) => null);
