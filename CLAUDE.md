# Motion Alarm — Project Guide (CLAUDE.md)

> This file is the project's constitution. Read it at the start of every session.
> When a task conflicts with this file, follow this file and flag the conflict.

## What this app is

Motion Alarm is a **free** alarm app (no monetization, no ads, no selling of data).
When an alarm fires, the user must physically complete a short exercise set,
verified in real time by the phone camera using **on-device** pose estimation,
before the alarm will stop.

## Current State (as of Phase 4)

**Complete and verified on a physical device (Galaxy A25):**
- Phase 0 — scaffolding, themes, folder structure.
- Phase 1 — alarm core: scheduling, permissions, full-screen ring over the
  lock screen, survives the app being killed.
- Phase 2 — camera + on-device pose pipeline, skeleton overlay correctly
  aligned (mirror + rotation handled).
- Phase 3 — rep-counting engine, all four exercises, tunable from the dev
  screen's debug overlay.

**Implemented, not yet verified on device:**
- Phase 4 — alarm + exercise integration (workout drawing, framing check,
  countdown, calibration, exercise flow, transitions, completion,
  emergency exit, permission-missing fallback). Builds and analyzes clean;
  awaiting an on-device end-to-end pass.
- Phase 5 — alarm robustness: a native foreground service now owns alarm
  ringing independently of any Activity. **The core mechanism is verified
  on-device**: sound survives home/recents/kill, which was the main goal.
  A first on-device pass also found five defects (duplicate notification,
  reopening the app not returning to the alarm, wrong time displayed, the
  notification being dismissible, vibration not working) — all fixed; see
  "Alarm ownership architecture" below for what's implemented and awaiting
  re-verification against the break-out test steps in that section.

**Known gaps:**
- Reboot persistence: `ScheduledNotificationBootReceiver` is declared and
  should reschedule alarms after a reboot per flutter_local_notifications'
  documented behavior, but this has never actually been tested by
  rebooting the device.
- Rep-counter/ROM-gate thresholds in `core/config.dart` are reasoned
  starting guesses, not measured — tuning against real body data is an
  explicitly separate, not-yet-started phase.
- Beep toggle: `FeedbackService.beepEnabled` exists and defaults on, but
  isn't yet exposed in the real Settings screen or persisted — only the
  camera dev screen's local switch can change it, and only for that
  session.
- Practice mode and the debug/eval-logging folder (`features/debug/`) are
  still Phase 0 placeholders — not implemented.
- iOS alarm layer remains best-effort/TODO, per Platforms below.

**Key decisions made along the way, not otherwise written down:**
- **The rep-counter design below is superseded by what's actually
  implemented.** Measured ~8-10fps on-device (ML Kit inference is a ~65ms
  hardware floor on this chip — neither a lower camera resolution nor
  manual pre-inference downscaling reduced it) makes fixed-threshold
  crossing detection unreliable for fast reps. The engine actually built
  is extrema-reversal: track a running local peak/trough, confirm it once
  the signal retraces from it by more than `minRepAmplitude` (a *relative*
  reversal gate, not an absolute threshold), then separately gate the
  confirmed cycle on an absolute range of motion (a fraction of the
  calibration reference) and `minRepDurationMs` between the two confirmed
  extrema. Deliberately no minimum-sample-count requirement, since that
  would miss fast reps at this frame rate.
- **Calibration is once per workout session, not once per exercise** — the
  first exercise's calibration reference is reused for exercises 2/3 in
  Medium/Hard workouts.
- **The workout is drawn from the alarm's stored difficulty + exercise
  pool at fire time**, not precomputed at schedule time, keeping alarm
  scheduling fully decoupled from workout-planning logic (the notification
  payload is still just the alarm id). If the pool is smaller than the
  difficulty needs, all of the pool's exercises are used rather than
  repeating one.
- **flutter_local_notifications (v16+) no longer declares its own
  receivers.** `ScheduledNotificationReceiver` (delivery) and
  `ScheduledNotificationBootReceiver` (reboot reschedule) must be declared
  by hand in `AndroidManifest.xml`, or alarms schedule "successfully" but
  never actually fire, with no exception anywhere.
- **camera_android_camerax converts every captured frame from
  YUV_420_888 to NV21 natively**, allocating a fresh buffer each time,
  regardless of whether that frame is later processed or dropped in Dart.
  The fix was capping the camera's own capture rate
  (`CameraController(fps: ...)`), not just dropping frames after arrival.
