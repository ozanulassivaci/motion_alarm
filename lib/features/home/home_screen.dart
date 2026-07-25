import 'package:flutter/foundation.dart';
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
      appBar: AppBar(
        title: const Text('Motion Alarm'),
        actions: [
          // Debug-only: reproduces the firing/delivery path in 10s instead
          // of waiting on the clock, for diagnosing scheduling issues.
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: 'TEST: 10 saniye sonra alarmı çal',
              onPressed: () => _guard(
                context,
                () => ref.read(alarmSchedulingServiceProvider).scheduleTestAlarm(),
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
