import * as L from './logic.js';
import * as C from './content.js';
import * as store from './store.js';

let S = store.load();
const app = document.getElementById('app');
const tabbar = document.getElementById('tabbar');

// ---------- helpers ----------

const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const today = () => L.isoDate(new Date());
const nowMins = () => {
  const d = new Date();
  return d.getHours() * 60 + d.getMinutes();
};
/** Night events belong to the morning they end on. */
const nightKey = () => (new Date().getHours() >= 12 ? L.addDays(today(), 1) : today());

function persist() {
  if (!store.save(S)) toast("Couldn't save. Storage may be full or blocked.");
}

function toast(msg) {
  const t = document.createElement('div');
  t.className = 'toast';
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 2600);
}

const entries = () => Object.entries(S.diary).map(([date, e]) => ({ date, ...e })).sort((a, b) => (a.date < b.date ? -1 : 1));
const currentWindow = () => S.windows.at(-1)?.windowMins ?? null;
const sched = () =>
  L.schedule({
    wakeAnchor: S.settings.wakeAnchor,
    windowMins: currentWindow(),
    usualBedtime: S.settings.usualBedtime,
    caffeineOffsetH: S.settings.caffeineOffsetH,
  });
const status = () => L.programStatus(S, entries(), today());
const check = (date, k) => !!S.checks[date]?.[k];
function setCheck(date, k, v) {
  S.checks[date] = { ...(S.checks[date] ?? {}), [k]: v };
  persist();
}

// timers / wake lock / speech used by night tools, cleared on every navigation
let timers = [];
let wakeLock = null;
function later(fn, ms) {
  timers.push(setTimeout(fn, ms));
}
function every(fn, ms) {
  timers.push(setInterval(fn, ms));
}
async function keepAwake(on) {
  try {
    if (on && 'wakeLock' in navigator && !wakeLock) wakeLock = await navigator.wakeLock.request('screen');
    if (!on && wakeLock) {
      await wakeLock.release();
      wakeLock = null;
    }
  } catch {
    /* unsupported or denied */
  }
}
function say(text) {
  if (!S.settings.speech || !('speechSynthesis' in window)) return;
  const u = new SpeechSynthesisUtterance(text);
  u.rate = 0.72;
  u.pitch = 0.85;
  u.volume = 0.6;
  speechSynthesis.speak(u);
}
function stopAll() {
  timers.forEach((t) => {
    clearTimeout(t);
    clearInterval(t);
  });
  timers = [];
  keepAwake(false);
  if ('speechSynthesis' in window) speechSynthesis.cancel();
}

// ---------- router ----------

const routes = {
  today: viewToday,
  diary: viewDiary,
  night: viewNight,
  worry: viewWorry,
  review: viewReview,
  learn: viewLearn,
  isi: viewISI,
  settings: viewSettings,
  reminders: viewReminders,
  onboard: viewOnboard,
};

