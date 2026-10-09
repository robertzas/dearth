import { expect, test } from '@playwright/test';
import { expectText, scrollTo, tap, tid, typeInto } from './helpers';

test.describe('Onboarding', () => {
  test('FR-SET-01: first run offers the Hub or the demo', async ({ page }) => {
    await page.goto('/?e2e=1&reset=1');
    await expect(tid(page, 'screen.onboarding')).toBeVisible({ timeout: 90_000 });
    await expect(tid(page, 'onboarding.hub')).toBeVisible();
    // A browser can't run the built-in Hub (SPEC §7.2 Solo mode): no such option on the web.
    await expect(tid(page, 'onboarding.solo')).toHaveCount(0);
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

  test('FR-SET-01: "Just the Toybox" sets the device up as one child\'s Toybox, with nothing else on it', async ({ page }) => {
    await page.goto('/?e2e=1&reset=1');
    await expect(tid(page, 'screen.onboarding')).toBeVisible({ timeout: 90_000 });
    await tap(tid(page, 'onboarding.toybox'));
    await typeInto(page, 'onboarding.toybox.kid', 'Mia');
    await tap(tid(page, 'onboarding.toybox.age.4'));
    await typeInto(page, 'onboarding.toybox.grownup', 'Mama');
    await typeInto(page, 'onboarding.toybox.pin', '2468');
    await tap(tid(page, 'onboarding.toybox.start'));
    await expect(tid(page, 'screen.toybox')).toBeVisible({ timeout: 30_000 });
    await expectText(tid(page, 'toybox.title'), 'Mia’s Toybox');
    // No navigation: the Toybox is all there is.
    await expect(tid(page, 'nav.calendar')).toHaveCount(0);
    await tap(await scrollTo(page, 'toybox.game.bubbles'));
    await expect(tid(page, 'game.bubbles')).toBeVisible();
  });
});
