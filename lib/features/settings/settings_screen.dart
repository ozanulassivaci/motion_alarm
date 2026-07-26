import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/alarm.dart';
import 'settings_controller.dart';

const _difficultyLabels = {
  AlarmDifficulty.easy: 'Kolay',
  AlarmDifficulty.medium: 'Orta',
  AlarmDifficulty.hard: 'Zor',
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: settingsAsync.when(
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Zorluk başına tekrar sayısı'),
            ),
            _RepsRow(
              difficulty: AlarmDifficulty.easy,
              reps: settings.easyReps,
              ref: ref,
            ),
            _RepsRow(
              difficulty: AlarmDifficulty.medium,
              reps: settings.mediumReps,
              ref: ref,
            ),
            _RepsRow(
              difficulty: AlarmDifficulty.hard,
              reps: settings.hardReps,
              ref: ref,
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text('Ayarlar yüklenemedi: $error')),
      ),
    );
  }
}

class _RepsRow extends StatelessWidget {
  const _RepsRow({
    required this.difficulty,
    required this.reps,
    required this.ref,
  });

  final AlarmDifficulty difficulty;
  final int reps;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(_difficultyLabels[difficulty]!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () => ref
                .read(settingsControllerProvider.notifier)
                .setReps(difficulty, reps - 1),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$reps',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => ref
                .read(settingsControllerProvider.notifier)
                .setReps(difficulty, reps + 1),
          ),
        ],
      ),
    );
  }
}