- The framing-check's ghost silhouette is a procedural `CustomPainter`,
  not an image asset or package.
- Emergency exit, workout completion, and the permission-missing fallback
  all exit through one shared path: stop any lingering feedback, call
  `disableIfOneTime`, navigate to the home screen clearing the stack.
- The dev-only test-alarm button (long-press) encodes its chosen
  difficulty/pool into the notification payload itself, since that config
  has to survive the app being killed during the 10-second wait — the
  same reason a real alarm's payload is just an id looked up later.

## Golden rules (apply to every task)

1. Do exactly what the current task asks. Do **not** build ahead into later phases.
2. Never weaken privacy: camera frames and pose data **never leave the device**.
   No network call ever includes user imagery or body-pose data.
3. Prefer boring, well-maintained packages over clever ones. Before adding a
   dependency, check its current version and health on pub.dev — do not guess
   versions from memory.
4. Every constant that affects detection or timing lives in `core/config.dart`,
   never hard-coded inline. Each one has a comment explaining what it does.
5. When a product or architecture decision is ambiguous, STOP and ask — do not guess.
6. Keep the iOS build structurally valid, but Android is the only target we test now.

## Platforms

- **Primary: Android** — the only tested target for now.
- **iOS**: keep the folder and platform-specific code paths valid and isolated,
  but do not invest in iOS-only features. iOS cannot schedule true system alarms;
  treat its alarm layer as best-effort and clearly marked TODO.

## Tech stack (do not change without asking)

- Flutter (stable channel), Dart.
- **State management: Riverpod** for app-level state (alarms, settings).
  The camera -> pose -> rep-count loop lives in a dedicated controller, never in widgets.
- **Pose**: `google_mlkit_pose_detection` (on-device).
- **Camera**: `camera` plugin.
- **Local persistence**: `shared_preferences` for settings; a simple local store
  for the alarm list. No cloud, no accounts.
- **Alarm scheduling**: native Android via a well-maintained plugin
  (e.g. `flutter_local_notifications` for full-screen intent, plus exact-alarm
  handling). Requires: exact alarms, full-screen intent, show-when-locked,
  turn-screen-on. Verify the exact package/approach on pub.dev before committing.

## Folder structure (feature-first)

```
lib/
  main.dart
  app/          app entry, ProviderScope, theme, routing
  core/         config.dart (all thresholds/constants), utils, haptics, feedback
  data/         models, repositories, local storage
  features/
    alarm/      scheduling, alarm-ring screen, alarm service
    exercise/   camera, pose pipeline, rep-counter engine, exercise defs,
                framing-check, calibration
    home/       alarm list, create/edit alarm
    settings/
    practice/   daytime practice mode
    debug/      eval logging, metric inspector
```

## Rep-counting engine (core design)

- ONE exercise-agnostic `RepCounter` state machine.
- Each exercise supplies a **pure function** `metric(landmarks) -> double`,
  returning a normalized, scale-invariant value.
- Mandatory layers, in order:
  1. **Normalization** — divide distances/coordinates by torso length or shoulder
     width. Never use raw pixels.
  2. **Smoothing** — EMA or One-Euro filter on landmarks before computing metric.
  3. **Hysteresis** — two thresholds: enter DOWN below X, return UP above Y.
     Count a rep only on a DOWN -> UP transition.
  4. **Validity rules** — minimum rep duration, minimum amplitude, minimum
     landmark visibility. If landmarks are unreliable, FREEZE the counter and
     show the user "Işığı aç, seni göremiyorum" — do not count.

## Exercises (MVP set)

1. **Squat** — hip Y drop vs. calibrated standing pose, normalized to leg length.
   Front-facing; must NOT require a side view.
2. **Jumping jack** — (ankle distance / shoulder width) ratio AND wrists above
   the shoulder line. Two conditions AND-ed.
3. **High knees** — per-leg state machine; each knee lift above threshold = 1 rep.
4. **Overhead reach** — wrist Y above nose/shoulder line = 1 rep.

Side bends is an easy future addition (torso-vector angle from vertical).
Arm circles is explicitly deferred — it cannot be counted reliably yet.

## Single framing standard

