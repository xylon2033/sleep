# Sleep Research Brief

What the evidence says about fixing *my* sleep, and what an app can realistically do about it.

## 1. My sleep profile (from intake, 2026-10-05)

| Dimension | Answer | Clinical read |
|---|---|---|
| Pattern | 30+ min (often ~1 hr) to fall asleep, with a podcast; wake 1–2× a night for a while | **Sleep-onset + sleep-maintenance insomnia** |
| What's happening while awake | Racing thoughts, anxiety about sleep, physically restless | **Hyperarousal**: cognitive, somatic, and sleep-related performance anxiety |
| Schedule | Wake time inconsistent; morning routine skipped; bedtime "just drifts" | **Circadian misalignment / irregular sleep–wake timing** |
| Duration | 3–12 months | Meets the ≥3-month threshold for **chronic insomnia disorder** |
| Red flags (snoring/gasping, restless legs, sleep attacks) | None | No obvious signal for apnea, RLS or narcolepsy, so behavioural treatment is the right first line |
| Device | iPhone, no wearable | Diary-based tracking (which is the clinical standard anyway) |
| Wants from an app | Structured program, tracking & insights, nudges & reminders | Fits a **digital CBT-I** design |

**Bottom line:** this is textbook chronic insomnia held in place by three loops:

1. **Conditioned arousal.** An hour awake in bed (podcast on, thoughts racing) teaches the brain that bed is a place for being awake.
2. **Sleep effort and anxiety.** Trying hard to sleep and worrying about not sleeping raises arousal, which makes sleep less likely.
3. **A weak body clock.** A shifting wake time and no morning anchor mean sleep pressure and circadian timing don't line up at bedtime.

The good news is that the first-line treatment for all three is the same, it's behavioural, and it can be delivered by an app.

---

## 2. The evidence hierarchy

### 2.1 CBT-I is the first-line treatment, ahead of sleep hygiene and ahead of pills

