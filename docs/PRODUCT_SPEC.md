# Sleep App: Product Spec (v0)

A personal, iPhone-first **digital CBT-I coach**. The evidence base is in [RESEARCH.md](./RESEARCH.md).

## Design principles

1. **Treatment first, tracking second.** Every feature has to serve one of the three loops: conditioned arousal, sleep anxiety, or body clock.
2. **Calm by design.** No nightly score, no clock on night screens, weekly trends only. The app must not become another source of sleep anxiety.
3. **30 seconds a day.** The morning diary has to be faster than checking a notification feed, or it won't survive week 3.
4. **Explain the hard parts.** Sleep restriction feels backwards, so each rule comes with a one-line "why".
5. **The diary is the source of truth.** It's the clinical standard, and an iPhone alone can't measure sleep.

---

## Pain point → feature map

| My pain point | Feature | Evidence hook |
|---|---|---|
| Takes ~1 hr to fall asleep | **Sleep Window** (restriction engine) + **"Only when sleepy"** bedtime prompt | Sleep restriction, stimulus control |
| Podcast in bed for an hour | **Wind-down chair routine** + optional **audio experiment** (timer-capped, tracked) | Stimulus control; podcast data is weak |
| Wake 1–2× and lie there | **Night Mode "Can't sleep" button**: no clock; guides get-up / come-back, cognitive shuffle, PMR | Quarter-hour rule, SDI, PMR |
| Racing thoughts | **Evening Worry Time** (constructive worry) + **5-min To-Do Offload** before wind-down | Constructive worry RCT, Scullin 2018 |
| Anxiety about sleep | **Sleep Beliefs** lessons, **Paradoxical Intention** mode, "One bad night" reframe card | Cognitive therapy, PI trials |
| Physically restless | **PMR** and **slow-breathing** guided audio (works in Night Mode) | PMR meta-analysis |
| Wake time all over the place, body clock off | **Wake Anchor** (one fixed wake time, 7 days) + **Morning Light check-in** + streak | Circadian / SRI evidence |
| Late caffeine (unknown) | **Caffeine cutoff** nudge = target bedtime − 8 h | Drake 2013 |
| "Is anything working?" | **Weekly Review**: SE, sleep onset, wake time in the night, wake-time regularity, ISI every 2 weeks | Consensus Sleep Diary, ISI |

---

## The program (6 weeks + maintenance)

| Week | Unlocks | My job that week |
|---|---|---|
| **0 (Baseline, 7 days)** | Diary, ISI, Wake Anchor, Morning Light, Caffeine cutoff, Worry Time | Log every morning. Hold the same wake time. Get outside within 30 min of waking. Podcast moves to the chair. |
| **1 (Sleep Window)** | Sleep window set from baseline; stimulus control rules; Night Mode | Bed only when sleepy and not before window start. Up at the anchor no matter what. No naps. |
| **2 (Quiet the mind)** | Cognitive shuffle, To-Do Offload, first weekly titration | Worry Time daily; shuffle in bed if thoughts race |
| **3 (Calm the body)** | PMR, slow breathing, ISI #2 | Practise PMR in the evening (not just at 2 am) |
| **4 (Sleep beliefs)** | Beliefs lessons, Paradoxical Intention | Try PI on 3 nights |
| **5 (Fine-tune)** | Experiments (e.g. podcast vs no podcast), ISI #3 | Run one experiment |
| **6 (Relapse-proof)** | "My sleep plan" summary, maintenance mode | Keep anchor + diary 3×/week |

Titration runs automatically every 7 days from week 1 onward (algorithm below).

---

## Core logic

### Sleep efficiency and titration

```
per night:
  TIB  = out_of_bed_time - into_bed_time
  TST  = TIB - sleep_onset_latency - wake_after_sleep_onset - (out_of_bed_time - final_wake_time)
  SE   = TST / TIB

weekly (needs >= 5 logged nights in the last 7):
  meanSE, meanTST = averages over the logged nights
  if meanSE >= 0.90: window += 15 min
  elif meanSE < 0.85: window = max(5h, min(window - 15 min, meanTST))
  else: hold
  bedtime = wake_anchor - window
```

- **Floor:** 5 h 00 m (configurable upward, never below 5 h).
- **Gentle mode (sleep compression):** shrink the window by 30 min/week toward mean TST instead of jumping straight there.
- **Missing data:** fewer than 5 nights logged means hold and nudge, never titrate on thin data.

