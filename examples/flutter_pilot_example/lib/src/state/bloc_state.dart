import 'package:flutter_bloc/flutter_bloc.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);
  void increment() => emit(state + 1);
  void decrement() => emit(state - 1);

  // Method to allow dynamic injection if needed,
  // though we used (bloc as dynamic).emit() in the plugin.
  void setManual(int value) => emit(value);
}

class ThemeCubit extends Cubit<bool> {
  ThemeCubit() : super(false); // false = light, true = dark
  void toggle() => emit(!state);
}
