import { expect, test } from '@playwright/test';
import { tap, tid } from './helpers';

test.describe('Onboarding', () => {
  test('FR-SET-01: first run offers the Hub or the demo', async ({ page }) => {
    await page.goto('/?e2e=1&reset=1');
    await expect(tid(page, 'screen.onboarding')).toBeVisible({ timeout: 90_000 });
    await expect(tid(page, 'onboarding.hub')).toBeVisible();
    await tap(tid(page, 'onboarding.demo'));
    await expect(tid(page, 'screen.home')).toBeVisible({ timeout: 30_000 });
    await expect(tid(page, 'home.demo')).toBeVisible();
  });

  test('FR-SET-01: the web app detects the Hub that serves it and pairs', async ({ page }, info) => {
    test.skip(info.project.name !== 'wall-l' && info.project.name !== 'phone', 'pairing covered on two layouts');
    await page.goto('/?e2e=1&reset=1');
    await tap(tid(page, 'onboarding.hub'));
    // The address is prefilled with the origin that served the app.
    await tap(tid(page, 'onboarding.connect'));
    // The test Hub auto-approves pairing; its demo household syncs down.
    await expect(tid(page, 'screen.home')).toBeVisible({ timeout: 60_000 });
    await expect(tid(page, 'home.date')).toBeVisible();
    await expect(tid(page, 'home.demo')).toHaveCount(0);
  });
});
