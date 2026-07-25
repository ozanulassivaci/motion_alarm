import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/alarm.dart';
import '../alarm/alarm_list_controller.dart';
import 'alarm_list_view.dart';
import 'create_edit_alarm_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(alarmListControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Motion Alarm')),
      body: alarmsAsync.when(
        data: (alarms) => AlarmListView(
          alarms: alarms,
          onToggle: (alarm, enabled) => ref
              .read(alarmListControllerProvider.notifier)
              .toggleEnabled(alarm.id, enabled),
          onTap: (alarm) => _openEditScreen(context, alarm),
          onDelete: (alarm) => ref
              .read(alarmListControllerProvider.notifier)
              .deleteAlarm(alarm.id),
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
}
