import 'package:flutter/material.dart';

import '../../data/models/alarm.dart';

const _dayLabels = {
  DateTime.monday: 'Pzt',
  DateTime.tuesday: 'Sal',
  DateTime.wednesday: 'Çar',
  DateTime.thursday: 'Per',
  DateTime.friday: 'Cum',
  DateTime.saturday: 'Cmt',
  DateTime.sunday: 'Paz',
};

class AlarmListView extends StatelessWidget {
  const AlarmListView({
    super.key,
    required this.alarms,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
  });

  final List<Alarm> alarms;
  final void Function(Alarm alarm, bool enabled) onToggle;
  final void Function(Alarm alarm) onTap;
  final void Function(Alarm alarm) onDelete;

  @override
  Widget build(BuildContext context) {
    if (alarms.isEmpty) {
      return const Center(
        child: Text('Henüz alarm yok. Eklemek için + butonuna dokun.'),
      );
    }

    final sorted = [...alarms]
      ..sort((a, b) {
        final aMinutes = a.hour * 60 + a.minute;
        final bMinutes = b.hour * 60 + b.minute;
        return aMinutes.compareTo(bMinutes);
      });

    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final alarm = sorted[index];
        final time = TimeOfDay(hour: alarm.hour, minute: alarm.minute);
        final repeatSummary = alarm.repeatDays.isEmpty
            ? 'Bir kere'
            : (alarm.repeatDays.toList()..sort())
                  .map((day) => _dayLabels[day])
                  .join(' ');

        return Dismissible(
          key: ValueKey(alarm.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(context).colorScheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: const Icon(Icons.delete),
          ),
          onDismissed: (_) => onDelete(alarm),
          child: ListTile(
            onTap: () => onTap(alarm),
            title: Text(time.format(context)),
            subtitle: Text(repeatSummary),
            trailing: Switch(
              value: alarm.enabled,
              onChanged: (value) => onToggle(alarm, value),
            ),
          ),
        );
      },
    );
  }
}
