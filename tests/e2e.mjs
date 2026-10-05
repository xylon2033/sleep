// End-to-end smoke test: drives the real app in Chromium at iPhone size.
// Usage: node tests/e2e.mjs [screenshotDir]
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require('playwright');
} catch {
  playwright = require(`${execSync('npm root -g').toString().trim()}/playwright`);
}
const { chromium, devices } = playwright;

const root = new URL('../app/', import.meta.url).pathname;
const shots = process.argv[2];
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const server = http.createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^\/+/, '') || 'index.html';
  try {
    const body = await readFile(join(root, path));
    res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(0, r));
const base = `http://localhost:${server.address().port}/`;

const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const daysAgo = (n) => {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return iso(d);
};

const browser = await chromium.launch();
const ctx = await browser.newContext({ ...devices['iPhone 13'] });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
const snap = async (name) => shots && page.screenshot({ path: `${shots}/${name}.png`, fullPage: true });
const state = () => page.evaluate(() => JSON.parse(localStorage.getItem('sleep-coach-v1')));

// 1. Onboarding
await page.goto(base);
await page.getByText("Let's fix your sleep").waitFor();
await snap('01-onboard');
await page.click('[data-act="ob-next"]');
await page.getByText('Do any of these apply?').waitFor();
await page.click('form[data-form="ob-flags"] button[type="submit"]');
await page.fill('input[name="wakeAnchor"]', '07:00');
await page.fill('input[name="usualBedtime"]', '23:30');
await page.click('form[data-form="ob-times"] button[type="submit"]');
await page.click('[data-act="ob-finish"]');

// 2. ISI
await page.getByText('Insomnia Severity Index').first().waitFor();
for (let i = 0; i < 7; i++) await page.click(`.pick[data-name="q${i}"] .chip[data-v="${i < 3 ? 3 : 2}"]`);
await snap('02-isi');
await page.click('form[data-form="isi"] button[type="submit"]');
await page.getByText("Today's plan").waitFor();
let s = await state();
assert.equal(s.isi[0].total, 3 * 3 + 2 * 4);
assert.equal(s.onboarded, true);

// 3. Today
await page.goto(base + '#/today');
await page.getByText("Today's plan").waitFor();
await snap('03-today-baseline');

// 4. Diary
await page.click('#tabbar a[data-tab="diary"]');
await page.getByText('How was last night?').waitFor();
await page.fill('input[name="intoBed"]', '23:00');
await page.fill('input[name="lightsOut"]', '23:30');
await page.click('.pick[data-name="onsetMins"] .chip[data-v="60"]');
await page.click('.pick[data-name="wakings"] .chip[data-v="2"]');
await page.click('.pick[data-name="wasoMins"] .chip[data-v="45"]');
await page.fill('input[name="finalWake"]', '06:45');
await page.fill('input[name="outOfBed"]', '07:00');
await page.click('.pick[data-name="quality"] .chip[data-v="2"]');
await page.check('input[name="audioInBed"]');
await snap('04-diary');
await page.click('form[data-form="diary"] button[type="submit"]');
await page.getByText("Today's plan").waitFor();
s = await state();
const t = iso(new Date());
assert.equal(s.diary[t].onsetMins, 60);
assert.equal(s.diary[t].audioInBed, true);

// 5. Worry Time
await page.goto(base + '#/worry');
await page.fill('textarea[name="worry"]', 'Quiz on Thursday');
await page.fill('input[name="step"]', 'Do practice set Wednesday');
await page.click('form[data-form="worry"] button[type="submit"]');
await page.getByText("Tonight's book").waitFor();
await page.click('[data-act="worry-close"]');
s = await state();
assert.equal(s.checks[t].worry, true);
await page.goto(base + '#/worry/offload');
await page.fill('textarea[name="todos"]', '- Email tutor');
await page.click('form[data-form="offload"] button[type="submit"]');
await page.getByText("Today's plan").waitFor();

