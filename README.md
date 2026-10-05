# sleep

A personal digital CBT-I coach for chronic insomnia (slow sleep onset, night wakings, drifting body clock). It's an installable web app (PWA) for iPhone, with nudges delivered by the built-in Clock and Shortcuts apps.

- [docs/RESEARCH.md](docs/RESEARCH.md): my sleep profile and the evidence base
- [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md): features, program, algorithms, build options

## What's in the app

| Screen | What it does |
|---|---|
| **Today** | Phase/week, today's plan (wake anchor → light → caffeine cutoff → Worry Time → wind-down → window opens), this week's tasks |
| **Diary** | 30-second Consensus Sleep Diary with tap-to-pick answers and experiment tags |
| **Night** | Black/red, **no clock**. Get-up guidance, cognitive shuffle (voice-guided), muscle relaxation, slow breathing, paradoxical intention |
| **Review** | 7-day averages, rise-time regularity, adherence, sleep-window setup and weekly titration, ISI history, n-of-1 experiments |
| **Learn** | Short lessons on each CBT-I component |
| **Worry Time / To-do offload** | Constructive worry and an evening to-do list |
| **Reminders** | Your computed times plus a step-by-step iPhone Shortcuts setup |

All data stays on the phone (localStorage). Use **Settings → Export backup** now and then.

## Install on iPhone

1. One-time: in GitHub go to **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Merge to `main`. The *Deploy app to GitHub Pages* workflow publishes `app/` to `https://xylon2033.github.io/sleep/`.
3. On the iPhone, open that URL in **Safari** → Share → **Add to Home Screen**. Always open it from the home-screen icon, because the home-screen app keeps its own data, separate from Safari.
4. Follow the in-app **Reminders** screen to set up the Clock alarm and Shortcuts automations.

## Develop

```sh
npm test            # unit tests for the sleep logic (node:test, no deps)
npm run test:e2e    # drives the app in Chromium at iPhone size (needs Playwright)
npm run serve       # local server on :5173
npm run icons       # re-render PNG icons from app/icons/icon.svg
```

No build step: `app/` is plain HTML/CSS/ES modules. When you change app files, bump `VERSION` in `app/sw.js` so installed copies update.

## Disclaimer

This is a self-help tool, not medical advice. Don't drive when drowsy. See a GP if you have red-flag symptoms (listed in the app) or if things haven't improved after about 8 weeks.