function render() {
  stopAll();
  const [name, ...rest] = location.hash.replace(/^#\/?/, '').split('/');
  let route = name || 'today';
  if (!S.onboarded && route !== 'onboard') route = 'onboard';
  const view = routes[route] ?? viewToday;
  document.documentElement.classList.toggle('night', route === 'night');
  document.body.classList.toggle('night', route === 'night');
  tabbar.hidden = route === 'onboard' || route === 'night';
  tabbar.querySelectorAll('a').forEach((a) => a.classList.toggle('active', a.dataset.tab === route));
  app.innerHTML = view(rest);
  app.scrollTop = 0;
  window.scrollTo(0, 0);
  afterRender[route]?.(rest);
}

const afterRender = {};
const go = (hash) => {
  if (location.hash === hash) render();
  else location.hash = hash;
};

// ---------- Today ----------

function viewToday() {
  const st = status();
  const s = sched();
  const t = today();
  const focus = C.WEEK_FOCUS[Math.min(st.week, 6)];
  const cards = [];

  if (!S.diary[t]) cards.push(card('Log last night', '30 seconds. Do it before you look at anything else.', '#/diary', 'Log diary', 'primary'));
  if (L.isiDue(S.isi, t)) cards.push(card('Sleep check-in', S.isi.length ? "It's been 2 weeks. Seven quick questions to track progress." : 'Seven quick questions to get your baseline.', '#/isi', 'Start'));
  if (st.phase === 'baseline' && st.ready) cards.push(card('Baseline complete', "You've logged enough nights. Time to set your sleep window.", '#/review', 'Set my window', 'primary'));
  if (st.phase !== 'baseline' && st.reviewDue) cards.push(card('Weekly review ready', "See how the week went and get next week's window.", '#/review', 'Open review', 'primary'));
  if (currentWindow() && S.remindersWindow !== currentWindow())
    cards.push(card('Update your phone reminders', `Your window is now ${L.fmtDuration(currentWindow())}, so bedtime is ${L.fmtClock(s.bedtime)}.`, '#/reminders', 'Show me'));

  const wakeRel = (m) => (m - s.wake + 1440) % 1440;
  const nowRel = wakeRel(nowMins());
  const items = [
    { t: s.wake, label: 'Wake anchor', sub: 'Out of bed, even after a bad night' },
    { t: s.light, label: 'Morning light', sub: 'Outside 10–30 min', check: 'light' },
    { t: s.caffeine, label: 'Caffeine cutoff', sub: `${S.settings.caffeineOffsetH} h before bed` },
    { t: s.worry, label: 'Worry Time', sub: '15 min, out of the bedroom', check: 'worry', href: '#/worry' },
    { t: s.windDown, label: 'Wind down', sub: 'Dim lights · to-do offload · podcast in the chair', check: 'offload', href: '#/worry/offload' },
    {
      t: s.bedtime,
      label: currentWindow() ? 'Window opens' : 'Usual bedtime',
      sub: currentWindow() ? 'Bed only when sleepy, and not before this' : 'Baseline: go to bed when sleepy',
    },
  ];

  const timeline = items
    .map((it) => {
      const past = wakeRel(it.t) < nowRel;
      const done = it.check && check(t, it.check);
      const box = it.check
        ? `<button class="tick ${done ? 'on' : ''}" data-act="tick" data-k="${it.check}" aria-label="Mark ${esc(it.label)} done">${done ? '✓' : ''}</button>`
        : '<span class="tick placeholder"></span>';
      const label = it.href ? `<a href="${it.href}">${it.label}</a>` : it.label;
      return `<li class="${past ? 'past' : ''} ${done ? 'done' : ''}">
        <span class="time">${L.fmtClock(it.t)}</span>
        <span class="what"><b>${label}</b><small>${it.sub}</small></span>${box}</li>`;
    })
    .join('');

  const phaseLine =
    st.phase === 'baseline'
      ? `Baseline · day ${Math.max(1, st.day + 1)} · ${st.logged}/7 nights logged`
      : `${st.phase === 'maintenance' ? 'Maintenance' : `Week ${st.week} of 6`} · window ${L.fmtDuration(st.window)}`;

  return `
  <header class="top"><div><p class="eyebrow">${phaseLine}</p><h1>${focus.title}</h1></div>
    <a class="icon-btn" href="#/settings" aria-label="Settings">⚙︎</a></header>
  ${cards.join('')}
  <section class="panel"><h2>Today's plan</h2><ul class="timeline">${timeline}</ul></section>
  <section class="panel"><h2>This week</h2><ul class="tasks">${focus.tasks.map((x) => `<li>${esc(x)}</li>`).join('')}</ul>
    <div class="chips">${focus.lessons.map((id) => `<a class="chip" href="#/learn/${id}">📖 ${esc(C.LESSONS.find((l) => l.id === id)?.title)}</a>`).join('')}</div></section>
  <section class="grid2">
    <a class="tile" href="#/worry"><span>📝</span>Worry Time</a>
    <a class="tile" href="#/night"><span>🌙</span>Can't sleep</a>
    <a class="tile" href="#/learn/one-bad-night"><span>🧭</span>After a bad night</a>
    <a class="tile" href="#/reminders"><span>⏰</span>Reminders</a>
  </section>`;
}

function card(title, body, href, cta, kind = '') {
  return `<a class="card ${kind}" href="${href}"><div><b>${title}</b><p>${body}</p></div><span class="cta">${cta} →</span></a>`;
}

// ---------- Diary ----------

let diaryDate = null;

function viewDiary() {
  const t = today();
  diaryDate ??= t;
  const prev = S.diary[diaryDate];
  const last = entries().at(-1);
  const s = sched();
  const night = S.night[diaryDate];
  const def = {
    intoBed: prev?.intoBed ?? last?.intoBed ?? L.toHHMM(s.bedtime),
    lightsOut: prev?.lightsOut ?? prev?.intoBed ?? last?.lightsOut ?? L.toHHMM(s.bedtime),
    onsetMins: prev?.onsetMins ?? null,
    wakings: prev?.wakings ?? (night?.visits ? Math.min(4, night.visits) : null),
    wasoMins: prev?.wasoMins ?? null,
    finalWake: prev?.finalWake ?? S.settings.wakeAnchor,
    outOfBed: prev?.outOfBed ?? S.settings.wakeAnchor,
    quality: prev?.quality ?? null,
  };
  const dates = Array.from({ length: 7 }, (_, i) => L.addDays(t, -i));
  const dateLabel = (d) => (d === t ? 'Last night' : new Date(d + 'T12:00').toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' }) + ' (morning)');

  const chips = (name, opts, val, fmt = (v) => v) =>
    `<div class="chips pick" data-name="${name}">${opts
      .map((o) => `<button type="button" class="chip ${val === o ? 'on' : ''}" data-act="pick" data-v="${o}">${fmt(o)}</button>`)
      .join('')}</div><input type="hidden" name="${name}" value="${val ?? ''}">`;
  const tag = (name, label) =>
    `<label class="toggle"><input type="checkbox" name="${name}" ${prev?.[name] ? 'checked' : ''}><span>${label}</span></label>`;

  return `
  <header class="top"><div><p class="eyebrow">Sleep diary</p><h1>${diaryDate === t ? 'How was last night?' : 'Edit entry'}</h1></div></header>
  <p class="muted">Best guesses are fine. Don't clock-watch at night to fill this in.</p>
  <form class="panel form" data-form="diary">
    <label>Night<select name="date" data-act="diary-date">${dates.map((d) => `<option value="${d}" ${d === diaryDate ? 'selected' : ''}>${dateLabel(d)}${S.diary[d] ? ' ✓' : ''}</option>`).join('')}</select></label>
    <div class="row2">
      <label>Got into bed<input type="time" name="intoBed" value="${def.intoBed}" required></label>
      <label>Lights out / tried to sleep<input type="time" name="lightsOut" value="${def.lightsOut}" required></label>
    </div>
    <fieldset><legend>Roughly how long to fall asleep?</legend>${chips('onsetMins', [5, 15, 30, 45, 60, 90, 120], def.onsetMins, (v) => (v === 120 ? '2h+' : L.fmtDuration(v)))}</fieldset>
    <fieldset><legend>How many times did you wake up?</legend>${chips('wakings', [0, 1, 2, 3, 4], def.wakings, (v) => (v === 4 ? '4+' : v))}</fieldset>
    <fieldset><legend>Total time awake during the night</legend>${chips('wasoMins', [0, 10, 20, 30, 45, 60, 90, 120], def.wasoMins, (v) => (v === 0 ? 'None' : v === 120 ? '2h+' : L.fmtDuration(v)))}</fieldset>
    <div class="row2">
      <label>Final wake-up<input type="time" name="finalWake" value="${def.finalWake}" required></label>
      <label>Got out of bed<input type="time" name="outOfBed" value="${def.outOfBed}" required></label>
    </div>
    <fieldset><legend>Sleep quality</legend>${chips('quality', [1, 2, 3, 4, 5], def.quality, (v) => ['', 'Very poor', 'Poor', 'Fair', 'Good', 'Very good'][v])}</fieldset>
    <fieldset><legend>Tags (for experiments)</legend><div class="toggles">
      ${tag('audioInBed', '🎧 Podcast/audio in bed')}
      ${tag('caffeineLate', '☕ Caffeine after cutoff')}
      ${tag('alcohol', '🍷 Alcohol')}
      ${tag('napped', '😴 Napped yesterday')}
    </div></fieldset>
    <label>Note<textarea name="note" rows="2" placeholder="Anything notable (stress, exam, late shift…)">${esc(prev?.note ?? '')}</textarea></label>
    <button class="btn primary" type="submit">${prev ? 'Update' : 'Save'}</button>
    ${prev ? '<button class="btn ghost danger" type="button" data-act="diary-delete">Delete this entry</button>' : ''}
  </form>`;
}

function saveDiary(form) {
  const f = new FormData(form);
  const num = (k) => (f.get(k) === '' ? null : Number(f.get(k)));
  const entry = {
    intoBed: f.get('intoBed'),
    lightsOut: f.get('lightsOut'),
    onsetMins: num('onsetMins'),
    wakings: num('wakings'),
    wasoMins: num('wasoMins'),
    finalWake: f.get('finalWake'),
    outOfBed: f.get('outOfBed'),
    quality: num('quality'),
    audioInBed: f.get('audioInBed') === 'on',
    caffeineLate: f.get('caffeineLate') === 'on',
    alcohol: f.get('alcohol') === 'on',
    napped: f.get('napped') === 'on',
    note: String(f.get('note') ?? '').trim(),
  };
  for (const [k, label] of [
    ['onsetMins', 'how long it took to fall asleep'],
    ['wakings', 'how many times you woke'],
    ['wasoMins', 'time awake in the night'],
  ]) {
    if (entry[k] == null) return toast(`Pick ${label}.`);
  }
  if (!L.diaryMetrics(entry)) return toast('Those times don\'t line up. Check that bed → lights out → wake → out of bed are in order.');
  S.diary[f.get('date')] = entry;
  persist();
  toast('Saved. Trends show up in the weekly review.');
  diaryDate = null;
  go('#/today');
}

// ---------- Night mode ----------

let nightLogged = null;

function viewNight([mode]) {
  if (!mode && nightLogged !== nightKey()) {
    const k = nightKey();
    S.night[k] = { visits: (S.night[k]?.visits ?? 0) + 1, tools: S.night[k]?.tools ?? [] };
    nightLogged = k;
    persist();
  }
  if (mode) {
    const k = nightKey();
    S.night[k] = S.night[k] ?? { visits: 1, tools: [] };
    if (!S.night[k].tools.includes(mode)) S.night[k].tools.push(mode);
    persist();
  }
  const exit = `<a class="night-exit" href="#/today" data-act="night-exit">Done</a>`;
  if (mode === 'getup') {
    return `${exit}<div class="night-wrap"><h1>Get up for a bit</h1>
      <p>Go somewhere dim and do something calm and boring. Come back to bed only when you feel <b>sleepy</b>. You're not doing anything wrong; you're teaching your bed what it's for.</p>
      <ul class="night-list">${C.GET_UP_IDEAS.map((x) => `<li>${esc(x)}</li>`).join('')}</ul>
      <div class="night-actions"><a class="nbtn" href="#/night/breathe">Slow breathing</a><a class="nbtn" href="#/night/pmr">Muscle relaxation</a>
      <a class="nbtn" href="#/night" >I'm sleepy, back to bed</a></div></div>`;
  }
  if (mode === 'shuffle') {
    return `${exit}<div class="night-wrap center"><p class="dim">Picture each thing for a few seconds, then let it go.</p>
      <p class="shuffle-word" id="sw"></p><p class="shuffle-letter" id="sl"></p><p class="shuffle-item" id="si"></p>
      <div class="night-actions"><button class="nbtn" data-act="shuffle-next">Next letter</button><button class="nbtn" data-act="shuffle-new">New word</button></div>
      <p class="dim small">${S.settings.speech ? 'Voice guidance is on. You can close your eyes.' : 'Turn on voice guidance in Settings to close your eyes.'}</p></div>`;
  }
  if (mode === 'breathe') {
    return `${exit}<div class="night-wrap center"><div class="breath"><div class="breath-dot"></div></div><p class="breath-cue" id="bc">in</p>
      <p class="dim">In for 4, out for 6. Let the out-breath be long and slow. Stop whenever you like.</p></div>`;
  }
  if (mode === 'pmr') {
    return `${exit}<div class="night-wrap center"><p class="dim" id="pg"></p><p class="pmr-cue" id="pc">Get comfortable.</p>
      <p class="dim small">Tense about 5 seconds, release about 15. Tense firmly, but don't strain.</p></div>`;
  }
  if (mode === 'pi') {
    return `${exit}<div class="night-wrap"><h1>Give up trying to sleep</h1>
      ${C.PI_SCRIPT.map((x) => `<p>${esc(x)}</p>`).join('')}
      <p class="dim">You can't force sleep, and you don't need to. One rough night is OK; tomorrow you'll still get up at your anchor, and that builds tonight's sleep drive.</p></div>`;
  }
  return `${exit}<div class="night-wrap"><h1>It's OK.</h1>
    <p class="dim">No clock here on purpose. What's going on?</p>
    <div class="night-menu">
      <a class="nbtn big" href="#/night/getup">I've been awake a while<small>Get up and reset</small></a>
      <a class="nbtn big" href="#/night/shuffle">My mind is racing<small>Cognitive shuffle</small></a>
      <a class="nbtn big" href="#/night/pmr">My body feels wired<small>Muscle relaxation</small></a>
      <a class="nbtn big" href="#/night/breathe">I need to slow down<small>Slow breathing</small></a>
      <a class="nbtn big" href="#/night/pi">I'm stressing about sleep<small>Stop trying</small></a>
    </div></div>`;
}

afterRender.night = ([mode]) => {
  if (mode === 'shuffle') startShuffle();
  if (mode === 'breathe') {
    const cue = document.getElementById('bc');
    let inPhase = true;
    const step = () => {
      cue.textContent = inPhase ? 'in' : 'out';
      later(() => {
        inPhase = !inPhase;
        step();
      }, inPhase ? 4000 : 6000);
    };
    step();
    keepAwake(true);
  }
  if (mode === 'pmr') startPMR();
};

let shuffle = { word: '', i: 0 };
function startShuffle(newWord = true) {
  stopAll();
  if (newWord || !shuffle.word) shuffle = { word: C.SHUFFLE_WORDS[Math.floor(Math.random() * C.SHUFFLE_WORDS.length)], i: 0 };
  const w = document.getElementById('sw');
  const l = document.getElementById('sl');
  const it = document.getElementById('si');
  if (!w) return;
  w.innerHTML = [...shuffle.word].map((c, i) => `<span class="${i === shuffle.i ? 'cur' : ''}">${c}</span>`).join('');
  const letter = shuffle.word[shuffle.i];
  l.textContent = letter.toUpperCase();
  if (newWord) say(`Your word is ${shuffle.word}. ${letter}.`);
  else say(letter);
  const pool = [...(C.SHUFFLE_ITEMS[letter] ?? [])].sort(() => Math.random() - 0.5);
  let n = 0;
  const show = () => {
    if (n >= pool.length) {
      shuffle.i = (shuffle.i + 1) % shuffle.word.length;
      startShuffle(false);
      return;
    }
    it.textContent = pool[n];
    say(pool[n]);
    n += 1;
  };
  later(show, 2500);
  every(show, 9000);
  keepAwake(true);
}

function startPMR() {
  const g = document.getElementById('pg');
  const c = document.getElementById('pc');
  let i = 0;
  const run = () => {
    if (!c) return;
    if (i >= C.PMR.length) {
      g.textContent = '';
      c.textContent = 'Let your whole body stay heavy and loose.';
      say('Let your whole body stay heavy and loose.');
      keepAwake(false);
      return;
    }
    const [group, tense] = C.PMR[i];
    g.textContent = group;
    c.textContent = tense;
    say(`${group}. ${tense}`);
    later(() => {
      c.textContent = 'Release. Notice the difference.';
      say('And release. Notice the difference.');
      i += 1;
      later(run, 15000);
    }, 6000);
  };
  later(run, 2500);
  keepAwake(true);
}

// ---------- Worry Time / offload ----------

function viewWorry([tab]) {
  const t = today();
  if (tab === 'offload') {
    return `
    <header class="top"><div><p class="eyebrow">Wind down · 5 min</p><h1>To-do offload</h1></div></header>
    <p class="muted">Write a <b>specific</b> to-do list for the next few days. The more specific, the better it works. Then it's out of your head and on the page.</p>
    <form class="panel form" data-form="offload">
      <textarea name="todos" rows="9" placeholder="e.g.\n– Email tutor about week 8 quiz extension\n– Buy milk + bread on the way home\n– Draft intro paragraph for assignment">${esc(S.todos[t] ?? '')}</textarea>
      <button class="btn primary" type="submit">Done, it's on the page</button>
    </form>
    <p class="muted center"><a href="#/worry">Worry Time →</a></p>`;
  }
  const todays = S.worries.filter((w) => w.date === t);
  const done = check(t, 'worry');
  return `
  <header class="top"><div><p class="eyebrow">About 3 h before bed · out of the bedroom</p><h1>Worry Time</h1></div></header>
  <p class="muted">Write each worry and one next step, even if the step is "nothing I can do tonight". When you're done, close the book. If it comes back in bed, tell yourself "it's in the book".</p>
  <form class="panel form" data-form="worry">
    <label>What's on your mind?<textarea name="worry" rows="2" required></textarea></label>
    <label>One next step<input name="step" placeholder="e.g. ask about it Thursday · nothing to do tonight"></label>
    <button class="btn" type="submit">Add</button>
  </form>
  ${todays.length ? `<section class="panel"><h2>Tonight's book</h2><ul class="worries">${todays.map((w) => `<li><b>${esc(w.worry)}</b><span>→ ${esc(w.step || '—')}</span></li>`).join('')}</ul></section>` : ''}
  <button class="btn primary" data-act="worry-close" ${done ? 'disabled' : ''}>${done ? 'Book closed for tonight ✓' : 'Close the book'}</button>
  <p class="muted center"><a href="#/worry/offload">To-do offload (wind-down) →</a></p>`;
}

// ---------- Review ----------

function viewReview() {
  const st = status();
  const t = today();
  const es = entries();
  const from = L.addDays(t, -6);
  const wk = L.summarise(es, from, t);
  const anchor = L.nightMins(S.settings.wakeAnchor);
  const inWeek = es.filter((e) => e.date >= from && e.date <= t);
  const anchorHits = inWeek.filter((e) => Math.abs(L.nightMins(e.outOfBed) - anchor) <= 30).length;
  const days7 = Array.from({ length: 7 }, (_, i) => L.addDays(t, -i));
  const lightN = days7.filter((d) => check(d, 'light')).length;
  const worryN = days7.filter((d) => check(d, 'worry')).length;
  const pct = (x) => (x == null ? '–' : `${Math.round(x * 100)}%`);

  let action = '';
  if (st.phase === 'baseline') {
    const all = L.summarise(es, L.addDays(S.startDate, 1), t);
    if (st.ready && all.tst != null) {
      const proposed = L.initialWindow({ meanTST: all.tst, meanTIB: all.tib, gentle: S.settings.gentle, floor: S.settings.floorMins });
      const bed = L.toMins(S.settings.wakeAnchor) - proposed;
      action = `<section class="panel accent"><h2>Your sleep window</h2>
        <p>From ${all.nights} nights: you're in bed about <b>${L.fmtDuration(all.tib)}</b> but asleep about <b>${L.fmtDuration(all.tst)}</b> (efficiency ${pct(all.se)}).</p>
        <p class="big">${L.fmtClock(bed)} → ${L.fmtClock(S.settings.wakeAnchor)}<small>${L.fmtDuration(proposed)} window${S.settings.gentle ? ' · gentle mode' : ''}</small></p>
        <p class="muted">Don't go to bed before ${L.fmtClock(bed)}, even if you're tired, and get up at ${L.fmtClock(S.settings.wakeAnchor)} every day. Expect to feel sleepier for 1–2 weeks. <b>Don't drive when drowsy.</b> <a href="#/learn/window">Why this works</a></p>
        <button class="btn primary" data-act="window-set" data-w="${proposed}">Start my window</button></section>`;
    } else {
      action = `<section class="panel"><h2>Baseline in progress</h2><p>${st.logged} of 7 nights logged. Keep logging every morning; your sleep window is calculated from this week.</p></section>`;
    }
  } else if (st.reviewDue) {
    const r = L.titrate({ window: st.window, meanSE: wk.se, meanTST: wk.tst, nights: wk.nights, gentle: S.settings.gentle, floor: S.settings.floorMins });
    const bed = L.toMins(S.settings.wakeAnchor) - r.window;
    action = `<section class="panel accent"><h2>Next week's window</h2><p>${esc(r.reason)}</p>
      <p class="big">${L.fmtClock(bed)} → ${L.fmtClock(S.settings.wakeAnchor)}<small>${L.fmtDuration(r.window)}${r.change ? ` (${r.change > 0 ? '+' : ''}${L.fmtDuration(r.change)})` : ' (no change)'}</small></p>
      <button class="btn primary" data-act="window-set" data-w="${r.window}" data-reason="${esc(r.reason)}">Apply</button></section>`;
  } else {
    action = `<section class="panel"><h2>Week ${st.week}</h2><p>Window ${L.fmtDuration(st.window)}. Next review in ${7 - st.sinceChange} day${7 - st.sinceChange === 1 ? '' : 's'}.</p></section>`;
  }

  // weekly SE trend since start
  const trend = [];
  if (S.startDate) {
    for (let end = t; end > S.startDate && trend.length < 10; end = L.addDays(end, -7)) {
      const s = L.summarise(es, L.addDays(end, -6), end);
      trend.unshift(s.se);
    }
  }
  const bars = trend
    .map((v, i) => `<div class="bar" title="${pct(v)}"><i style="height:${v == null ? 2 : Math.max(4, Math.round(v * 100))}%"></i><small>${i === trend.length - 1 ? 'now' : ''}</small></div>`)
    .join('');

  const isiRows = S.isi
    .map((r, i) => {
      const d = i ? r.total - S.isi[0].total : null;
      return `<li><span>${new Date(r.date + 'T12:00').toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}</span><b>${r.total}</b><small>${L.isiBand(r.total).label}${d != null ? ` · ${d > 0 ? '+' : ''}${d} vs start` : ''}</small></li>`;
    })
    .join('');
  const isiWin = S.isi.length > 1 && S.isi[0].total - S.isi.at(-1).total >= 6;

  const exps = [
    ['🎧 Podcast in bed', (e) => e.audioInBed],
    ['📝 Worry Time the evening before', (e) => !!S.checks[L.addDays(e.date, -1)]?.worry],
    ['🍷 Alcohol', (e) => e.alcohol],
    ['☕ Caffeine after cutoff', (e) => e.caffeineLate],
  ]
    .map(([label, pred]) => {
      const c = L.compare(es, pred);
      return `<li><b>${label}</b>${
        c.enough
          ? `<span>with: ${L.fmtDuration(c.yes)} to fall asleep · without: ${L.fmtDuration(c.no)}</span>`
          : `<span class="muted">needs ≥5 nights each (${c.nYes} with / ${c.nNo} without)</span>`
      }</li>`;
    })
    .join('');

  return `
  <header class="top"><div><p class="eyebrow">Weekly review</p><h1>Last 7 days</h1></div></header>
  ${action}
  <section class="stats">
    ${stat('Sleep efficiency', pct(wk.se), 'target 85–90%+')}
    ${stat('To fall asleep', L.fmtDuration(wk.sol), 'average')}
    ${stat('Awake in night', L.fmtDuration(wk.waso), 'average')}
    ${stat('Asleep', L.fmtDuration(wk.tst), 'average')}
    ${stat('Rise-time spread', wk.riseSD == null ? '–' : `±${Math.round(wk.riseSD)}m`, 'lower = steadier clock')}
    ${stat('Anchor kept', `${anchorHits}/${inWeek.length || 0}`, 'within 30 min')}
    ${stat('Morning light', `${lightN}/7`, 'days')}
    ${stat('Worry Time', `${worryN}/7`, 'evenings')}
  </section>
  <p class="muted small">${wk.nights} night${wk.nights === 1 ? '' : 's'} logged this week. These are averages on purpose: single nights are noisy.</p>
  ${trend.length > 1 ? `<section class="panel"><h2>Sleep efficiency by week</h2><div class="bars">${bars}</div></section>` : ''}
  <section class="panel"><h2>Insomnia Severity Index</h2>
    ${S.isi.length ? `<ul class="isi-list">${isiRows}</ul>` : '<p class="muted">No check-ins yet.</p>'}
    ${isiWin ? '<p class="win">🎉 That\'s a 6+ point drop, a clinically meaningful improvement.</p>' : ''}
    <a class="btn ghost" href="#/isi">Take it now</a></section>
  <section class="panel"><h2>Your experiments</h2><p class="muted small">Average time to fall asleep. Treat these as hints, not proof.</p><ul class="exps">${exps}</ul></section>`;
}

function stat(label, value, sub) {
  return `<div class="stat"><small>${label}</small><b>${value}</b><span>${sub}</span></div>`;
}

// ---------- Learn ----------

function viewLearn([id]) {
  const st = status();
  const focus = C.WEEK_FOCUS[Math.min(st.week, 6)].lessons;
  if (id) {
    const l = C.LESSONS.find((x) => x.id === id);
    if (!l) return '<p>Not found.</p>';
    return `<header class="top"><div><p class="eyebrow"><a href="#/learn">← Learn</a> · ${l.mins} min</p><h1>${l.title}</h1></div></header>
      <article class="panel lesson">${l.body}</article>`;
  }
  return `<header class="top"><div><p class="eyebrow">Learn</p><h1>How this works</h1></div></header>
    <ul class="lessons">${C.LESSONS.map(
      (l) => `<li><a href="#/learn/${l.id}"><b>${l.title}</b><small>${l.mins} min${focus.includes(l.id) ? ' · <em>this week</em>' : ''}</small></a></li>`
    ).join('')}</ul>
    <section class="panel"><h2>More help</h2><p>THIS WAY UP's free <b>Insomnia Program</b> (UNSW / St Vincent's) is an online CBT-I course that pairs well with this app. Your GP can also prescribe it with clinician check-ins.</p>
    <a class="btn ghost" href="https://thiswayup.org.au/programs/insomnia-program/" target="_blank" rel="noopener">Open THIS WAY UP</a></section>`;
}

// ---------- ISI ----------

function viewISI() {
  return `<header class="top"><div><p class="eyebrow">Sleep check-in · every 2 weeks</p><h1>Insomnia Severity Index</h1></div></header>
  <form class="form" data-form="isi">
    ${C.ISI.map(
      (it, i) => `<fieldset class="panel"><legend>${i + 1}. ${it.q}</legend><div class="chips pick col" data-name="q${i}">
        ${it.a.map((a, v) => `<button type="button" class="chip" data-act="pick" data-v="${v}">${a}</button>`).join('')}
        </div><input type="hidden" name="q${i}" value=""></fieldset>`
    ).join('')}
    <button class="btn primary" type="submit">See my score</button>
  </form>
  <p class="muted small">ISI © Charles M. Morin, used here for personal self-monitoring.</p>`;
}

// ---------- Reminders ----------

function viewReminders() {
  const s = sched();
  const rows = [
    ['Wake anchor (alarm)', s.wake, 'Clock app alarm or Health → Sleep schedule. Fixed; set once.'],
    ['Up, light & diary', s.diary, 'Up now. Get outside light, then log your diary.'],
    ['Caffeine cutoff', s.caffeine, 'Caffeine cutoff. Switch to decaf or water.'],
    ['Worry Time', s.worry, 'Worry Time: 15 min, out of the bedroom.'],
    ['Wind down', s.windDown, 'Wind down: dim lights, to-do offload, podcast in the chair.'],
    [currentWindow() ? 'Window opens' : 'Bedtime', s.bedtime, 'Window open. Bed only when sleepy.'],
  ];
  const needs = currentWindow() && S.remindersWindow !== currentWindow();
  return `<header class="top"><div><p class="eyebrow">iPhone setup · about 10 min once</p><h1>Reminders</h1></div></header>
  ${needs ? `<p class="card primary static"><b>Your window changed.</b> Update the times marked ★ below, then tap "I've updated them".</p>` : ''}
  <section class="panel"><h2>Your times</h2><ul class="remlist">${rows
    .map(([label, t, msg], i) => `<li><span class="time">${L.fmtClock(t)}${needs && i >= 2 ? ' ★' : ''}</span><span><b>${label}</b><small>${i === 0 ? esc(msg) : `“${esc(msg)}”`}</small></span></li>`)
    .join('')}</ul>
    ${currentWindow() ? `<button class="btn ${needs ? 'primary' : 'ghost'}" data-act="rem-ack">I've updated them</button>` : ''}</section>
  <section class="panel lesson"><h2>How to set them up</h2>
    <ol>
      <li><b>Wake anchor:</b> in the <b>Clock</b> app, add an alarm at ${L.fmtClock(s.wake)}, repeat <b>every day</b>. (Or use Health → Sleep → Full Schedule with the same wake time every day, which also turns on Sleep Focus at wind-down.)</li>
      <li>Open <b>Shortcuts</b> → <b>Automation</b> → <b>+</b> → <b>Time of Day</b>.</li>
      <li>Set the time from the list above, <b>Repeat: Daily</b>, and choose <b>Run Immediately</b>. Turn off "Notify When Run".</li>
      <li>Tap <b>New Blank Automation</b> → add the <b>Show Notification</b> action → paste the message in quotes.</li>
      <li>Repeat for each row. Add one more: <b>Time of Day → Weekly → Sunday</b> at ${L.fmtClock(s.light)} → "Weekly sleep review".</li>
    </ol>
    <p class="muted">When your window changes (usually ±15 min after a weekly review), only the bedtime-related times (★) move. Edit those automations and you're done. The wake ones never change.</p>
  </section>`;
}

// ---------- Settings ----------

function viewSettings() {
  const st = S.settings;
  return `<header class="top"><div><p class="eyebrow"><a href="#/today">← Today</a></p><h1>Settings</h1></div></header>
  <form class="panel form" data-form="settings">
    <label>Wake anchor<input type="time" name="wakeAnchor" value="${st.wakeAnchor}" required><small>Same time every day. Changing it moves your whole schedule.</small></label>
    <label>Usual bedtime (baseline only)<input type="time" name="usualBedtime" value="${st.usualBedtime}"></label>
    <label>Caffeine cutoff (hours before bed)<input type="number" name="caffeineOffsetH" min="4" max="12" step="1" value="${st.caffeineOffsetH}"></label>
    <label>Minimum window (hours)<input type="number" name="floorH" min="5" max="7" step="0.25" value="${st.floorMins / 60}"><small>Never below 5 h.</small></label>
    <label class="toggle"><input type="checkbox" name="gentle" ${st.gentle ? 'checked' : ''}><span>Gentle mode (sleep compression: smaller steps)</span></label>
    <label class="toggle"><input type="checkbox" name="speech" ${st.speech ? 'checked' : ''}><span>Voice guidance in Night Mode</span></label>
    <button class="btn primary" type="submit">Save</button>
  </form>
  <section class="panel"><h2>Your data</h2><p class="muted">Everything stays on this phone. Back it up now and then.</p>
    <div class="btnrow"><button class="btn" data-act="export">Export backup</button>
    <label class="btn">Import<input type="file" accept="application/json,.json" data-act="import" hidden></label></div>
    <button class="btn ghost danger" data-act="reset">Erase everything</button></section>
  <section class="panel lesson"><h2>Safety</h2><ul>
    <li>Expect extra daytime sleepiness for 1–2 weeks after starting the window. <b>Don't drive or operate machinery when drowsy.</b></li>
    <li>See a GP if you notice loud snoring or gasping, leg-crawling urges in the evening, falling asleep without meaning to, low mood, or thoughts of self-harm, or if your ISI is still 15+ after 8 weeks.</li>
    <li>If you need to talk to someone now: Lifeline 13 11 14.</li>
  </ul></section>`;
}

// ---------- Onboarding ----------

let obStep = 0;
function viewOnboard() {
  const steps = [
    () => `<div class="ob"><p class="eyebrow">Sleep Coach</p><h1>Let's fix your sleep, properly.</h1>
      <p>This is a 6-week program based on <b>CBT-I</b>, the first-line treatment for chronic insomnia. It works better long-term than sleeping pills.</p>
      <ul class="tasks"><li>30-second diary each morning</li><li>One fixed wake time, every day</li><li>A personal sleep window that adjusts each week</li><li>Tools for racing thoughts, a restless body and 2 am wake-ups</li></ul>
      <p class="muted">Weeks 1–2 are the hardest. It's normal to feel worse before you feel better.</p>
      <button class="btn primary" data-act="ob-next">Start</button></div>`,
    () => `<div class="ob"><p class="eyebrow">Quick safety check</p><h1>Do any of these apply?</h1>
      <form data-form="ob-flags" class="form">${C.RED_FLAGS.map((f, i) => `<label class="toggle"><input type="checkbox" name="f${i}"><span>${f}</span></label>`).join('')}
      <button class="btn primary" type="submit">Continue</button></form></div>`,
    () => `<div class="ob"><p class="eyebrow">Your anchor</p><h1>Pick a wake time you can keep 7 days a week.</h1>
      <p class="muted">Weekends too. This is the most important number in the program. Choose one that works on your <i>earliest</i> regular day.</p>
      <form data-form="ob-times" class="form">
        <label>Wake anchor<input type="time" name="wakeAnchor" value="${S.settings.wakeAnchor}" required></label>
        <label>When do you usually go to bed right now?<input type="time" name="usualBedtime" value="${S.settings.usualBedtime}" required></label>
        <button class="btn primary" type="submit">Continue</button></form></div>`,
    () => `<div class="ob"><p class="eyebrow">Baseline week</p><h1>For the next 7 days, just observe.</h1>
      <ul class="tasks"><li>Log the diary each morning</li><li>Get up at ${L.fmtClock(S.settings.wakeAnchor)} every day</li><li>Get outside light soon after</li><li>Move the podcast out of bed: listen in a chair during wind-down</li><li>Use Worry Time in the evening</li></ul>
      <p class="muted">After that, the app calculates your sleep window. First, a 1-minute check-in to measure where you're starting from.</p>
      <button class="btn primary" data-act="ob-finish">Take the check-in</button></div>`,
  ];
  return steps[obStep]();
}

// ---------- events ----------

const actions = {
  tick: (el) => {
    const k = el.dataset.k;
    setCheck(today(), k, !check(today(), k));
    render();
  },
  pick: (el) => {
    const wrap = el.closest('.pick');
    wrap.querySelectorAll('.chip').forEach((c) => c.classList.toggle('on', c === el));
    wrap.parentElement.querySelector(`input[name="${wrap.dataset.name}"]`).value = el.dataset.v;
  },
  'diary-delete': () => {
    if (!confirm('Delete this diary entry?')) return;
    delete S.diary[diaryDate];
    persist();
    diaryDate = null;
    go('#/today');
  },
  'night-exit': () => {
    nightLogged = null;
  },
  'shuffle-next': () => {
    shuffle.i = (shuffle.i + 1) % shuffle.word.length;
    startShuffle(false);
  },
  'shuffle-new': () => startShuffle(true),
  'worry-close': () => {
    setCheck(today(), 'worry', true);
    toast("Book closed. If it comes back in bed: it's in the book.");
    render();
  },
  'window-set': (el) => {
    const w = Number(el.dataset.w);
    S.windows.push({ effectiveFrom: today(), windowMins: w, reason: el.dataset.reason ?? 'Initial window from baseline' });
    persist();
    toast(`Window set: ${L.fmtDuration(w)}`);
    go('#/reminders');
  },
  'rem-ack': () => {
    S.remindersWindow = currentWindow();
    persist();
    toast('Great, reminders are in sync.');
    go('#/today');
  },
  export: async () => {
    const text = store.exportJSON(S);
    const name = `sleep-backup-${today()}.json`;
    const file = new File([text], name, { type: 'application/json' });
    try {
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], title: 'Sleep Coach backup' });
        return;
      }
    } catch (e) {
      if (e?.name === 'AbortError') return;
    }
    const a = document.createElement('a');
    a.href = URL.createObjectURL(file);
    a.download = name;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  },
  reset: () => {
    if (!confirm('Erase all diary entries, check-ins and settings on this device? Export a backup first if unsure.')) return;
    S = store.blankState();
    persist();
    obStep = 0;
    go('#/onboard');
  },
  'ob-next': () => {
    obStep += 1;
    render();
  },
  'ob-finish': () => {
    S.onboarded = true;
    S.startDate = today();
    persist();
    store.requestPersistence();
    go('#/isi');
  },
};

const forms = {
  diary: saveDiary,
  offload: (f) => {
    S.todos[today()] = new FormData(f).get('todos');
    setCheck(today(), 'offload', true);
    toast('Offloaded. It will keep until tomorrow.');
    go('#/today');
  },
  worry: (f) => {
    const d = new FormData(f);
    S.worries.push({ id: Date.now(), date: today(), worry: String(d.get('worry')).trim(), step: String(d.get('step') ?? '').trim() });
    persist();
    render();
  },
  isi: (f) => {
    const d = new FormData(f);
    const items = C.ISI.map((_, i) => d.get(`q${i}`));
    if (items.some((v) => v === '' || v == null)) return toast('Answer all seven questions.');
    const nums = items.map(Number);
    const total = L.isiTotal(nums);
    const idx = S.isi.findIndex((r) => r.date === today());
    const rec = { date: today(), items: nums, total };
    if (idx >= 0) S.isi[idx] = rec;
    else S.isi.push(rec);
    persist();
    toast(`ISI ${total}: ${L.isiBand(total).label}`);
    go(S.isi.length === 1 ? '#/today' : '#/review');
  },
  settings: (f) => {
    const d = new FormData(f);
    S.settings = {
      ...S.settings,
      wakeAnchor: d.get('wakeAnchor'),
      usualBedtime: d.get('usualBedtime') || S.settings.usualBedtime,
      caffeineOffsetH: Math.min(12, Math.max(4, Number(d.get('caffeineOffsetH')) || 8)),
      floorMins: Math.max(300, Math.round((Number(d.get('floorH')) || 5) * 60)),
      gentle: d.get('gentle') === 'on',
      speech: d.get('speech') === 'on',
    };
    persist();
    toast('Saved');
    go('#/today');
  },
  'ob-flags': (f) => {
    const any = [...new FormData(f).keys()].length > 0;
    if (any) {
      S.settings.gentle = true;
      S.flags = [...new FormData(f).keys()];
      alert(
        'Please see a GP before starting the sleep window. Some of these need checking first, and sleep restriction may not be right without supervision.\n\nYou can still use the diary, Worry Time and night tools. Gentle mode is now on.'
      );
    }
    obStep += 1;
    render();
  },
  'ob-times': (f) => {
    const d = new FormData(f);
    S.settings.wakeAnchor = d.get('wakeAnchor');
    S.settings.usualBedtime = d.get('usualBedtime');
    obStep += 1;
    render();
  },
};

app.addEventListener('click', (e) => {
  const el = e.target.closest('[data-act]');
  if (!el || el.tagName === 'SELECT' || el.tagName === 'INPUT') return;
  const fn = actions[el.dataset.act];
  if (fn) {
    if (el.tagName === 'BUTTON') e.preventDefault();
    fn(el);
  }
});

app.addEventListener('change', async (e) => {
  const el = e.target;
  if (el.dataset.act === 'diary-date') {
    diaryDate = el.value;
    render();
  }
  if (el.dataset.act === 'import' && el.files?.[0]) {
    try {
      S = store.importJSON(await el.files[0].text());
      persist();
      toast('Backup restored');
      go('#/today');
    } catch (err) {
      toast(err.message || 'Import failed');
    }
  }
});

app.addEventListener('submit', (e) => {
  const fn = forms[e.target.dataset.form];
  if (fn) {
    e.preventDefault();
    fn(e.target);
  }
});

window.addEventListener('hashchange', render);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && !location.hash.startsWith('#/night')) render();
});

if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('./sw.js').catch(() => {});
}

render();