// 6. Seed a full baseline, then set the window
await page.evaluate(
  ({ start, nights }) => {
    const st = JSON.parse(localStorage.getItem('sleep-coach-v1'));
    st.startDate = start;
    for (const d of nights) {
      st.diary[d] = { intoBed: '23:00', lightsOut: '23:15', onsetMins: 60, wakings: 2, wasoMins: 45, finalWake: '06:30', outOfBed: '07:00', quality: 2, audioInBed: true };
    }
    localStorage.setItem('sleep-coach-v1', JSON.stringify(st));
  },
  { start: daysAgo(8), nights: [1, 2, 3, 4, 5, 6, 7].map(daysAgo) }
);
await page.goto(base + '#/today');
await page.reload();
await page.getByText('Baseline complete').waitFor();
await page.goto(base + '#/review');
await page.getByText('Your sleep window').waitFor();
await snap('05-review-baseline');
await page.click('[data-act="window-set"]');
await page.getByText('How to set them up').waitFor();
s = await state();
// 23:15→06:30 = 435 − 60 − 45 = 330 TST → window 330 (5h30m)
assert.equal(s.windows[0].windowMins, 330);
await snap('06-reminders');
await page.click('[data-act="rem-ack"]');
await page.getByText("Today's plan").waitFor();
await snap('07-today-active');

// 7. Weekly titration
await page.evaluate(
  ({ from, nights }) => {
    const st = JSON.parse(localStorage.getItem('sleep-coach-v1'));
    st.windows[0].effectiveFrom = from;
    for (const d of nights) {
      st.diary[d] = { intoBed: '01:30', lightsOut: '01:30', onsetMins: 15, wakings: 0, wasoMins: 10, finalWake: '06:55', outOfBed: '07:00', quality: 4, audioInBed: false };
    }
    localStorage.setItem('sleep-coach-v1', JSON.stringify(st));
  },
  { from: daysAgo(7), nights: [0, 1, 2, 3, 4, 5, 6].map(daysAgo) }
);
await page.goto(base + '#/review');
await page.reload();
await page.getByText("Next week's window").waitFor();
await snap('08-review-titrate');
await page.click('[data-act="window-set"]');
s = await state();
assert.equal(s.windows.at(-1).windowMins, 345, 'SE ≥ 90% expands by 15 min');

// 8. Night mode (no clock anywhere)
await page.goto(base + '#/night');
await page.getByText("It's OK.").waitFor();
assert.equal(await page.locator('#tabbar').isHidden(), true);
await snap('09-night');
const nightText = await page.locator('#app').innerText();
assert.doesNotMatch(nightText, /\d{1,2}:\d{2}/, 'night mode must not show a time');
await page.click('a[href="#/night/shuffle"]');
await page.waitForTimeout(3000);
assert.ok((await page.locator('#sl').innerText()).length === 1);
await snap('10-shuffle');
await page.click('a[href="#/night"]').catch(() => {});
await page.goto(base + '#/night/breathe');
await page.waitForTimeout(500);
await snap('11-breathe');
await page.goto(base + '#/night/pmr');
await page.waitForTimeout(3000);
assert.notEqual(await page.locator('#pg').innerText(), '');
await page.goto(base + '#/night/getup');
await page.getByText('Get up for a bit').waitFor();
s = await state();
assert.ok(Object.values(s.night).some((n) => n.visits >= 1 && n.tools.includes('shuffle')));

// 9. Learn + settings
await page.goto(base + '#/learn/window');
await page.getByText('Why less time in bed means more sleep').waitFor();
await snap('12-lesson');
await page.goto(base + '#/settings');
await page.check('input[name="gentle"]');
await page.click('form[data-form="settings"] button[type="submit"]');
s = await state();
assert.equal(s.settings.gentle, true);

await browser.close();
server.close();
assert.deepEqual(errors, [], `page errors: ${errors.join('\n')}`);
console.log('e2e: all checks passed');
