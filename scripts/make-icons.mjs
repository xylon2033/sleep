// Rasterise app/icons/icon.svg into the PNG sizes iOS and the manifest need.
// Usage: node scripts/make-icons.mjs  (uses the globally installed Playwright + Chromium)
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

const require = createRequire(import.meta.url);
const { chromium } = require(`${execSync('npm root -g').toString().trim()}/playwright`);
const svg = readFileSync(new URL('../app/icons/icon.svg', import.meta.url), 'utf8');
const sizes = { 'apple-touch-icon.png': 180, 'icon-192.png': 192, 'icon-512.png': 512 };

const browser = await chromium.launch();
for (const [name, size] of Object.entries(sizes)) {
  const page = await browser.newPage({ viewport: { width: size, height: size } });
  await page.setContent(`<style>html,body{margin:0}svg{display:block;width:${size}px;height:${size}px}</style>${svg}`);
  await page.screenshot({ path: new URL(`../app/icons/${name}`, import.meta.url).pathname });
  await page.close();
}
await browser.close();
console.log('icons written');
