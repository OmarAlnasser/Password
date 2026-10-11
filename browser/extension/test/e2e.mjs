// End-to-end check of the extension in a real Chromium, driven by
// test/tool/extension_e2e_test.dart (which runs the app's side: a real vault,
// the bridge and the browser helper). Not part of the extension.
//
// Environment: PLAYWRIGHT (path of playwright's index.mjs), EXT_DIR,
// USER_DATA_DIR (with NativeMessagingHosts/ already written), ORIGIN
// (https://github.com:<port>).

const { chromium } = await import(process.env.PLAYWRIGHT);
const ext = process.env.EXT_DIR;
const origin = process.env.ORIGIN;
const id = 'hanpnpoopbcidkdgeknbinmkhlkfmecf';

function step(text) {
  console.log(`STEP ${text}`);
}

function check(ok, text) {
  if (!ok) throw new Error(`FAILED: ${text}`);
}

const ctx = await chromium.launchPersistentContext(process.env.USER_DATA_DIR, {
  channel: 'chromium',
  headless: true,
  ignoreHTTPSErrors: true,
  args: [
    `--disable-extensions-except=${ext}`,
    `--load-extension=${ext}`,
    '--host-resolver-rules=MAP github.com 127.0.0.1',
    '--no-proxy-server',
  ],
});

try {
  let [sw] = ctx.serviceWorkers();
  if (!sw) sw = await ctx.waitForEvent('serviceworker', { timeout: 15000 });
  check(sw.url().startsWith(`chrome-extension://${id}/`), 'extension id');

  async function tabIdOf(url) {
    return sw.evaluate(async (u) => {
      const tabs = await chrome.tabs.query({});
      return tabs.find((t) => (t.url || '').startsWith(u)).id;
    }, url);
  }

  async function prompt(page) {
    // The prompt is a closed shadow root: find its host by its style, and
    // click its buttons where they are drawn.
    const box = await page.waitForFunction(
      () => {
        const host = [...document.documentElement.querySelectorAll('div')].find(
          (d) => d.style.zIndex === '2147483647',
        );
        if (!host) return null;
        const r = host.getBoundingClientRect();
        return r.width > 100 ? { x: r.x, y: r.y, w: r.width, h: r.height } : null;
      },
      null,
      { timeout: 15000 },
    );
    return box.jsonValue();
  }

  const page = await ctx.newPage();
  step('open the login page');
  await page.goto(`${origin}/login`);

  step('popup: pair');
  const popup = await ctx.newPage();
  await popup.goto(`chrome-extension://${id}/popup.html?tab=${await tabIdOf(origin)}`);
  const code = await popup.locator('.code').textContent({ timeout: 15000 });
  check(/^\d{3} \d{3}$/.test(code), `pairing code "${code}"`);
  console.log(`CODE ${code}`);
  await popup.locator('button.primary').click();

  step('popup: list and fill');
  await popup.locator('button.entry').first().waitFor({ timeout: 20000 });
  const titles = await popup.locator('button.entry .title').allTextContents();
  check(titles.length === 2, `two logins for github.com, got ${titles}`);
  await popup
    .locator('button.entry', { hasText: 'someone@example.test' })
    .click();
  await page.waitForFunction(
    () => document.querySelector('input[type=password]').value !== '',
    null,
    { timeout: 10000 },
  );
  check(
    (await page.inputValue('input[name=email]')) === 'someone@example.test',
    'username filled',
  );
  check((await page.inputValue('input[name=pw]')) === 'old-pass-1', 'password filled');

  step('sign in with a new password: update prompt');
  await page.fill('input[name=pw]', 'new-pass-9');
  await page.click('button[type=submit]');
  await page.waitForURL(`${origin}/done`);
  let b = await prompt(page);
  await page.mouse.click(b.x + b.w - 44, b.y + b.h - 31);
  console.log('UPDATED');

  step('sign in as someone new: save prompt');
  await page.goto(`${origin}/login`);
  await page.fill('input[name=email]', 'third@example.test');
  await page.fill('input[name=pw]', 'brand-new-1');
  await page.press('input[name=pw]', 'Enter');
  await page.waitForURL(`${origin}/done`);
  b = await prompt(page);
  await page.mouse.click(b.x + b.w - 44, b.y + b.h - 31);
  console.log('SAVED');

  step('same password again: no prompt');
  await page.goto(`${origin}/login`);
  await page.fill('input[name=email]', 'third@example.test');
  await page.fill('input[name=pw]', 'brand-new-1');
  await page.click('button[type=submit]');
  await page.waitForURL(`${origin}/done`);
  await page.waitForTimeout(1500);
  const again = await page.evaluate(
    () => [...document.querySelectorAll('div')].some((d) => d.style.zIndex === '2147483647'),
  );
  check(!again, 'no prompt for a login Khazna already has');

  // Give the last save a moment to reach the app.
  await page.waitForTimeout(500);
  console.log('E2E OK');
} finally {
  await ctx.close();
}