The user faces the camera, full body in frame, ~2–2.5 m away. Every exercise
metric MUST work in this one framing. Before any counting, a **framing-check
screen** verifies the required landmarks are visible and confidently tracked;
counting begins with a 3-2-1 countdown once the user is correctly positioned.

## Calibration

On the first exercise (or once per session), a 3-second "stand still" capture
records a personal reference (torso length, resting hip height). The squat
threshold derives from this.

## Difficulty

Difficulty changes the **workout**, not the detector:

- Easy:   1 exercise  x 8 reps
- Medium: 2 different exercises x 10 reps
- Hard:   3 different exercises x 12 reps

The user selects a **pool** of accepted exercises. Each morning the required
exercise(s) are drawn **randomly** from that pool (if the pool has one item,
it is always that one). Rep counts are user-adjustable in settings; the numbers
above are defaults.

## Feedback (haptic / sound) — it is an OUTPUT of counting

- Each VALID counted rep -> short haptic pulse (+ optional short beep, toggleable
  in settings; haptic is always on).
- Last 3 reps -> a distinct/heavier haptic to signal the finish line.
- Completion -> long success vibration, alarm fully stops, screen flashes the
  accent color once.
- **Volume rule (changed in Phase 5): the alarm sound does NOT stop when the
  exercise starts.** It keeps looping, at a reduced volume
  (`AppConfig.alarmVolumeDuringExerciseFraction`), through the entire
  workout — otherwise tapping "Egzersize Başla" would be a free snooze with
  no enforcement behind it. Only completion or a confirmed emergency exit
  actually stops it. The alarm's own *vibration* loop does stop at this
  point (freeing the single vibration motor for per-rep haptic feedback),
  but the sound is the one channel that keeps nagging throughout. See
  "Alarm ownership architecture" below for how this is implemented.

## Theme

- **Night / setup UI** (creating & editing alarms, done in bed): dark,
  low-contrast, calm. Not pure black — base `#0B0D10`. One strong accent color.
- **Alarm-ringing / exercise UI**: bright, high-contrast, near-white background,
  request max screen brightness, huge tabular numerals readable from 2 m.
- After the alarm is dismissed, return to the dark theme.

## Alarm behavior

- Exact alarm, full-screen intent, show-when-locked, turn-screen-on.
- Verify camera + exact-alarm permissions the night before (at alarm creation),
  never surprise the user at 7 a.m.
- An **emergency exit** exists but is deliberately effortful (long-press + confirm),
  so a stuck user is never trapped, but it is not the easy path.
- **Practice mode** lets the user run any exercise during the day without an alarm.

## Alarm ownership architecture (Phase 5)

Phase 4 testing showed the alarm's core promise was broken: ringing lived
inside `AlarmRingScreen`'s widget state, so killing or backgrounding the app
silenced it. Fixed by making a native Android foreground service
(`AlarmRingService`) the sole owner of ringing (sound + vibration),
independent of any Activity. **The Flutter UI — `AlarmRingScreen`,
`WorkoutScreen` — is only a view over the service's state now; it never owns
a `MediaPlayer`/`Vibrator` again**, only sends `lowerVolume()`/
`stopRinging()` commands through a `MethodChannel` (`motion_alarm/ring_service`,
wired in `MainActivity.kt`).

- **Why a second, parallel, natively-scheduled `AlarmManager` entry exists**
  (`NativeAlarmRingBridge.scheduleRing`, fired by `AlarmRingReceiver`), rather
  than hooking `flutter_local_notifications`' existing one:
  `flutter_local_notifications` posts its `PendingIntent` as an **explicit**
  broadcast to its own receiver class, which Android delivers only to that
  one component — a second receiver cannot piggyback on the same broadcast.
  `flutter_local_notifications`' own `zonedSchedule` call is completely
  untouched by this; the new entry is purely additive, fired at the
  identical instant.
