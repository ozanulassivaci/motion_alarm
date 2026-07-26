import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config.dart';

/// Digital scroll-wheel time picker — replaces the Material dial
/// (`showTimePicker`) with two vertically-scrolling hour/minute wheels, the
/// way recent stock Android/iOS clock apps do it. Built entirely from
/// Flutter's own `ListWheelScrollView` (no new package): large item extents
/// and a bottom-sheet position for one-handed use in a dark room, per
/// CLAUDE.md's night-theme requirements for this screen. 24-hour, no AM/PM —
/// matches how the rest of the app already displays time (`TimeOfDay.format`)
/// and Turkish locale convention.
Future<TimeOfDay?> showTimeWheelPicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _TimeWheelPickerSheet(initialTime: initialTime),
  );
}

class _TimeWheelPickerSheet extends StatefulWidget {
  const _TimeWheelPickerSheet({required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<_TimeWheelPickerSheet> createState() => _TimeWheelPickerSheetState();
}

class _TimeWheelPickerSheetState extends State<_TimeWheelPickerSheet> {
  late int _hour = widget.initialTime.hour;
  late int _minute = widget.initialTime.minute;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Alarm Saati', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            SizedBox(
              height: AppConfig.timeWheelItemExtent * 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _WheelColumn(
                    itemCount: 24,
                    initialValue: _hour,
                    onChanged: (value) => setState(() => _hour = value),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      ':',
                      style: TextStyle(
                        fontSize: AppConfig.timeWheelFontSize,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _WheelColumn(
                    itemCount: 60,
                    initialValue: _minute,
                    onChanged: (value) => setState(() => _minute = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(TimeOfDay(hour: _hour, minute: _minute)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One looping hour-or-minute wheel. A thin highlight band behind the
/// center row marks the "selected" value, the common wheel-picker
/// convention — the value under it is whatever `onChanged` last reported.
class _WheelColumn extends StatefulWidget {
  const _WheelColumn({
    required this.itemCount,
    required this.initialValue,
    required this.onChanged,
  });

  final int itemCount;
  final int initialValue;
  final ValueChanged<int> onChanged;

  @override
  State<_WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<_WheelColumn> {
  late final _controller = FixedExtentScrollController(
    initialItem: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemExtent = AppConfig.timeWheelItemExtent;
    return SizedBox(
      width: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              height: itemExtent,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: itemExtent,
            physics: const FixedExtentScrollPhysics(),
            diameterRatio: 1.6,
            onSelectedItemChanged: (index) {
              HapticFeedback.selectionClick();
              widget.onChanged(index % widget.itemCount);
            },
            childDelegate: ListWheelChildLoopingListDelegate(
              children: List.generate(
                widget.itemCount,
                (index) => Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: AppConfig.timeWheelFontSize,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
