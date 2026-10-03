import { Browser, expect, Page, test } from '@playwright/test';
import { button, goTo, tap, tid, typeInto } from './helpers';

async function pairedPage(browser: Browser, baseURL: string): Promise<Page> {
  const ctx = await browser.newContext({ baseURL, viewport: { width: 1920, height: 1080 }, timezoneId: 'America/Denver' });
  const page = await ctx.newPage();
  await page.goto('/?e2e=1&reset=1');
  await tap(tid(page, 'onboarding.hub'));
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
});
