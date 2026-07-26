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
- When the exercise starts, the alarm's own ringing sound/vibration MUST STOP so
  it does not collide with rep feedback.

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

## Privacy statement (for store listing & README)

All camera processing happens on-device. No image, video, or body-pose data is
stored or transmitted. The camera is used only to count exercise repetitions while
an alarm is active (or in practice mode).

## Coding conventions

- English identifiers. User-facing strings in **Turkish**, centralized in one
  place for future localization.
- Small files, single responsibility. No business logic inside widgets.
- Every detection-affecting magic number goes in `core/config.dart` with a comment.
