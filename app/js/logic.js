// Pure, side-effect-free logic: time maths, diary metrics, sleep-window titration,
// schedule, ISI scoring and weekly stats. Imported by the UI and by the Node tests.

export const MIN_WINDOW = 5 * 60;
export const DEFAULT_CAFFEINE_OFFSET_H = 8;
const DAY = 1440;

// ---------- time helpers ----------

/** "HH:MM" -> minutes since midnight */
export function toMins(hhmm) {
  if (typeof hhmm !== 'string' || !/^\d{1,2}:\d{2}$/.test(hhmm)) return null;
  const [h, m] = hhmm.split(':').map(Number);
  if (h > 23 || m > 59) return null;
  return h * 60 + m;
}

/** minutes (any integer) -> "HH:MM", wrapped to a 24h clock */
export function toHHMM(mins) {
  const m = ((Math.round(mins) % DAY) + DAY) % DAY;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

/** "HH:MM" -> minutes since the previous noon, so a night (e.g. 22:00 -> 07:00) is monotonic. */
export function nightMins(hhmm) {
  const m = toMins(hhmm);
  return m == null ? null : (m - 720 + DAY) % DAY;
}

export function fmtDuration(mins) {
  if (mins == null || Number.isNaN(mins)) return '–';
  const sign = mins < 0 ? '−' : '';
  const a = Math.abs(Math.round(mins));
  const h = Math.floor(a / 60);
  const m = a % 60;
  if (!h) return `${sign}${m}m`;
  return m ? `${sign}${h}h ${m}m` : `${sign}${h}h`;
}

/** 12h display for humans: "10:45 pm" */
export function fmtClock(minsOrHHMM) {
  const m = typeof minsOrHHMM === 'string' ? toMins(minsOrHHMM) : ((minsOrHHMM % DAY) + DAY) % DAY;
  if (m == null) return '–';
  const h24 = Math.floor(m / 60);
  const mm = String(m % 60).padStart(2, '0');
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  return `${h12}:${mm} ${h24 < 12 ? 'am' : 'pm'}`;
}

export const roundUp15 = (m) => Math.ceil(m / 15) * 15;
export const roundDown15 = (m) => Math.floor(m / 15) * 15;

// ---------- dates (local, YYYY-MM-DD) ----------

export function isoDate(d = new Date()) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export function addDays(iso, n) {
  const [y, mo, d] = iso.split('-').map(Number);
  const dt = new Date(y, mo - 1, d + n);
  return isoDate(dt);
}

export function daysBetween(fromIso, toIso) {
  const [y1, m1, d1] = fromIso.split('-').map(Number);
  const [y2, m2, d2] = toIso.split('-').map(Number);
  return Math.round((Date.UTC(y2, m2 - 1, d2) - Date.UTC(y1, m1 - 1, d1)) / 86400000);
}

export function weekday(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).getDay();
}

// ---------- diary metrics (Consensus Sleep Diary) ----------

/**
 * entry: { intoBed, lightsOut, onsetMins, wakings, wasoMins, finalWake, outOfBed, quality }
 * Returns { tib, tst, se, sol, waso, earlyMins } in minutes / ratio, or null if times are unusable.
 */
export function diaryMetrics(entry) {
  const inBed = nightMins(entry.intoBed);
  const lightsOut = nightMins(entry.lightsOut ?? entry.intoBed);
  const finalWake = nightMins(entry.finalWake);
  const out = nightMins(entry.outOfBed ?? entry.finalWake);
  if ([inBed, lightsOut, finalWake, out].some((v) => v == null)) return null;
  if (!(inBed <= lightsOut && lightsOut <= finalWake && finalWake <= out)) return null;
  const tib = out - inBed;
  if (tib <= 0) return null;
  const sol = Math.max(0, Number(entry.onsetMins) || 0);
  const waso = Math.max(0, Number(entry.wasoMins) || 0);
  const tst = Math.max(0, finalWake - lightsOut - sol - waso);
  return {
    tib,
    tst,
    se: tst / tib,
    sol,
    waso,
    earlyMins: out - finalWake,
    preSleepMins: lightsOut - inBed,
  };
}

// ---------- stats ----------

export const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);

export function sd(xs) {
  if (xs.length < 2) return null;
  const mu = mean(xs);
  return Math.sqrt(xs.reduce((a, x) => a + (x - mu) ** 2, 0) / (xs.length - 1));
}

/** Circular-safe SD for clock times around a morning anchor: uses nightMins so 23:50/00:10 don't explode. */
export function timeSD(hhmms) {
  const ms = hhmms.map(nightMins).filter((v) => v != null);
  return sd(ms);
}

/**
 * Summarise diary entries (array of {date, ...entry}) for dates in [fromIso, toIso].
 */
export function summarise(entries, fromIso, toIso) {
  const inRange = entries.filter((e) => e.date >= fromIso && e.date <= toIso);
  const rows = inRange.map((e) => ({ e, m: diaryMetrics(e) })).filter((r) => r.m);
  const pick = (k) => rows.map((r) => r.m[k]);
  return {
    nights: rows.length,
    tib: mean(pick('tib')),
    tst: mean(pick('tst')),
    se: mean(pick('se')),
    sol: mean(pick('sol')),
    waso: mean(pick('waso')),
    quality: mean(rows.map((r) => Number(r.e.quality)).filter((q) => q > 0)),
    riseSD: timeSD(rows.map((r) => r.e.outOfBed)),
    riseTimes: rows.map((r) => r.e.outOfBed),
  };
}

// ---------- sleep window ----------