- **Full-screen intent's real limit** (verified against current Android
  docs, not assumed): on a **locked** device, FSI still launches the
  Activity directly over the lock screen, unchanged. On an **unlocked**
  device already on the home screen or in another app, FSI does **not**
  force-launch the Activity — it only surfaces as a heads-up notification.
  This means the ring must be startable independent of the Flutter
  engine/Activity ever running at all, not just survivable after it has —
  which is exactly why the native parallel-entry mechanism above is
  necessary, not optional. The guarantee this architecture gives is that
  **once started, sound/vibration cannot be silenced** by backgrounding,
  swiping the app away, or the back gesture. Getting the *screen* back in
  front of the user is best-effort: full-screen intent when locked;
  otherwise the persistent, ongoing notification (`AlarmRingService`'s own,
  superseding `flutter_local_notifications`' moments after it posts) is
  tappable to return. That notification is dismissible on Android 14+ (see
  the repost-on-dismiss fix below) — not truly non-dismissible — but
  dismissing it never silences the ring either way.
- **Audio attribution was a live bug, not a feature, before this phase.**
  The old Dart `AudioPlayer` never called `setAudioContext`, so it played on
  Android's default `AudioContextAndroid` — `USAGE_MEDIA`, `AUDIOFOCUS_GAIN`
  — meaning the ring was **not** exempt from Do Not Disturb and was
  actively requesting audio focus another app could interrupt. Fixed: the
  native `MediaPlayer` uses `AudioAttributes.USAGE_ALARM` and requests **no**
  audio focus at all (matching how AOSP's own Clock app plays its alarm
  tone, so nothing can duck or steal it). No `MediaSession` is registered
  anywhere in the audio path, confirmed on both the old and new
  implementation.
- **Back is blocked** (`PopScope(canPop: false)`) on both `AlarmRingScreen`
  and `WorkoutScreen`. `MainActivity` declares
  `android:resizeableActivity="false"`, opting out of split-screen/
  freeform/Samsung pop-up view entirely.
- **Session persistence**: `WorkoutSessionRepository` (backed by
  `shared_preferences`, same pattern as the alarm/settings stores) persists
  the drawn `Workout`, current exercise index, reps completed for the
  current exercise, and the calibration reference — on every rep and every
  exercise transition, discarded if older than
  `AppConfig.workoutSessionMaxAgeMinutes`. `WorkoutSessionController` checks
  for a resumable session before starting fresh, and resumes straight into
  `exercising` (skipping framing-check/countdown/calibration entirely) via
  `ExerciseCountingController.startExerciseWithExistingCalibration`'s
  additive `resumeReps` parameter, which credits already-counted reps
  without replaying pose history or touching `RepCounter` internals.
- **Camera permission revoked mid-exercise** no longer risks a crash or a
  silent freeze: `WorkoutScreen` polls permission status every
  `AppConfig.cameraPermissionPollIntervalMs` while a camera-dependent state
  is active and falls back to the existing permission-missing view. This is
  effectively free precisely because sound is service-owned now and needs
  no special handling on this path at all.
- **Mechanisms explicitly rejected**, with reasoning, so they aren't
  reintroduced later:
  - `SYSTEM_ALERT_WINDOW` ("display over other apps") — not requested.
    Full-screen intent is the officially sanctioned mechanism for
    alarm-category apps and needs no overlay permission; `SYSTEM_ALERT_WINDOW`
    draws heavy Play Store scrutiny for no benefit FSI doesn't already cover.
  - **Screen pinning / lock task mode** — not implemented. Without a
    device-owner, the user can always escape it via the standard
    swipe-up-and-hold gesture, so it adds a consent dialog and support
    confusion without a real guarantee; the back-gesture intercept above
    gets most of the same benefit for free.
  - **A `camera`-type foreground service** (keeping the pose pipeline
    running while backgrounded) — not implemented. Background camera access
    is one of the most heavily scrutinized permissions on Play. The camera
    stays tied to the visible Activity; if the user backgrounds mid-exercise,
    rep progress simply pauses (state persists, see above) and resumes when
    the screen comes back — "can't rep-count what it can't see" is
    acceptable, policy-safe behavior, not a bug.
- **Accepted holes** (a threat model ranked every escape vector on this
  Galaxy A25/Android 16 build; these are the ones deliberately left open,
  not overlooked): force-stopping the app from system Settings, powering
  the device off, uninstalling the app, and — before the alarm fires only —
  manually changing the system clock. All are OS-level user-sovereignty
  guarantees no Android app can or should override. Muting the alarm via the
  volume buttons is also always possible and not blocked (attempting to
  intercept hardware volume keys reads as hostile and risks Play policy) —
  it degrades the wake-up nag, but the exercise gate itself stays enforced
  regardless of audio volume.

**Five defects found on the first on-device pass, and how they were fixed:**
- **Duplicate notification.** Both `flutter_local_notifications` and
  `AlarmRingService` were meant to post to the same notification id (so the
  service's post supersedes the other), but the id was never actually
  threaded through natively — `AlarmRingService` used its own hardcoded
  constant. Fixed by passing the same `id` all the way through
  (`NativeAlarmRingBridge.scheduleRing` → `MainActivity` → `AlarmRingReceiver`
  → `AlarmRingService`, as `EXTRA_NOTIFICATION_ID`). Since two independently
  scheduled exact alarms firing at the identical instant have no guaranteed
  ordering, the native entry is additionally scheduled
  `AppConfig.ringServiceStartDelayMs` (300ms) after
  `flutter_local_notifications`' one, so `AlarmRingService`'s post
  deterministically wins instead of racing it.
- **Reopening the app didn't return to the alarm.** Only notification-tap
  paths were handled; launching from the plain launcher icon (cold start) or
  resuming an already-running process that was showing something else (warm)
  both fell through to the normal home screen. Fixed with
  `AlarmRingService.isRinging()`/`currentAlarmId()`, checked from `main.dart`
  at cold start (after the existing notification-tap checks come up empty)
  and from a lifecycle observer in `MotionAlarmApp` on every
  `AppLifecycleState.resumed` (guarded by the `isAlarmFlowActive` flag, set
  in `AlarmRingScreen.initState` and cleared only by `WorkoutScreen`'s shared
  `_exitToHome`, so an already-showing alarm flow is never pushed twice).
  Note the scope of this fix: it always routes back to `AlarmRingScreen`
  first (matching the existing notification-tap behavior), never directly
  to a resumed `WorkoutScreen` — if the user had already tapped "Egzersize
  Başla", they see one extra tap to re-enter the (already-progress-persisted)
  workout, and the alarm briefly returns to full volume/vibration until they
  do (see the vibration fix below). Tightening this further wasn't in scope.
- **Wrong time displayed.** `AlarmRingScreen` showed the live ticking clock;
  it now looks up the matching `Alarm` and shows its scheduled hour/minute
  instead (falling back to the current time only for the dev test-alarm's
  synthetic payload, which has no fixed schedule).
- **Notification was dismissible.** Researched current behavior: Android 14+
  lets users dismiss a foreground service's notification regardless of
  `setOngoing(true)` — that guarantee is gone as of API 34. **The actual
  guarantee here is repost-on-dismiss, not non-dismissibility**: the
  notification carries a `deleteIntent` that immediately rebuilds it if
  swiped away, so it reappears within a fraction of a second rather than
  staying gone. Dismissing it never touches the running ring either way —
  sound/vibration are only ever stopped by `stopRinging()`
  (completion/emergency exit) or process death, never by notification
  lifecycle.
- **Vibration wasn't working.** The service took over sound but the
  vibration loop had no explicit `VibrationAttributes` tag, unlike the sound
  (which is correctly tagged `USAGE_ALARM`) — an untagged vibration call can
  be silently suppressed by OEM per-category vibration settings (Samsung's
  separate ringtone/notification/touch toggles, for instance). Fixed by
  tagging it `VibrationAttributes.USAGE_ALARM` (API 33+) for the same reason
  the audio is tagged `USAGE_ALARM`. Also implemented the required state
  machine explicitly rather than the old one-way stop:
  `AlarmRingService.setExerciseActive(active, fraction)` — `active: true`
  (exercise/camera on screen) lowers volume and stops vibration so the
  single vibration motor is free for per-rep haptic feedback; `active: false`
  restores full volume and resumes the alarm vibration loop.
  `AlarmRingScreen` calls this with `false` every time it's shown, which
  doubles as the "resume alarm vibration if the workout was
  abandoned/interrupted" behavior without needing a separate code path.

## Privacy statement (for store listing & README)

All camera processing happens on-device. No image, video, or body-pose data is
stored or transmitted. The camera is used only to count exercise repetitions while
an alarm is active (or in practice mode).

## Coding conventions

- English identifiers. User-facing strings in **Turkish**, centralized in one
  place for future localization.
- Small files, single responsibility. No business logic inside widgets.
- Every detection-affecting magic number goes in `core/config.dart` with a comment.
