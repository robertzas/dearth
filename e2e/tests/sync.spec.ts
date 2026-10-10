import { Browser, expect, Page, test } from '@playwright/test';
import { button, expectText, goTo, replaceText, scrollTo, tap, textOf, tid, tids, typeInto } from './helpers';

async function pairedPage(browser: Browser, baseURL: string, name?: string): Promise<Page> {
  const ctx = await browser.newContext({ baseURL, viewport: { width: 1920, height: 1080 }, timezoneId: 'America/Denver' });
  const page = await ctx.newPage();
  await page.goto('/?e2e=1&reset=1');
  await tap(tid(page, 'onboarding.hub'));
  if (name) await replaceText(page, 'onboarding.name', name);
  await tap(tid(page, 'onboarding.connect'));
  await expect(tid(page, 'screen.home')).toBeVisible({ timeout: 60_000 });
  return page;
}

test.describe('Sync', () => {
  test('§8.4 FR-LIST-01: a change on one display appears on another within seconds', async ({ browser, baseURL }, info) => {
    test.skip(info.project.name !== 'wall-l', 'multi-device sync runs once');
    const a = await pairedPage(browser, baseURL!);
    const b = await pairedPage(browser, baseURL!);
    await goTo(a, 'lists');
    await goTo(b, 'lists');
    const name = `Sync check ${Date.now() % 100000}`;
    await typeInto(a, 'list.add', name);
    await a.keyboard.press('Enter');
    await expect(button(a, new RegExp(name))).toBeVisible();
    await expect(button(b, new RegExp(name))).toBeVisible({ timeout: 10_000 });
    // And back: B checks it off, A sees it move to the checked fold.
    await tap(button(b, new RegExp(name)));
    await expect(button(a, new RegExp(name))).toHaveCount(0, { timeout: 10_000 });
  });

  test('FR-ADM-01: a grown-up removes another display in Settings; it is unpaired at once', async ({ browser, baseURL }, info) => {
    test.skip(info.project.name !== 'wall-l', 'multi-device journeys run once');
    const a = await pairedPage(browser, baseURL!);
    const name = `Spare ${Date.now() % 100000}`;
    const b = await pairedPage(browser, baseURL!, name);
    await goTo(a, 'settings');
    await tap(tid(a, 'settings.nav.hub'));
    // The Hub lists every display paired in this run; find the spare one.
    let rowId = '';
    await expect
      .poll(async () => {
        for (const row of await tids(a, 'hub.device.').all()) {
          const id = (await row.getAttribute('flt-semantics-identifier')) ?? '';
          if (!id.endsWith('.remove') && (await textOf(row)).includes(name)) rowId = id;
        }
        return rowId;
      }, { timeout: 30_000 })
      .not.toBe('');
    await tap(await scrollTo(a, `${rowId}.remove`));
    await tap(tid(a, 'dialog.confirm.ok'));
    await expect(tid(a, rowId)).toHaveCount(0, { timeout: 15_000 });
    await expectText(tid(b, 'home.sync'), 'Unpaired', 15_000);
  });

  test('FR-ADM-04: Settings → Updates shows the Hub’s version; a Hub without its updater only tells', async ({ browser, baseURL }, info) => {
    test.skip(info.project.name !== 'wall-l', 'Hub journeys run once');
    const a = await pairedPage(browser, baseURL!);
    await goTo(a, 'settings');
    // The section list is lazy and Updates is near its end: search for it.
    await typeInto(a, 'settings.search', 'updates');
    await tap(tid(a, 'settings.nav.updates'));
    await expectText(tid(a, 'updates.hub.status'), /Dearth Hub \S+/);
    await expect(tid(a, 'updates.hub.check')).toBeVisible();
    // The test Hub runs without the Watchtower beside it (compose.yml).
    await expect(tid(a, 'updates.hub.install')).toHaveCount(0);
    await expect(tid(a, 'updates.hub.mode.nightly')).toHaveCount(0);
  });
});
