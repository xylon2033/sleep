# Sleep

A personal, Sleep Cycle–style iPhone app (iOS 26, SwiftUI) built from the research brief. Features are ranked by how good the evidence behind them is:

- **Schedule and coaching (strong evidence).** A fixed wake time seven days a week. Bedtime is coached towards *wake − goal* in 15‑minute steps. Wind‑down, caffeine‑cutoff, bedtime and morning‑light nudges are local notifications.
- **Regularity metrics (strong evidence).** Sleep Regularity Index (Phillips et al.) and social jetlag (Wittmann/Roenneberg) are the headline numbers. Alongside them: bed/wake time spread, sleep debt and an on‑schedule streak.
- **Journal and tag effects (sound n‑of‑1 statistics).** One‑tap evening tags and a morning check‑in that takes under 15 s. Tag effects are only computed once a tag has at least 5 nights with it and 5 without, and are flagged provisional below 10 of each. Comparisons are stratified by work/free day, carry bootstrap 95% CIs and are corrected with Benjamini–Hochberg FDR. Results are ranked by effect size, not p‑value. There's also an alternating‑week **experiment** mode.
- **Reliable alarm.** AlarmKit, which rings through Silent and Focus, with a melodic bundled sound and snooze.
- **Overnight listening (weak evidence: event detection only).** The microphone gives a movement/sound activity index per 30 s epoch, plus snore, talk and cough events from Apple's built‑in SoundAnalysis classifier. "Light/deep" are labelled *estimated* everywhere and are never written to Health as stages.
- **Gentle wake window (phase 2).** A hybrid design. While a night is tracked, an AlarmKit **backstop** is set for the end of the window. If you're stirring inside the window ("2 of the last 3 epochs active"), an in‑app melody fades in over 90 s. Stopping it cancels the backstop; ignoring it means the system alarm still rings.
- **Sleep sounds.** White, pink, brown, rain and waves, all generated in code (no assets). Volume is capped. The default is a 45‑min fade‑out timer, with "all night (masking)" as an explicit opt‑in, because of the 2026 pink‑noise/REM finding.
- **Also included.** Apple Health export (`inBed` + `asleepUnspecified`/`awake` only), Shortcuts ("Start Night", "Log Sleep Tag"), CSV/JSON export, optional snore/talk clips (off by default, max 5 per night, deleted after 30 days), and a Live Activity for the snooze countdown.

Not built: Spotify (see below), Home Screen widgets beyond the alarm Live Activity, a custom Create ML model.

## Project layout

```
Sleep.xcodeproj            Xcode project (synchronized folders: new files are picked up automatically)
Config/Base.xcconfig       ← set BUNDLE_ID_PREFIX (and optionally DEVELOPMENT_TEAM) here
Sleep/                     App target
  App/                     Entry point, root tabs, router
  Audio/                   NightRecorder (AVAudioEngine), FrameAnalyzer (vDSP), NoiseGenerator,
                           SoundEventDetector (SoundAnalysis), GentleAlarmPlayer
  Night/NightSession.swift Start Night → heartbeat/interruptions → smart wake → End Night
  Services/                AlarmService (AlarmKit), ReminderService, HealthService, Exporter
  Models/                  SwiftData records, settings, analytics glue
  Views/                   Tonight, night mode, morning report, nights, trends, insights, settings
  Intents/                 App Intents + Shortcuts
Shared/                    AlarmKit metadata (compiled into app and widget)
SleepWidgets/              Widget extension: AlarmKit Live Activity
Packages/SleepCore/        Pure‑Swift logic + tests (runs on macOS and Linux)
tools/                     Scripts that generated the alarm sound and app icon
```

`SleepCore` contains everything that can be tested without a phone: the adaptive noise floor, 30 s epoch features, the sleep/wake estimator (smoothing → 2‑state HMM → onset/final‑wake rules), SRI, social jetlag, coaching, the reminder plan, tag‑effect statistics, experiments, and the compact epoch codec (~23 bytes per epoch).

## Build and run on your iPhone

1. Xcode 26+ on a Mac, and an iPhone on iOS 26+.
2. Edit `Config/Base.xcconfig` and set `BUNDLE_ID_PREFIX` to something unique (e.g. `com.yourname`).
3. Open `Sleep.xcodeproj`. In **Signing & Capabilities**, pick your team for both the **Sleep** and **SleepWidgetsExtension** targets.
4. Select your iPhone and press Run.

**Use a paid Apple Developer account if you'll rely on the alarm.** With a free account the provisioning profile expires after 7 days, and the app (and its alarm) stops launching until you rebuild. If your free team rejects the HealthKit capability, delete the two HealthKit keys from `Config/Sleep.entitlements`; Health export then simply stays off.

Run the logic tests with `cd Packages/SleepCore && swift test`. CI (`.github/workflows/ci.yml`) runs them on Linux and builds the full app for the simulator with Xcode 26.

## How to use it

1. In **Settings**, set your wake time and sleep goal. The same wake time every day is the anchor.
2. In the evening, tap tags on **Tonight** (or use the "Log Sleep Tag" shortcut).
3. At bedtime, plug the phone in, put it on the nightstand, tap **Start Night**, then lock the phone. Recording has to start in the foreground: iOS won't let an app start the microphone from the background. The "Start Night" shortcut opens the app for this reason.
4. In the morning, stop the alarm. If you stop the AlarmKit alarm, the night ends by itself. You can also tap **I'm up** or **End Night**. Then do the 15‑second check‑in.
5. After a week, **Trends** shows SRI and social jetlag. After a few weeks of tagging, **Insights** starts showing tag effects.

## Known limitations and things to verify on your device

- **Accuracy.** Phone audio tracking estimates time in bed reasonably well. It doesn't estimate sleep stages, and this algorithm is simpler than Sleep Cycle's. Use it for trends in your own data. Detection sensitivity is adjustable in Settings.
- **Interruptions.** Calls, Siri or another app taking the microphone pause recording. The app retries automatically, logs a heartbeat every minute, and shows gaps honestly in the morning report. If the app was killed, it offers **Resume** or **End** the next time you open it.
- **AlarmKit behaviours come from developer forum reports.** Custom sounds stop at ~30 s, don't loop, and play at ringer volume. The volume buttons dismiss the alarm. The bundled sound has its own crescendo for this reason. Set your ringer volume deliberately. Auto‑ending the night when you stop the system alarm relies on `alarmUpdates` while the app is alive in the background. Test this on your iOS build.
- **Background rescheduling** of AlarmKit alarms while the audio session keeps the app alive is undocumented. The smart wake doesn't depend on it: it plays in‑app audio and only *cancels* the backstop.
- **Spotify** isn't integrated. The audio session mixes with other apps, so Spotify can play while the app listens. Spotify's own sleep timer is the simplest option; the brief explains why App Remote is fragile overnight.
- **Battery.** Keep the phone on the charger. The app warns you when it isn't plugged in.
- **Not a medical device.** Loud, frequent snoring with daytime sleepiness is a reason to get a sleep‑apnea evaluation. This app can prompt one; it can't rule apnea out.