### Night Mode ("Can't sleep")

- Pure black background, red/amber text, minimum brightness, **no time displayed anywhere**.
- Flow: *"Do you feel like you've been awake a while?"* → **Yes**: "Get up, go to the chair, dim light, do something calm. Come back when sleepy." Offers PMR, slow breathing, or boring audio. → **Not yet**: cognitive shuffle (word prompt + letter-by-letter cues, voice or text), or Paradoxical Intention script.
- Logs that a night waking happened (count only, no timestamps shown) to prefill the morning diary.

### Nudges (all local notifications, all relative to wake anchor and window)

| When | Nudge |
|---|---|
| Wake anchor | Alarm-style: "Up now. Light within 30 min." |
| Anchor + 5 min | 30-sec diary |
| Anchor + 45 min | "Got outside light?" (one tap) |
| Bedtime − 8 h | Caffeine cutoff |
| Bedtime − 3 h | Worry Time (15 min, out of the bedroom) |
| Bedtime − 60 min | Wind down: dim lights, Focus mode on, podcast in the chair, To-Do Offload |
| Bedtime | "Window opens. Bed only if sleepy." |
| Sunday | Weekly review + new window |

Nudges can be snoozed but never bunched, and they go quiet automatically in maintenance mode.

### Weekly Review (the only "insights" surface)

- Mean SE, sleep onset, time awake in the night, and TST, as 7-day averages with a tiny trend line.
- **Wake-time regularity** (± minutes SD) and anchor-hit streak.
- Adherence: diary %, morning light %, Worry Time %.
- **ISI** every 2 weeks with bands, and celebration at a ≥ 6-point drop.
- Simple n-of-1 comparisons (e.g. "nights with Worry Time: onset 22 min vs 41 min"). Shown only once n ≥ 5 per side, and phrased as a hint rather than proof.

---

## Data model (local-first)

```
DiaryEntry   { date, intoBed, triedToSleep, onsetMins, wakings, wasoMins, finalWake, outOfBed,
               quality(1-5), caffeineLast?, napMins?, alcohol?, audioInBed?, morningLight?, worryTimeDone?, note? }
ISIResult    { date, items[7], total }
SleepWindow  { effectiveFrom, wakeAnchor, windowMins, reason }
NightEvent   { date, kind: canSleep|tool_used, tool? }   // no timestamps surfaced in UI
Settings     { wakeAnchor, floorMins, gentleMode, caffeineOffsetH, notifications{} }
```

Everything stays on-device by default, with optional iCloud/export. There's no account and no analytics.

---

## Explicitly *not* building (v0)

- A nightly sleep score or hypnogram, because of orthosomnia risk.
- Phone-on-mattress movement tracking, which is inaccurate and keeps the phone in bed.
- A sound/story library. Link to existing ones; ours just needs a few guided scripts (PMR, breathing, shuffle).
- Social or streak shaming.

## Safety copy (shown at onboarding and at window start)

- Expect extra sleepiness for 1–2 weeks. **Don't drive when drowsy.**
- Stop and see a GP if you develop loud snoring or gasping, leg-crawling urges, sudden sleep attacks, low mood or thoughts of self-harm, or if ISI stays ≥ 15 after 8 weeks.
- Not for unsupervised use with bipolar disorder, epilepsy, or pregnancy. Use gentle mode and talk to a doctor.

---

## Open decision: how to build it

| Option | Pros | Cons |
|---|---|---|
| **A. Native SwiftUI app** | Reliable local notifications and alarms, HealthKit, Focus/Shortcuts, widgets, best Night Mode | Needs a Mac + Xcode; a free Apple ID sideload expires every 7 days (or $149 AUD/yr dev account) |
| **B. PWA (installable web app)** | Can be built and tested end to end here; works on iPhone home screen; zero install friction | iOS web push needs a server for scheduled reminders; no HealthKit; less alarm-like |
| **C. PWA + Apple Shortcuts / Reminders for nudges** | Gets reliable phone nudges without a server or Mac | Nudges live outside the app and are set up once by hand |

**Recommendation:** start with **C** to get the program running *this week*. The treatment works with a diary and a schedule, so it doesn't need to wait on platform work. Port to **A** later if it sticks.
