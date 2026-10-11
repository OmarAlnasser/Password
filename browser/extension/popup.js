// Khazna browser extension: the toolbar popup.

const t = (name, subs) => chrome.i18n.getMessage(name, subs) || name;
const main = document.getElementById('main');

document.documentElement.lang = chrome.i18n.getUILanguage();
document.documentElement.dir = chrome.i18n.getMessage('@@bidi_dir') || 'ltr';
document.getElementById('name').textContent = t('extName');

let tabId = null;

function el(tag, props = {}, children = []) {
  const e = document.createElement(tag);
  Object.assign(e, props);
  for (const c of children) e.append(c);
  return e;
}

function show(...nodes) {
  main.replaceChildren(...nodes);
}

function message(text, { muted = false } = {}) {
  return el('p', { textContent: text, className: muted ? 'muted' : '' });
}

function button(text, onClick) {
  const b = el('button', { textContent: text, className: 'primary' });
  b.addEventListener('click', onClick);
  return b;
}

function ask(cmd, extra = {}) {
  return chrome.runtime.sendMessage({ cmd, tabId, ...extra }).catch(() => null);
}

async function refresh() {
  show(message(t('loading'), { muted: true }));
  const s = (await ask('state')) || { status: 'error' };
  render(s);
}

function render(s) {
  switch (s.status) {
    case 'not_installed':
      show(message(t('notInstalled')), message(t('notInstalledHint'), { muted: true }));
      return;
    case 'app_not_running':
      show(
        message(t('appNotRunning')),
        button(t('openKhazna'), async () => {
          await ask('open');
          setTimeout(refresh, 2500);
        }),
      );
      return;
    case 'not_paired': {
      const pairButton = button(t('pair'), async () => {
        pairButton.disabled = true;
        pairButton.textContent = t('pairWaiting');
        const r = await ask('pair');
        if (r && r.ok) {
          refresh();
        } else {
          pairButton.disabled = false;
          pairButton.textContent = t('pair');
          main.append(
            message(r && r.error === 'busy' ? t('pairBusy') : t('pairDenied'), {
              muted: true,
            }),
          );
        }
      });
      show(
        message(t('notPaired')),
        el('div', { className: 'code', textContent: s.code || '' }),
        message(t('pairHint'), { muted: true }),
        pairButton,
      );
      return;
    }
    case 'locked':
      show(
        message(t('locked')),
        button(t('showKhazna'), () => ask('open')),
      );
      return;
    case 'no_vault':
      show(message(t('noVault')), button(t('showKhazna'), () => ask('open')));
      return;
    case 'insecure':
    case 'insecure_page':
      show(message(t('insecure')));
      return;
    case 'unlocked':
      renderEntries(s);
      return;
    default:
      show(message(t('error')), button(t('retry'), refresh));
  }
}

function renderEntries(s) {
  const nodes = [];
  const entries = s.entries || [];
  if (!entries.length) {
    nodes.push(
      message(t('noLogins', [s.host])),
      message(t('noLoginsHint'), { muted: true }),
    );
  } else {
    const list = el('ul');
    for (const e of entries) {
      const b = el('button', { className: 'entry' }, [
        el('span', { className: 'title', textContent: e.title || s.host }),
        el('span', { className: 'user ltr', textContent: e.username || '—' }),
      ]);
      b.addEventListener('click', async () => {
        const r = await ask('fill', { entry: e.id });
        if (r && r.ok) {
          window.close();
          return;
        }
        main.append(
          message(r && r.error === 'locked' ? t('locked') : t('fillFailed'), {
            muted: true,
          }),
        );
      });
      list.append(el('li', {}, [b]));
    }
    nodes.push(list);
  }
  if (s.appVersion && s.version && s.appVersion !== s.version) {
    nodes.push(el('div', { className: 'note', textContent: t('versionMismatch') }));
  }
  show(...nodes);
}

// The tab the popup is for: the active one. (`?tab=<id>` names another, for
// the end-to-end test, which opens the popup as a page.)
const named = Number(new URLSearchParams(location.search).get('tab'));
if (named) {
  tabId = named;
  refresh();
} else {
  chrome.tabs.query({ active: true, currentWindow: true }).then((tabs) => {
    tabId = tabs[0] ? tabs[0].id : null;
    refresh();
  });
}