- The **American Academy of Sleep Medicine (AASM) 2021 guideline** gives its only **strong** recommendation to multicomponent **CBT-I** for chronic insomnia. It gives **conditional** recommendations to stimulus control alone, sleep restriction alone, relaxation, and brief behavioural therapy. It recommends **against sleep hygiene as a stand-alone treatment**. ([AASM](https://aasm.org/new-guideline-supports-behavioral-psychological-treatments-for-insomnia/), [AAFP summary](https://www.aafp.org/pubs/afp/issues/2022/0100/p97.html))
- **Digital CBT-I works.** A meta-analysis of 49 RCTs (n = 20,118) found that fully automated dCBT-I significantly reduces insomnia severity. Its effects were comparable to active/therapist controls, with about **15.5 min faster sleep onset** and about **+7.9 % sleep efficiency** vs inactive controls. Therapist-supported or hybrid versions do somewhat better than fully automated ones. ([npj Digit Med / PMC](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12731755/), [IJPS meta-analysis](https://publish.kne-publishing.com/index.php/IJPS/article/view/19689))
- Of the CBT-I smartphone apps studied, **CBT-i Coach** and **Insomnia Coach** (both US VA) had the strongest evidence. Their feature sets are a good reference design. ([dCBT-I app review](https://doaj.org/article/3799fbd4355743ee86834558021ab652))

**Implication:** the app's core has to be CBT-I: a sleep diary, a sleep window (restriction/compression), stimulus control, and cognitive work. Hygiene tips, sounds and trackers are supporting extras.

### 2.2 The components, and which loop each one targets

| Component | What it is | Targets | Evidence |
|---|---|---|---|
| **Sleep restriction / compression** | Limit time in bed to roughly actual sleep time, then expand weekly as sleep efficiency rises | Weak sleep drive, long time awake in bed, night wakings | AASM conditional (standalone), core of CBT-I |
| **Stimulus control** | Bed only for sleep; go to bed only when *sleepy*; if awake about 15–20 min, get up and come back when sleepy; **fixed wake time 7 days/week**; no naps | Conditioned arousal | AASM conditional (standalone) |
| **Cognitive therapy** | Challenge catastrophic beliefs ("if I don't sleep I'll fail tomorrow"), decatastrophise one bad night | Sleep anxiety | Part of CBT-I |
| **Paradoxical intention** | Lie in bed and gently try to *stay awake*, which removes performance pressure | Sleep effort / anxiety | RCTs show reduced sleep effort and performance anxiety ([Espie, Penn CBT-I](https://www.med.upenn.edu/cbti/assets/user-content/documents/Espie_ParadoxicalIntentionTherapy-BTSD.pdf), [UEA meta-analysis on sleep effort](https://ueaeprints.uea.ac.uk/id/eprint/97547/)) |
| **Constructive worry / "worry time"** | 15 min in the early evening: write worries and a next step for each, then close the book | Racing thoughts | Lower pre-sleep cognitive arousal vs controls ([ANZCTR trial](https://anzctr.org.au/ACTRN12615000061538.aspx)) |
| **To-do list offload** | 5 min before bed: write a *specific* to-do list for the next few days | Racing thoughts | Fell asleep about 9 min faster (about 15 min with very specific lists) vs journaling completed tasks, n = 57 ([Baylor / Scullin 2018](https://news.web.baylor.edu/news/story/2018/can-writing-your-dos-help-you-doze-baylor-study-suggests-jotting-down-tasks-can)) |
| **Cognitive shuffle (serial diverse imagining)** | In bed: pick a word, imagine a random object for each letter | Racing thoughts *in bed* | RCT (n = 154 students) found it as effective as standard treatment for pre-sleep arousal and sleep effort, and it can be done lying down ([SFU, Beaudoin et al.](https://summit.sfu.ca/item/15270), [Sleep Review](https://sleepreviewmag.com/sleep-health/parameters/quality/need-better-sleep-consider-cognitive-shuffle/)) |
| **Progressive muscle relaxation / slow breathing** | Tense–release muscle groups; slow paced breathing | Physical restlessness | Meta-analysis of 31 RCTs: PSQI −3.79 ([Lichstein, Penn CBT-I](https://www.med.upenn.edu/cbti/assets/user-content/documents/Lichstein_RelaxationforInsomnia-BTSD.pdf), [PMR systematic review](https://jdk.ulm.ac.id/index.php/jdk/article/view/253)) |
| **Circadian anchoring** | Same wake time every day plus outdoor morning light soon after waking; dim evenings | Body clock drift | Morning bright light phase-advances the clock and improved sleep onset in insomnia trials ([PMC3176957](https://pmc.ncbi.nlm.nih.gov/articles/PMC3176957), [PMC4344919](https://pmc.ncbi.nlm.nih.gov/articles/PMC4344919/)) |

### 2.3 Sleep restriction: the actual algorithm

This is the engine of the program, and it's the part people find hardest to follow.

1. Keep a diary for 7–14 days. Compute **mean total sleep time (TST)** and **sleep efficiency (SE = TST ÷ time in bed)**.
2. **Fix the wake time** (pick one you can hold 7 days a week).
3. **Sleep window = mean TST, never below 5 h.** Bedtime = wake time − window.
4. Each week, using the 7-day mean SE:
   - **SE ≥ 90 %**: add 15 min (move bedtime earlier)
   - **SE 85–89 %**: hold
   - **SE < 85 %**: reduce the window to mean TST (or −15 min), keeping the 5 h floor
5. Stop expanding when SE stays around 85–90 % and daytime functioning is good. That's your "core sleep need".

Sources: [Penn CBT-I standard protocol (Muench)](https://www.med.upenn.edu/cbti/assets/user-content/uploads/MUENCH%20Chapter%20-%20Standard%20CBT-I%20in%20Chapter%20Adapting%20CBT-I%20Book%20reduced%20.pdf), [PMC3900612](https://pmc.ncbi.nlm.nih.gov/articles/PMC3900612).

**Safety:** expect more sleepiness for the first 1–2 weeks. **Don't drive or operate machinery when drowsy.** Sleep restriction isn't appropriate unsupervised for people with bipolar disorder, seizure disorders, or jobs where sleepiness is dangerous. For them, use *sleep compression* instead (shrink the window by 15–30 min/week instead of all at once).

### 2.4 Measuring progress

- **Consensus Sleep Diary** (the research standard, 9 core items): time into bed, time trying to sleep, sleep onset latency, number of awakenings, total wake time, final wake time, out-of-bed time, quality rating, comments. Filled in each morning, from memory, with no clock-checking at night. ([Carney et al. 2012, PMC3250369](https://pmc.ncbi.nlm.nih.gov/articles/PMC3250369/))
- **Insomnia Severity Index (ISI)**: 7 items, 0–28. 0–7 none · 8–14 subthreshold · 15–21 moderate · 22–28 severe. A **≥ 6-point drop** is a clinically meaningful individual improvement. ([ISI MWIC, PMC11217251](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11217251/), [UNC ISI form](https://www.med.unc.edu/neurology/wp-content/uploads/sites/716/2018/05/Insomnia-Severity-Index.pdf))
- **Wake-time regularity**: the standard deviation of wake time. The Sleep Regularity Index literature shows that irregular timing predicts mortality **more strongly than sleep duration** does (UK Biobank). ([PMC10782501](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10782501/), [PMC10666928](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10666928/))

### 2.5 Lifestyle levers (supporting, not curative)

- **Caffeine:** 400 mg taken even **6 h before bed** cut objectively measured sleep by **more than 1 h** ([Drake 2013, AASM](https://aasm.org/late-afternoon-and-early-evening-caffeine-can-disrupt-sleep-at-night/), [PMC3805807](https://pmc.ncbi.nlm.nih.gov/articles/PMC3805807/)). Caffeine's half-life is about 5 h, so default the cutoff to 8 h before the target bedtime.
- **Naps:** avoid them while in sleep restriction, because they drain sleep pressure.
- **Evening light and screens:** dim the lights and use red/warm modes in the last hour.

### 2.6 About the podcast in bed

The evidence here is thin and mostly self-report. An Acast survey found podcast-for-sleep listeners took **about 10 min longer** to fall asleep than non-users ([Radio Ink](https://radioink.com/2023/09/05/new-study-suggests-podcasts-are-becoming-essential-to-sleep/)). A 2026 Swedish survey found audiobook users *felt* it helped ([JMIR Formative](https://formative.jmir.org/2026/1/e95064)). From a CBT-I standpoint, **engaging content plus an hour in bed awake** is the conditioned-arousal pattern to break. Options, best first:

1. Move the podcast to the **wind-down chair** before the sleep window, and get into bed only when sleepy.
2. If audio in bed stays, keep it **boring or familiar, slow-paced, on a 15–20 min sleep timer**, and treat it as a measured experiment (see the spec).

### 2.7 Pitfalls to design around

- **Orthosomnia.** Chasing a "perfect sleep score" from a tracker can *worsen* insomnia, especially in anxious or perfectionist people ([Sleep Foundation](https://www.sleepfoundation.org/sleep-disorders/orthosomnia), [Cornell](https://evidencebasedliving.human.cornell.edu/uncategorized/is-your-sleep-tracker-disrupting-your-sleep)). Since sleep anxiety is one of my drivers, the app should show **no nightly score, no clock at 2 am, and only weekly trends**.
- **Adherence.** Real-world dCBT-I loses most users before the end. Reminders, a 30-second diary, a clear weekly feedback loop and the "why" behind the hard parts improve completion. Added human coaching improved sleep-restriction adherence. ([CBT-i Coach pilot](https://experts.umn.edu/en/publications/a-randomized-controlled-pilot-study-of-cbt-i-coach-feasibility-ac/), [Henry Ford abstract](https://scholarlycommons.henryford.com/sleepmedicine_mtgabstracts/63))
- **iPhone-only data is weak.** Without a Watch, HealthKit only gets coarse "in bed" samples from the phone, inferred from phone inactivity during a scheduled sleep window ([Apple Dev Forums](https://developer.apple.com/forums/thread/726278)). So the **diary is the source of truth**, and HealthKit is at most a prefill hint.

### 2.8 Don't wait for the app

**THIS WAY UP's Insomnia Program** is a free, 4-lesson online CBT-I course for Australian residents, built by UNSW / St Vincent's ([healthdirect](https://healthdirect.gov.au/managing-insomnia-course), [Lifeline toolkit](https://toolkit.lifeline.org.au/articles/resources/insomnia-program)). A GP can also prescribe it with clinician monitoring, still free. It's worth starting **in parallel** with the app; the two reinforce each other. If ISI is still ≥ 15 after 6–8 weeks of honest effort, see a GP about a referral to a sleep psychologist.
