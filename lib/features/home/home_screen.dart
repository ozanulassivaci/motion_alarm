import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/alarm.dart';
import '../../data/models/exercise_type.dart';
import '../alarm/alarm_list_controller.dart';
import '../exercise/pose_detection_dev_screen.dart';
import '../settings/settings_screen.dart';
import 'alarm_list_view.dart';
import 'create_edit_alarm_screen.dart';

const _difficultyLabels = {
  AlarmDifficulty.easy: 'Kolay',
  AlarmDifficulty.medium: 'Orta',
  AlarmDifficulty.hard: 'Zor',
};

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(alarmListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Motion Alarm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ayarlar',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          // Debug-only: short-press reproduces the firing/delivery path in
          // 10s with the Easy+all-four fallback, as before. Long-press opens
          // a config sheet to pick difficulty/pool first, so Medium/Hard's
          // multi-exercise path is reachable without waiting for a real
          // alarm — both go through the exact same drawWorkout() call in
          // WorkoutScreen, just with different inputs.
          if (kDebugMode)
            Tooltip(
              message:
                  'TEST: 10sn sonra alarmı çal (uzun bas: zorluk/egzersiz seç)',
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _guard(
                  context,
                  () =>
                      ref.read(alarmSchedulingServiceProvider).scheduleTestAlarm(),
                ),
                onLongPress: () => _openTestAlarmConfigSheet(context, ref),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.bug_report_outlined),
                ),
              ),
            ),
          // Debug-only: opens the camera + pose pipeline directly, without
          // setting an alarm, for fast iteration on Phase 2.
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined),
              tooltip: 'TEST: Kamera + poz algılama',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PoseDetectionDevScreen(),
                ),
              ),
            ),
        ],
      ),
      body: alarmsAsync.when(
        data: (alarms) => AlarmListView(
          alarms: alarms,
          onToggle: (alarm, enabled) => _guard(
            context,
            () => ref
                .read(alarmListControllerProvider.notifier)
                .toggleEnabled(alarm.id, enabled),
          ),
          onTap: (alarm) => _openEditScreen(context, alarm),
          onDelete: (alarm) => _guard(
            context,
            () => ref
                .read(alarmListControllerProvider.notifier)
                .deleteAlarm(alarm.id),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text('Alarmlar yüklenemedi: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCreateScreen(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openCreateScreen(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateEditAlarmScreen()));
  }

  void _openEditScreen(BuildContext context, Alarm alarm) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateEditAlarmScreen(existingAlarm: alarm),
      ),
    );
  }

  Future<void> _openTestAlarmConfigSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result =
        await showModalBottomSheet<
          ({AlarmDifficulty difficulty, Set<ExerciseType> exercisePool})
        >(context: context, isScrollControlled: true, builder: (context) => const _TestAlarmConfigSheet());
    if (result == null || !context.mounted) return;
    await _guard(
      context,
      () => ref
          .read(alarmSchedulingServiceProvider)
          .scheduleTestAlarm(
            difficulty: result.difficulty,
            exercisePool: result.exercisePool,
          ),
    );
  }

  Future<void> _guard(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('[HomeScreen] action FAILED: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('İşlem başarısız: $error')));
      }
    }
  }
}

class _TestAlarmConfigSheet extends StatefulWidget {
  const _TestAlarmConfigSheet();

  @override
  State<_TestAlarmConfigSheet> createState() => _TestAlarmConfigSheetState();
}

class _TestAlarmConfigSheetState extends State<_TestAlarmConfigSheet> {
  // Defaults to Medium + every exercise: the whole point of this sheet is
  // reaching the multi-exercise path, one tap away from firing.
  AlarmDifficulty _difficulty = AlarmDifficulty.medium;
  final Set<ExerciseType> _pool = {...ExerciseType.values};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Test Alarmını Yapılandır',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          const Text('Zorluk'),
          const SizedBox(height: 8),
          SegmentedButton<AlarmDifficulty>(
            segments: AlarmDifficulty.values
                .map(
                  (difficulty) => ButtonSegment(
                    value: difficulty,
                    label: Text(_difficultyLabels[difficulty]!),
                  ),
                )
                .toList(),
            selected: {_difficulty},
            onSelectionChanged: (selection) {
              setState(() => _difficulty = selection.first);
            },
          ),
          const SizedBox(height: 16),
          const Text('Egzersizler'),
          ...ExerciseType.values.map(
            (type) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(type.label),
              value: _pool.contains(type),
              onChanged: (checked) {
                setState(() {
                  if (checked ?? false) {
                    _pool.add(type);
                  } else {
                    _pool.remove(type);
                  }
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _pool.isEmpty
                ? null
                : () => Navigator.of(
                    context,
                  ).pop((difficulty: _difficulty, exercisePool: _pool)),
            child: const Text('10sn Sonra Çal'),
          ),
        ],
      ),
    );
  }
}
