// Local-first persistence. Everything lives in this device's localStorage under one key.

const KEY = 'sleep-coach-v1';

export function blankState() {
  return {
    version: 1,
    onboarded: false,
    startDate: null,
    settings: {
      wakeAnchor: '07:00',
      usualBedtime: '23:30',
      gentle: false,
      floorMins: 300,
      caffeineOffsetH: 8,
      speech: true,
    },
    windows: [], // [{ effectiveFrom, windowMins, reason }]
    diary: {}, // { [morningDate]: entry }
    checks: {}, // { [date]: { light, worry, offload } }
    isi: [], // [{ date, items, total }]
    worries: [], // [{ id, date, worry, step }]
    todos: {}, // { [date]: text }
    night: {}, // { [morningDate]: { visits, tools: [] } }
    remindersWindow: null, // window (mins) the phone reminders were last set for
    flags: [],
  };
}

export function load() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return blankState();
    const parsed = JSON.parse(raw);
    const base = blankState();
    return { ...base, ...parsed, settings: { ...base.settings, ...(parsed.settings ?? {}) } };
  } catch {
    return blankState();
  }
}

export function save(state) {
  try {
    localStorage.setItem(KEY, JSON.stringify(state));
    return true;
  } catch {
    return false;
  }
}

export function exportJSON(state) {
  return JSON.stringify({ exportedAt: new Date().toISOString(), app: 'sleep-coach', state }, null, 2);
}

export function importJSON(text) {
  const parsed = JSON.parse(text);
  const state = parsed?.state ?? parsed;
  if (!state || typeof state !== 'object' || !('diary' in state) || !('settings' in state)) {
    throw new Error("That file doesn't look like a Sleep Coach backup.");
  }
  const base = blankState();
  return { ...base, ...state, settings: { ...base.settings, ...state.settings } };
}

export async function requestPersistence() {
  try {
    if (navigator.storage?.persist) await navigator.storage.persist();
  } catch {
    /* best effort */
  }
}
