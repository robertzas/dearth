import { expect, test } from '@playwright/test';
import { expectText, goTo, openDemo, scrollTo, tap, tid, tids } from './helpers';

// The Toybox (SPEC §10.8). Demo: Ava is 2½, so the 3+ games stay hidden.
// The demo has no PINs, so the grown-up corner opens the settings directly.

test.describe('Toybox', () => {
  test('FR-TOY-01: Ava’s Toybox shows her games; one opens full screen and the house goes home', async ({ page }) => {
    await openDemo(page);
    await goTo(page, 'toybox');
    await expectText(tid(page, 'toybox.title'), 'Ava’s Toybox');
    await expect(tid(page, 'toybox.game.farm')).toBeVisible();
    await expect(tid(page, 'toybox.game.counting')).toHaveCount(0);
    await expect(tid(page, 'toybox.new.farm')).toBeVisible();
    await tap(tid(page, 'toybox.game.farm'));
    await expect(tid(page, 'screen.game')).toBeVisible();
    await tap(tid(page, 'game.home'));
    await expect(tid(page, 'screen.toybox')).toBeVisible();
    await expect(tid(page, 'toybox.new.farm')).toHaveCount(0);
  });

  test('FR-TOY-02: on the farm, a tapped animal says hello with its name', async ({ page }) => {
    await openDemo(page, '/toybox');
    await tap(tid(page, 'toybox.game.farm'));
    const animal = tids(page, 'farm.animal.').first();
    const id = (await animal.getAttribute('flt-semantics-identifier'))!.replace('farm.animal.', '');
    await tap(animal);
    await expect(tid(page, `farm.says.${id}`)).toBeVisible();
    await expectText(tid(page, `farm.says.${id}`), '·');
  });

  test('FR-TOY-02: the parrot plays a tune, then it’s her turn', async ({ page }) => {
    await openDemo(page, '/toybox');
    await tap(await scrollTo(page, 'toybox.game.music'));
    await tap(tid(page, 'music.bar.0'));
    await tap(tid(page, 'music.drum.kick'));
    await tap(tid(page, 'music.echo'));
    await expectText(tid(page, 'music.echo'), 'Your turn');
  });

  test('FR-TOY-05: a daily budget from the grown-up corner shows the time left', async ({ page }) => {
    await openDemo(page, '/toybox');
    await expect(tid(page, 'toybox.timeleft')).toHaveCount(0);
    const corner = tid(page, 'toybox.grownups');
    const box = (await corner.boundingBox())!;
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(3300);
    await page.mouse.up();
    await expect(tids(page, 'screen.settings').first()).toBeVisible();
    await tap(await scrollTo(page, 'toybox.budget.15-min'));
    await goTo(page, 'toybox');
    await expectText(tid(page, 'toybox.timeleft'), '15 min');
  });
});
