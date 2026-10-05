import test from 'node:test';
import assert from 'node:assert/strict';
import * as L from '../app/js/logic.js';

test('time helpers', () => {
  assert.equal(L.toMins('07:30'), 450);
  assert.equal(L.toMins('24:00'), null);
  assert.equal(L.toMins('bad'), null);
  assert.equal(L.toHHMM(-30), '23:30');
  assert.equal(L.toHHMM(1500), '01:00');
  assert.equal(L.nightMins('12:00'), 0);
  assert.equal(L.nightMins('23:00'), 660);
  assert.equal(L.nightMins('07:00'), 1140);
  assert.equal(L.fmtDuration(375), '6h 15m');
  assert.equal(L.fmtDuration(45), '45m');
  assert.equal(L.fmtClock('00:15'), '12:15 am');
  assert.equal(L.fmtClock(13 * 60), '1:00 pm');
});

test('date helpers', () => {
  assert.equal(L.addDays('2026-10-31', 1), '2026-11-01');
  assert.equal(L.addDays('2026-01-01', -1), '2025-12-31');
  assert.equal(L.daysBetween('2026-10-01', '2026-10-08'), 7);
  // across the AEDT switch (first Sunday in October)
  assert.equal(L.daysBetween('2026-10-03', '2026-10-05'), 2);
});

test('diaryMetrics: typical insomnia night across midnight', () => {
  const m = L.diaryMetrics({
    intoBed: '22:30',
    lightsOut: '23:00',
    onsetMins: 60,
    wasoMins: 40,
    finalWake: '06:30',
    outOfBed: '07:00',
  });
  // TIB 22:30 -> 07:00 = 510; asleep window 23:00 -> 06:30 = 450 − 60 − 40 = 350
  assert.equal(m.tib, 510);
  assert.equal(m.tst, 350);
  assert.ok(Math.abs(m.se - 350 / 510) < 1e-9);
  assert.equal(m.earlyMins, 30);
  assert.equal(m.preSleepMins, 30);
});

test('diaryMetrics: after-midnight bedtime and defaults', () => {
  const m = L.diaryMetrics({ intoBed: '01:15', onsetMins: 15, wasoMins: 0, finalWake: '08:00' });
  assert.equal(m.tib, 405);
  assert.equal(m.tst, 390);
});

test('diaryMetrics: rejects inconsistent order', () => {
  assert.equal(L.diaryMetrics({ intoBed: '23:00', lightsOut: '22:00', finalWake: '07:00', outOfBed: '07:10' }), null);
  assert.equal(L.diaryMetrics({ intoBed: '23:00', finalWake: '07:00', outOfBed: '06:00' }), null);
});

test('diaryMetrics: TST never negative', () => {
  const m = L.diaryMetrics({ intoBed: '23:00', onsetMins: 400, wasoMins: 200, finalWake: '06:00', outOfBed: '06:00' });
  assert.equal(m.tst, 0);
  assert.equal(m.se, 0);
});

test('initialWindow: standard restriction uses TST with 5h floor', () => {
  assert.equal(L.initialWindow({ meanTST: 352, meanTIB: 500 }), 360);
  assert.equal(L.initialWindow({ meanTST: 200, meanTIB: 480 }), 300);
});

test('initialWindow: gentle compression starts below TIB', () => {
  assert.equal(L.initialWindow({ meanTST: 352, meanTIB: 510, gentle: true }), 480);
  // never below TST
  assert.equal(L.initialWindow({ meanTST: 470, meanTIB: 480, gentle: true }), 480);
});

test('titrate: expand / hold / shrink', () => {
  const up = L.titrate({ window: 360, meanSE: 0.92, meanTST: 340, nights: 7 });
  assert.equal(up.window, 375);
  assert.equal(up.action, 'expand');

  const hold = L.titrate({ window: 360, meanSE: 0.87, meanTST: 315, nights: 6 });
  assert.equal(hold.window, 360);
  assert.equal(hold.action, 'hold');

  const down = L.titrate({ window: 420, meanSE: 0.78, meanTST: 330, nights: 7 });
  assert.equal(down.window, 330);
  assert.equal(down.action, 'shrink');

  const small = L.titrate({ window: 360, meanSE: 0.84, meanTST: 355, nights: 7 });
  assert.equal(small.window, 345, 'at least −15 when SE < 85%');
});

