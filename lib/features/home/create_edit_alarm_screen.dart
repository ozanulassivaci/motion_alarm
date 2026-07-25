import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/alarm.dart';
import '../alarm/alarm_list_controller.dart';

const _dayOrder = [
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
  DateTime.saturday,
  DateTime.sunday,
];

const _dayLabels = {
  DateTime.monday: 'P',
  DateTime.tuesday: 'S',
  DateTime.wednesday: 'Ç',
  DateTime.thursday: 'P',
  DateTime.friday: 'C',
  DateTime.saturday: 'C',
  DateTime.sunday: 'P',
};

const _difficultyLabels = {
  AlarmDifficulty.easy: 'Kolay',
  AlarmDifficulty.medium: 'Orta',
  AlarmDifficulty.hard: 'Zor',
};

class CreateEditAlarmScreen extends ConsumerStatefulWidget {
  const CreateEditAlarmScreen({super.key, this.existingAlarm});

  final Alarm? existingAlarm;

  @override
  ConsumerState<CreateEditAlarmScreen> createState() =>
      _CreateEditAlarmScreenState();
}

class _CreateEditAlarmScreenState
    extends ConsumerState<CreateEditAlarmScreen> {
  late TimeOfDay _time;
  late Set<int> _repeatDays;
  late AlarmDifficulty _difficulty;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingAlarm;
    _time = existing == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: existing.hour, minute: existing.minute);
    _repeatDays = {...(existing?.repeatDays ?? <int>{})};
    _difficulty = existing?.difficulty ?? AlarmDifficulty.easy;
  }

  bool get _isEditing => widget.existingAlarm != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Alarmı Düzenle' : 'Yeni Alarm'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: TextButton(
              onPressed: _pickTime,
              child: Text(
                _time.format(context),
                style: Theme.of(context).textTheme.displayMedium,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Tekrar'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _dayOrder.map((day) {
              final selected = _repeatDays.contains(day);
              return FilterChip(
                label: Text(_dayLabels[day]!),
                selected: selected,
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _repeatDays.add(day);
                    } else {
                      _repeatDays.remove(day);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 32),
          FilledButton(onPressed: _save, child: const Text('Kaydet')),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  Future<void> _save() async {
    final controller = ref.read(alarmListControllerProvider.notifier);
    final existing = widget.existingAlarm;
    if (existing == null) {
      await controller.addAlarm(
        hour: _time.hour,
        minute: _time.minute,
        repeatDays: _repeatDays,
        difficulty: _difficulty,
      );
    } else {
      await controller.updateAlarm(
        existing.copyWith(
          hour: _time.hour,
          minute: _time.minute,
          repeatDays: _repeatDays,
          difficulty: _difficulty,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existingAlarm;
    if (existing == null) return;
    await ref.read(alarmListControllerProvider.notifier).deleteAlarm(existing.id);
    if (mounted) Navigator.of(context).pop();
  }
}
