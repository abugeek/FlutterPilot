import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_bloc/flutterpilot_bloc.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);
  void increment() => emit(state + 1);
}

class VolumeCubit extends Cubit<double> {
  VolumeCubit() : super(0.5);
}

class Filter {
  const Filter(this.query);
  final String query;
  @override
  String toString() => 'Filter($query)';
}

class FilterCubit extends Cubit<Filter> {
  FilterCubit() : super(const Filter(''));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    BlocPilotObserver.reset();
    Bloc.observer = BlocPilotObserver();
  });

  test('lists each live bloc once, with its current state', () async {
    final counter = CounterCubit()..increment();
    final filter = FilterCubit();

    expect(BlocPilotObserver.states(), {
      'CounterCubit': {'state': '1', 'type': 'int'},
      'FilterCubit': {'state': 'Filter()', 'type': 'Filter'},
    });

    await counter.close();
    expect(BlocPilotObserver.states().keys, ['FilterCubit']);
    await filter.close();
  });

  test('several instances of one class get #n names', () async {
    final a = CounterCubit();
    final b = CounterCubit()..increment();
    expect(BlocPilotObserver.states().keys, ['CounterCubit', 'CounterCubit#2']);
    expect(BlocPilotObserver.states()['CounterCubit#2']!['state'], '1');
    await a.close();
    await b.close();
  });

  test('injects JSON-expressible states, coercing int to double', () async {
    final counter = CounterCubit();
    final volume = VolumeCubit();

    BlocPilotObserver.inject('CounterCubit', 42);
    BlocPilotObserver.inject('VolumeCubit', 1);

    expect(counter.state, 42);
    expect(volume.state, 1.0);
    await counter.close();
    await volume.close();
  });

  test('a class-typed state is refused with what to do instead', () async {
    final filter = FilterCubit();
    expect(
      () => BlocPilotObserver.inject('FilterCubit', {'query': 'x'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('holds a Filter'), contains('drive the UI')),
        ),
      ),
    );
    expect(filter.state.query, '');
    await filter.close();
  });

  test('unknown name lists the live blocs', () async {
    final counter = CounterCubit();
    expect(
      () => BlocPilotObserver.inject('AuthBloc', 1),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Live: CounterCubit'),
        ),
      ),
    );
    await counter.close();
  });

  test('long states are capped', () async {
    final filter = FilterCubit()..emit(Filter('x' * 2000));
    final state = BlocPilotObserver.states()['FilterCubit']!['state']!;
    expect(state.length, lessThan(600));
    expect(state, endsWith('(2008 chars)'));
    await filter.close();
  });
}
