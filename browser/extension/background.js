// Khazna browser extension: service worker.
//
// It talks to the Khazna app on this computer through the browser helper
// (native messaging host "app.khazna.bridge"). The extension stores no
// passwords: it asks the app each time, and the app decides which logins
// belong to a page.
//
// Requests to the app: {id, t, ...}; replies: {id, ok, ...} or
// {id, ok: false, error}. See lib/services/browser/browser_bridge.dart.

const HOST = 'app.khazna.bridge';
const REQUEST_TIMEOUT_MS = 15000;
const PAIR_TIMEOUT_MS = 130000;
// A save or update prompt waits this long for the user.
const PENDING_MS = 3 * 60 * 1000;
// The username of a sign-in split over two pages is kept this long.
const USERNAME_MS = 5 * 60 * 1000;

// ---------------------------------------------------------------------------
// Connection to the app
// ---------------------------------------------------------------------------

let port = null;
let nextId = 1;
const waiting = new Map();
let helloPromise = null;

function connect() {
  if (port) return port;
  const p = chrome.runtime.connectNative(HOST);
  port = p;
  helloPromise = null;
  p.onMessage.addListener((msg) => {
    const w = waiting.get(msg && msg.id);
    if (!w) return;
    waiting.delete(msg.id);
    clearTimeout(w.timer);
    w.resolve(msg);
  });
  p.onDisconnect.addListener(() => {
    const reason = classify(chrome.runtime.lastError?.message || '');
    if (port === p) {
      port = null;
      helloPromise = null;
    }
    for (const [id, w] of waiting) {
      clearTimeout(w.timer);
      w.resolve({ id, ok: false, error: reason });
    }
    waiting.clear();
  });
  return p;
}

// Chrome's reasons for a port that closed, as our error codes.
function classify(message) {
  if (/not found|forbidden|not allowed/i.test(message)) return 'not_installed';
  return 'disconnected';
}

// Sends one request and resolves with the reply (never rejects).
function request(msg, timeoutMs = REQUEST_TIMEOUT_MS) {
  return new Promise((resolve) => {
    let p;
    try {
      p = connect();
    } catch (e) {
      resolve({ ok: false, error: 'not_installed' });
      return;
    }
    const id = nextId++;
    const timer = setTimeout(() => {
      waiting.delete(id);
      resolve({ id, ok: false, error: 'timeout' });
    }, timeoutMs);
    waiting.set(id, { resolve, timer });
    try {
      p.postMessage({ ...msg, id });
    } catch (e) {
      waiting.delete(id);
      clearTimeout(timer);
      resolve({ id, ok: false, error: 'disconnected' });
    }
  });
}

// ---------------------------------------------------------------------------
// Identity and pairing
// ---------------------------------------------------------------------------

function base64Url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromBase64Url(text) {
  const s = atob(text.replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(s, (c) => c.charCodeAt(0));
}

// This browser's key: 32 random bytes made once. The app keeps only its hash.
async function clientKey() {
  const { clientKey: stored } = await chrome.storage.local.get('clientKey');
  if (typeof stored === 'string' && /^[A-Za-z0-9_-]{43}$/.test(stored)) {
    return stored;
  }
  const key = base64Url(crypto.getRandomValues(new Uint8Array(32)));
  await chrome.storage.local.set({ clientKey: key });
  return key;
}

// The six digits the app shows while pairing (pairingCode in
// browser/bridge/lib/bridge_protocol.dart).
export async function pairingCode(key) {
  const d = new Uint8Array(
    await crypto.subtle.digest('SHA-256', fromBase64Url(key)),
  );
  const n = ((d[0] << 16) | (d[1] << 8) | d[2]) % 1000000;
  const s = String(n).padStart(6, '0');
  return `${s.slice(0, 3)} ${s.slice(3)}`;
}

function browserName() {
  const brands = (navigator.userAgentData?.brands || []).map((b) => b.brand);
  if (brands.some((b) => /Edge/i.test(b))) return 'Edge';
  if (navigator.brave || brands.some((b) => /Brave/i.test(b))) return 'Brave';
  if (brands.some((b) => /Opera/i.test(b))) return 'Opera';
  return 'Chrome';
}

// Says hello once per connection; resolves with the reply.
async function hello() {
  if (port && helloPromise) return helloPromise;
  const key = await clientKey();
  const promise = request({
    t: 'hello',
    key,
    browser: browserName(),
    version: chrome.runtime.getManifest().version,
  });
  helloPromise = promise;
  const reply = await promise;
  // A failed hello is not kept: the next call tries again.
  if (!reply.ok && helloPromise === promise) helloPromise = null;
  return reply;
}

// ---------------------------------------------------------------------------
// Pages
// ---------------------------------------------------------------------------

function httpsUrl(url) {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && u.hostname ? u : null;
  } catch (e) {
    return null;
  }
}