/**
 * Initial sleep window from baseline.
 * Standard sleep restriction: window = mean TST (rounded up to 15), floor 5h.
 * Gentle (sleep compression): start 30 min below mean time-in-bed, never below mean TST or floor.
 */
export function initialWindow({ meanTST, meanTIB, gentle = false, floor = MIN_WINDOW }) {
  const tst = roundUp15(meanTST);
  if (!gentle) return Math.max(floor, tst);
  return Math.max(floor, tst, roundDown15(meanTIB - 30));
}

/**
 * Weekly titration decision.
 * SE >= 90%: +15 min. SE < 85%: shrink (standard: to mean TST or −15, whichever is smaller;
 * gentle: −30 but not below mean TST). 85–89%: hold. Never below floor.
 * Returns { window, change, action, reason }.
 */
export function titrate({ window, meanSE, meanTST, nights, gentle = false, floor = MIN_WINDOW, minNights = 5 }) {
  if (nights < minNights || meanSE == null) {
    return {
      window,
      change: 0,
      action: 'hold',
      reason: `Only ${nights} night${nights === 1 ? '' : 's'} logged this week, so there isn't enough data to change your window. Holding steady.`,
    };
  }
  const pct = Math.round(meanSE * 100);
  let next = window;
  let action = 'hold';
  let reason;
  if (meanSE >= 0.9) {
    next = window + 15;
    action = 'expand';
    reason = `Sleep efficiency ${pct}% (≥ 90%). Your sleep is consolidating, so you've earned 15 more minutes.`;
  } else if (meanSE < 0.85) {
    const tst = roundUp15(meanTST);
    next = gentle ? Math.max(tst, window - 30) : Math.min(window - 15, tst);
    next = Math.max(floor, next);
    action = next < window ? 'shrink' : 'hold';
    reason =
      next < window
        ? `Sleep efficiency ${pct}% (< 85%). You're still spending a lot of the window awake, so we'll tighten it to build sleep pressure.`
        : `Sleep efficiency ${pct}% (< 85%), but you're already at the ${fmtDuration(floor)} floor. Holding. Stick with the bed rules.`;
  } else {
    reason = `Sleep efficiency ${pct}% (85–89%). That's the sweet spot, so we'll hold the window.`;
  }
  return { window: next, change: next - window, action, reason };
}

// ---------- daily schedule ----------

/**
 * Times (minutes since midnight) for the day's anchors. bedtime is derived from wake anchor − window,
 * or from the user's usual bedtime during baseline.
 */
export function schedule({ wakeAnchor, windowMins, usualBedtime, caffeineOffsetH = DEFAULT_CAFFEINE_OFFSET_H }) {
  const wake = toMins(wakeAnchor);
  const bed = windowMins ? wake - windowMins : toMins(usualBedtime ?? '23:00');
  const wrap = (m) => ((m % DAY) + DAY) % DAY;
  return {
    wake: wrap(wake),
    diary: wrap(wake + 5),
    light: wrap(wake + 30),
    caffeine: wrap(bed - caffeineOffsetH * 60),
    worry: wrap(bed - 180),
    windDown: wrap(bed - 60),
    bedtime: wrap(bed),
  };
}

// ---------- ISI ----------

export function isiTotal(items) {
  return items.reduce((a, b) => a + (Number(b) || 0), 0);
}

export function isiBand(total) {
  if (total <= 7) return { label: 'No clinically significant insomnia', key: 'none' };
  if (total <= 14) return { label: 'Subthreshold insomnia', key: 'sub' };
  if (total <= 21) return { label: 'Moderate clinical insomnia', key: 'mod' };
  return { label: 'Severe clinical insomnia', key: 'sev' };
}

// ---------- program state ----------

/**
 * Where am I in the program?
 * state: { startDate, windows: [{effectiveFrom, windowMins}] }
 */
export function programStatus(state, entries, todayIso) {
  const windows = state.windows ?? [];
  if (!windows.length) {
    const day = daysBetween(state.startDate, todayIso);
    const logged = entries.filter((e) => e.date > state.startDate && e.date <= todayIso).length;
    const ready = logged >= 7 || (logged >= 5 && day >= 7);
    return { phase: 'baseline', week: 0, day, logged, ready };
  }
  const first = windows[0];
  const last = windows[windows.length - 1];
  const week = Math.floor(daysBetween(first.effectiveFrom, todayIso) / 7) + 1;
  const sinceChange = daysBetween(last.effectiveFrom, todayIso);
  return {
    phase: week > 6 ? 'maintenance' : 'active',
    week,
    window: last.windowMins,
    sinceChange,
    reviewDue: sinceChange >= 7,
  };
}

export function isiDue(isiResults, todayIso) {
  if (!isiResults.length) return true;
  const last = isiResults[isiResults.length - 1];
  return daysBetween(last.date, todayIso) >= 14;
}

// ---------- n-of-1 comparisons ----------

/**
 * Compare sleep onset on nights with vs without a factor. predicate(entry) -> true/false/null (null = unknown).
 * Requires >= minN per side. Returns null when not enough data.
 */
export function compare(entries, predicate, metric = 'sol', minN = 5) {
  const yes = [];
  const no = [];
  for (const e of entries) {
    const m = diaryMetrics(e);
    if (!m) continue;
    const p = predicate(e);
    if (p === true) yes.push(m[metric]);
    else if (p === false) no.push(m[metric]);
  }
  if (yes.length < minN || no.length < minN) return { enough: false, nYes: yes.length, nNo: no.length };
  return { enough: true, nYes: yes.length, nNo: no.length, yes: mean(yes), no: mean(no) };
}