test('titrate: respects floor and thin data', () => {
  const floor = L.titrate({ window: 300, meanSE: 0.7, meanTST: 200, nights: 7 });
  assert.equal(floor.window, 300);
  assert.equal(floor.action, 'hold');

  const thin = L.titrate({ window: 360, meanSE: 0.95, meanTST: 350, nights: 3 });
  assert.equal(thin.window, 360);
  assert.match(thin.reason, /Only 3 nights/);
});

test('titrate: gentle shrinks by 30 but not below TST', () => {
  assert.equal(L.titrate({ window: 480, meanSE: 0.8, meanTST: 360, nights: 7, gentle: true }).window, 450);
  assert.equal(L.titrate({ window: 380, meanSE: 0.8, meanTST: 365, nights: 7, gentle: true }).window, 375);
});

test('schedule derives from wake anchor and window', () => {
  const s = L.schedule({ wakeAnchor: '07:00', windowMins: 390 });
  assert.equal(L.toHHMM(s.bedtime), '00:30');
  assert.equal(L.toHHMM(s.windDown), '23:30');
  assert.equal(L.toHHMM(s.worry), '21:30');
  assert.equal(L.toHHMM(s.caffeine), '16:30');
  assert.equal(L.toHHMM(s.light), '07:30');

  const base = L.schedule({ wakeAnchor: '07:00', usualBedtime: '23:00' });
  assert.equal(L.toHHMM(base.bedtime), '23:00');
  assert.equal(L.toHHMM(base.caffeine), '15:00');
});

test('ISI scoring and bands', () => {
  assert.equal(L.isiTotal([3, 3, 1, 3, 2, 3, 3]), 18);
  assert.equal(L.isiBand(7).key, 'none');
  assert.equal(L.isiBand(8).key, 'sub');
  assert.equal(L.isiBand(15).key, 'mod');
  assert.equal(L.isiBand(22).key, 'sev');
});

test('programStatus: baseline readiness then weeks', () => {
  const entries = Array.from({ length: 7 }, (_, i) => ({ date: L.addDays('2026-10-05', i + 1) }));
  const b = L.programStatus({ startDate: '2026-10-05' }, entries.slice(0, 4), '2026-10-09');
  assert.equal(b.phase, 'baseline');
  assert.equal(b.ready, false);
  const r = L.programStatus({ startDate: '2026-10-05' }, entries, '2026-10-12');
  assert.equal(r.ready, true);

  const a = L.programStatus(
    { startDate: '2026-10-05', windows: [{ effectiveFrom: '2026-10-12', windowMins: 360 }] },
    entries,
    '2026-10-20'
  );
  assert.equal(a.phase, 'active');
  assert.equal(a.week, 2);
  assert.equal(a.reviewDue, true);
});

test('isiDue every 14 days', () => {
  assert.equal(L.isiDue([], '2026-10-05'), true);
  assert.equal(L.isiDue([{ date: '2026-10-05' }], '2026-10-18'), false);
  assert.equal(L.isiDue([{ date: '2026-10-05' }], '2026-10-19'), true);
});

test('summarise: rise-time regularity', () => {
  const mk = (date, out) => ({ date, intoBed: '23:00', onsetMins: 30, wasoMins: 0, finalWake: out, outOfBed: out });
  const s = L.summarise([mk('2026-10-06', '07:00'), mk('2026-10-07', '07:00'), mk('2026-10-08', '09:00')], '2026-10-06', '2026-10-12');
  assert.equal(s.nights, 3);
  assert.ok(s.riseSD > 60 && s.riseSD < 70);
});

test('compare needs enough nights on both sides', () => {
  const mk = (i, sol, flag) => ({ date: `d${i}`, intoBed: '23:00', onsetMins: sol, finalWake: '07:00', audioInBed: flag });
  const few = [mk(1, 10, true), mk(2, 40, false)];
  assert.equal(L.compare(few, (e) => e.audioInBed).enough, false);
  const many = [...Array(5)].flatMap((_, i) => [mk(i, 50, true), mk(i + 10, 20, false)]);
  const c = L.compare(many, (e) => e.audioInBed);
  assert.equal(c.enough, true);
  assert.equal(c.yes, 50);
  assert.equal(c.no, 20);
});