async function tabUrl(tabId) {
  try {
    const tab = await chrome.tabs.get(tabId);
    return tab.url || '';
  } catch (e) {
    return '';
  }
}

// What the popup shows for a tab.
async function stateFor(tabId) {
  const url = await tabUrl(tabId);
  const page = httpsUrl(url);
  const h = await hello();
  if (!h.ok) return { status: h.error || 'error' };
  const base = {
    host: page ? page.hostname : '',
    appVersion: h.app || '',
    version: chrome.runtime.getManifest().version,
  };
  if (!h.paired) {
    return { ...base, status: 'not_paired', code: await pairingCode(await clientKey()) };
  }
  if (h.state !== 'unlocked') {
    const s = await request({ t: 'status' });
    if (!s.ok) return { ...base, status: s.error || 'error' };
    if (s.state !== 'unlocked') return { ...base, status: s.state };
  }
  if (!page) return { ...base, status: 'insecure' };
  const list = await request({ t: 'list', url: page.href });
  if (!list.ok) return { ...base, status: list.error || 'error' };
  return { ...base, status: 'unlocked', entries: list.entries || [] };
}

async function pair() {
  const key = await clientKey();
  const r = await request(
    { t: 'pair', key, browser: browserName() },
    PAIR_TIMEOUT_MS,
  );
  if (r.ok) helloPromise = Promise.resolve({ ok: true, paired: true, state: r.state });
  return r;
}

async function fill(tabId, entry) {
  // The address is read again now: the tab may have moved on.
  const page = httpsUrl(await tabUrl(tabId));
  if (!page) return { ok: false, error: 'insecure_page' };
  const r = await request({ t: 'fill', url: page.href, entry });
  if (!r.ok) return r;
  try {
    const done = await chrome.tabs.sendMessage(
      tabId,
      {
        cmd: 'fill',
        origin: page.origin,
        username: r.username,
        password: r.password,
      },
      { frameId: 0 },
    );
    return done && done.filled ? { ok: true } : { ok: false, error: 'no_fields' };
  } catch (e) {
    return { ok: false, error: 'no_fields' };
  }
}

async function openApp() {
  const h = await hello();
  if (h.ok) return request({ t: 'show' });
  if (h.error === 'app_not_running') return request({ t: 'open' });
  return h;
}

// ---------------------------------------------------------------------------
// Save and update prompts
// ---------------------------------------------------------------------------

const pendingKey = (tabId) => `pending:${tabId}`;
const userKey = (tabId) => `user:${tabId}`;

async function onSubmitted(sender, msg) {
  const tabId = sender.tab?.id;
  const page = httpsUrl(sender.url || '');
  if (tabId == null || sender.frameId !== 0 || !page) return null;
  if (typeof msg.password !== 'string' || !msg.password) return null;
  let username = typeof msg.username === 'string' ? msg.username.trim() : '';
  if (!username) {
    const key = userKey(tabId);
    const stored = (await chrome.storage.session.get(key))[key];
    if (stored && stored.host === page.hostname && stored.expires > Date.now()) {
      username = stored.username;
    }
  }
  const h = await hello();
  if (!h.ok || !h.paired) return null;
  const r = await request({
    t: 'check',
    url: page.href,
    username,
    password: msg.password,
  });
  if (!r.ok || (r.action !== 'save' && r.action !== 'update')) return null;
  const pending = {
    nonce: base64Url(crypto.getRandomValues(new Uint8Array(16))),
    action: r.action,
    entry: r.entry || null,
    title: r.title || page.hostname,
    host: page.hostname,
    url: page.href,
    username,
    password: msg.password,
    expires: Date.now() + PENDING_MS,
  };
  await chrome.storage.session.set({ [pendingKey(tabId)]: pending });
  return publicPrompt(pending);
}

