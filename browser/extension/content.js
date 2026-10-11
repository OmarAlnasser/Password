// Khazna browser extension: content script (top frame of https pages only).
//
// * Fills a login when the user picks one in the popup. Never on its own.
// * After the user signs in, offers to save the login or update its password
//   (the app decides whether there is anything to save).

(() => {
  if (window.__khaznaLoaded) return;
  window.__khaznaLoaded = true;

  const USER_HINT = /user|email|e-mail|login|account|identifier|ident|phone/i;
  const TEXTUAL = /^(text|email|tel|)$/i;
  const SUBMIT_TEXT =
    /sign ?in|log ?in|continue|next|submit|save|change|update|تسجيل|دخول|متابعة|التالي|حفظ|تغيير/i;

  // ---------------------------------------------------------------------------
  // Fields
  // ---------------------------------------------------------------------------

  function visible(el) {
    if (!el.isConnected) return false;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return false;
    const st = getComputedStyle(el);
    return st.visibility !== 'hidden' && st.display !== 'none' && st.opacity !== '0';
  }

  function usable(el) {
    return !el.disabled && !el.readOnly && visible(el);
  }

  function passwordFields(scope = document) {
    return [...scope.querySelectorAll('input[type="password"]')].filter(usable);
  }

  function textFields(scope) {
    return [...scope.querySelectorAll('input')].filter(
      (i) => TEXTUAL.test(i.type) && usable(i),
    );
  }

  function score(el) {
    const ac = (el.autocomplete || '').toLowerCase();
    if (/\b(username|email)\b/.test(ac)) return 3;
    if (el.type === 'email') return 2;
    if (USER_HINT.test(`${el.name} ${el.id} ${el.placeholder} ${el.getAttribute('aria-label') || ''}`)) {
      return 1;
    }
    return 0;
  }

  // The username field that goes with a password field: in the same form,
  // before it, the most username-like one (the closest on a tie).
  function usernameFieldFor(pw) {
    const scope = pw.form || pw.closest('form') || document;
    const before = textFields(scope).filter(
      (i) => i.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING,
    );
    let best = null;
    let bestScore = -1;
    for (const i of before) {
      const s = score(i);
      if (s >= bestScore) {
        best = i;
        bestScore = s;
      }
    }
    return best;
  }

  // The first step of a sign-in split over two pages: a username field and
  // no password field yet.
  function standaloneUsernameField() {
    let best = null;
    let bestScore = 0;
    for (const i of textFields(document)) {
      const s = score(i);
      if (s > bestScore) {
        best = i;
        bestScore = s;
      }
    }
    return best;
  }

  // Sets a value the way typing would, so pages built with React and the like
  // notice it.
  function setValue(el, value) {
    const setter = Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype,
      'value',
    ).set;
    el.focus();
    setter.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }

  function fill(username, password) {
    const pws = passwordFields();
    if (pws.length) {
      // Prefer a password field that has a username field before it.
      const pw = pws.find((p) => usernameFieldFor(p)) || pws[0];
      const user = usernameFieldFor(pw);
      if (user && username) setValue(user, username);
      setValue(pw, password);
      pw.focus();
      return true;
    }
    const user = standaloneUsernameField();
    if (user && username) {
      setValue(user, username);
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Sign-ins
  // ---------------------------------------------------------------------------

  let lastSent = '';
  let lastSentAt = 0;

  // The new password of a form: the only one, or on a change-password form
  // (current, new, confirm) the new one.
  function chosenPassword(fields) {
    const values = fields.map((f) => f.value).filter((v) => v);
    if (!values.length) return '';
    if (values.length === 1) return values[0];
    if (values.length === 2) return values[1];
    return values[1] === values[2] ? values[1] : values[values.length - 1];
  }

  function captureFrom(node) {
    const form = node && (node.form || (node.closest && node.closest('form')));
    const scope = form || document;
    const pws = [...scope.querySelectorAll('input[type="password"]')].filter(
      (p) => p.isConnected && p.value,
    );
    if (!pws.length) {
      const user = standaloneUsernameField();
      if (user && user.value) {
        send({ cmd: 'username', username: user.value });
      }
      return;
    }
    const password = chosenPassword(pws);
    const userField = usernameFieldFor(pws[0]);
    const username = userField ? userField.value : '';
    const sig = `${username}\u0000${password}`;
    if (sig === lastSent && Date.now() - lastSentAt < 3000) return;
    lastSent = sig;
    lastSentAt = Date.now();
    send({ cmd: 'submitted', username, password }).then((prompt) => {
      if (prompt) showPrompt(prompt);
    });
  }

  // A button that sends the form, not one that shows the password or opens a
  // menu.
  function submitLike(b) {
    if (b instanceof HTMLInputElement) return true;
    if (b instanceof HTMLButtonElement && b.form) return b.type === 'submit';
    const label = `${b.textContent || ''} ${b.getAttribute('aria-label') || ''}`;
    return SUBMIT_TEXT.test(label);
  }

  function send(msg) {
    try {
      return chrome.runtime.sendMessage(msg).catch(() => null);
    } catch (e) {
      // The extension was reloaded; this page has an orphaned script.
      return Promise.resolve(null);
    }
  }

  document.addEventListener(
    'submit',
    (e) => {
      if (e.isTrusted) captureFrom(e.target);
    },
    true,
  );
  document.addEventListener(
    'click',
    (e) => {
      if (!e.isTrusted || !(e.target instanceof Element)) return;
      const b = e.target.closest(
        'button, input[type="submit"], input[type="image"], [role="button"]',
      );
      if (b && submitLike(b)) captureFrom(b);
    },
    true,
  );
  document.addEventListener(
    'keydown',
    (e) => {
      if (e.isTrusted && e.key === 'Enter' && e.target instanceof HTMLInputElement) {
        captureFrom(e.target);
      }
    },
    true,
  );

  // ---------------------------------------------------------------------------
  // The prompt
  // ---------------------------------------------------------------------------

  const t = (name, subs) => chrome.i18n.getMessage(name, subs) || name;
  let promptHost = null;

  function showPrompt(p) {
    if (promptHost) promptHost.remove();
    const host = document.createElement('div');
    promptHost = host;
    host.style.cssText =
      'all: initial; position: fixed; top: 16px; inset-inline-end: 16px; z-index: 2147483647;';
    const root = host.attachShadow({ mode: 'closed' });
    const dir = chrome.i18n.getMessage('@@bidi_dir') || 'ltr';
    root.innerHTML = `
      <style>
        .card { font: 14px/1.45 system-ui, "Segoe UI", sans-serif; color: #F4F1FA;
          background: linear-gradient(160deg, #221437, #0B0814); border: 1px solid #4A3368;
          border-radius: 16px; padding: 14px 16px; width: 320px; box-sizing: border-box;
          box-shadow: 0 12px 40px rgba(0,0,0,.45); }
        .head { display: flex; align-items: center; gap: 8px; font-weight: 600; }
        .head img { width: 20px; height: 20px; border-radius: 6px; }
        .msg { margin: 8px 0 2px; }
        .sub { color: #AAA6BC; font-size: 13px; overflow: hidden; text-overflow: ellipsis;
          white-space: nowrap; direction: ltr; text-align: start; unicode-bidi: plaintext; }
        .row { display: flex; gap: 8px; justify-content: flex-end; margin-top: 12px; }
        button { font: inherit; border-radius: 999px; padding: 6px 14px; cursor: pointer;
          border: 1px solid #3A2D50; background: transparent; color: #D6CBE8; }
        button.yes { background: #8251D4; border-color: #8251D4; color: #fff; }
        button:focus-visible { outline: 2px solid #C9A8FF; outline-offset: 2px; }
      </style>
      <div class="card" role="dialog" dir="${dir}">
        <div class="head"><img alt=""><span></span></div>
        <div class="msg"></div>
        <div class="sub"></div>
        <div class="row"><button class="no"></button><button class="yes"></button></div>
      </div>`;
    root.querySelector('img').src = chrome.runtime.getURL('icons/icon32.png');
    root.querySelector('.head span').textContent = t('extName');
    root.querySelector('.msg').textContent =
      p.action === 'update' ? t('promptUpdate', [p.title]) : t('promptSave');
    root.querySelector('.sub').textContent = p.username
      ? `${p.username} · ${p.host}`
      : p.host;
    const yes = root.querySelector('.yes');
    const no = root.querySelector('.no');
    yes.textContent = p.action === 'update' ? t('update') : t('save');
    no.textContent = t('notNow');
    const done = (ok) => (e) => {
      // Only a real click: the page cannot answer for the user.
      if (!e.isTrusted) return;
      host.remove();
      if (promptHost === host) promptHost = null;
      send({ cmd: 'answer', nonce: p.nonce, yes: ok });
    };
    yes.addEventListener('click', done(true));
    no.addEventListener('click', done(false));
    (document.body || document.documentElement).appendChild(host);
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (sender.id !== chrome.runtime.id || !msg) return false;
    if (msg.cmd === 'fill') {
      // The page must still be the one the app matched.
      if (msg.origin !== location.origin) {
        sendResponse({ filled: false });
        return false;
      }
      sendResponse({ filled: fill(msg.username || '', msg.password || '') });
    }
    return false;
  });

  // A sign-in that moved to a new page: the prompt follows it.
  send({ cmd: 'pending' }).then((prompt) => {
    if (prompt) showPrompt(prompt);
  });
})();
