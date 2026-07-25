import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:motion_alarm/app/app.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('shows an empty state with no alarms yet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MotionAlarmApp()));
    await tester.pumpAndSettle();

    expect(find.text('Motion Alarm'), findsOneWidget);
    expect(
      find.text('Henüz alarm yok. Eklemek için + butonuna dokun.'),
      findsOneWidget,
    );
  });
}
