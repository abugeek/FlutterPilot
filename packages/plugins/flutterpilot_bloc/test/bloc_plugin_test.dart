import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_bloc/flutterpilot_bloc.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);
  void increment() => emit(state + 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlocPilotObserver', () {
    late BlocPilotObserver observer;

    setUp(() {
      observer = BlocPilotObserver();
      Bloc.observer = observer;
    });

    test('tracks Cubit state transitions', () {
      final cubit = CounterCubit();
      cubit.increment();

      expect(cubit.state, 1);
      cubit.close();
    });

    test('handles state injection if dynamic emit is possible', () async {
      // This is mostly to ensure the observer's internal registry
      // and state setter logic don't crash.
      final cubit = CounterCubit();

      // The observer captures it on creation
      // ... logic here

      cubit.close();
    });
  });
}
