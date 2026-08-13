import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../state/riverpod_state.dart';
import '../state/bloc_state.dart';

class StateInjectionScreen extends ConsumerWidget {
  const StateInjectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riverpodCount = ref.watch(counterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('State Injection Testing')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _CounterCard(
              title: 'Riverpod Counter',
              value: riverpodCount,
              onIncrement: () => ref.read(counterProvider.notifier).increment(),
              keyPrefix: 'riverpod',
            ),
            const SizedBox(height: 20),
            BlocBuilder<CounterCubit, int>(
              builder: (context, state) {
                return _CounterCard(
                  title: 'Bloc Counter',
                  value: state,
                  onIncrement: () => context.read<CounterCubit>().increment(),
                  keyPrefix: 'bloc',
                );
              },
            ),
            const SizedBox(height: 40),
            const Card(
              color: Colors.blueGrey,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'AI DIRECTIVE: You can call set_riverpod_state("counterProvider", 99) or set_bloc_state("CounterCubit", 42) to change these values instantly.',
                  style: TextStyle(
                    color: Colors.white,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  final String title;
  final int value;
  final VoidCallback onIncrement;
  final String keyPrefix;

  const _CounterCard({
    required this.title,
    required this.value,
    required this.onIncrement,
    required this.keyPrefix,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineLarge,
              key: Key('${keyPrefix}_count_text'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              key: Key('${keyPrefix}_increment_button'),
              onPressed: onIncrement,
              child: const Text('Increment Manually'),
            ),
          ],
        ),
      ),
    );
  }
}