// What the page may see of a prompt: never the password.
function publicPrompt(p) {
  return {
    nonce: p.nonce,
    action: p.action,
    title: p.title,
    host: p.host,
    username: p.username,
  };
}

async function pendingFor(sender) {
  const tabId = sender.tab?.id;
  const page = httpsUrl(sender.url || '');
  if (tabId == null || sender.frameId !== 0 || !page) return null;
  const key = pendingKey(tabId);
  const p = (await chrome.storage.session.get(key))[key];
  if (!p) return null;
  if (p.expires < Date.now()) {
    await chrome.storage.session.remove(key);
    return null;
  }
  // Show it only on the same site (a redirect within the site is fine).
  if (!sameSite(p.host, page.hostname)) return null;
  return publicPrompt(p);
}

function sameSite(a, b) {
  const strip = (h) => h.replace(/^www\./, '');
  a = strip(a);
  b = strip(b);
  return a === b || a.endsWith(`.${b}`) || b.endsWith(`.${a}`);
}

async function answer(sender, msg) {
  const tabId = sender.tab?.id;
  if (tabId == null || sender.frameId !== 0) return { ok: false };
  const key = pendingKey(tabId);
  const p = (await chrome.storage.session.get(key))[key];
  if (!p || p.nonce !== msg.nonce) return { ok: false };
  await chrome.storage.session.remove(key);
  if (!msg.yes || p.expires < Date.now()) return { ok: true, saved: false };
  const r = await request({
    t: 'save',
    url: p.url,
    username: p.username,
    password: p.password,
    entry: p.action === 'update' ? p.entry : undefined,
  });
  return { ok: r.ok, saved: r.ok, error: r.error };
}

async function rememberUsername(sender, msg) {
  const tabId = sender.tab?.id;
  const page = httpsUrl(sender.url || '');
  if (tabId == null || sender.frameId !== 0 || !page) return;
  const username = typeof msg.username === 'string' ? msg.username.trim() : '';
  if (!username || username.length > 512) return;
  await chrome.storage.session.set({
    [userKey(tabId)]: {
      host: page.hostname,
      username,
      expires: Date.now() + USERNAME_MS,
    },
  });
}

chrome.tabs.onRemoved.addListener((tabId) => {
  chrome.storage.session.remove([pendingKey(tabId), userKey(tabId)]);
});

// ---------------------------------------------------------------------------
// Messages from the popup and the content script
// ---------------------------------------------------------------------------

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  // The popup is our own page; a content script's sender is a web page.
  const fromPopup =
    sender.id === chrome.runtime.id &&
    (sender.url || '').startsWith(chrome.runtime.getURL('popup.html'));
  let work;
  switch (msg && msg.cmd) {
    case 'state':
      if (fromPopup) work = stateFor(msg.tabId);
      break;
    case 'pair':
      if (fromPopup) work = pair();
      break;
    case 'fill':
      if (fromPopup) work = fill(msg.tabId, msg.entry);
      break;
    case 'open':
      if (fromPopup) work = openApp();
      break;
    case 'submitted':
      if (sender.tab) work = onSubmitted(sender, msg);
      break;
    case 'pending':
      if (sender.tab) work = pendingFor(sender);
      break;
    case 'answer':
      if (sender.tab) work = answer(sender, msg);
      break;
    case 'username':
      if (sender.tab) work = rememberUsername(sender, msg);
      break;
  }
  if (!work) return false;
  work.then(
    (r) => sendResponse(r ?? null),
    () => sendResponse(null),
  );
  return true;
});
