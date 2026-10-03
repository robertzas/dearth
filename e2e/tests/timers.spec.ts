import { expect, test } from '@playwright/test';
import { expectText, openDemo, tap, tid } from './helpers';

/** Opens the timers sheet from the rail, or from More where there's no rail. */
async function openTimers(page: import('@playwright/test').Page): Promise<void> {
  if (await tid(page, 'nav.timers').count()) {
    await tap(tid(page, 'nav.timers'));
  } else {
    await tap(tid(page, 'nav.more'));
    await tap(tid(page, 'more.timers'));
  }
  await expect(tid(page, 'timers.sheet')).toBeVisible();
}

test.describe('Kitchen timers', () => {
  test('FR-TMR-01: a preset starts a timer; the pill counts down on every screen; cancel ends it', async ({ page }) => {
    await openDemo(page);
    await openTimers(page);
    await tap(tid(page, 'timers.preset.3'));
    const left = page.locator('[flt-semantics-identifier^="timer."][flt-semantics-identifier$=".left"]');
    await expectText(left, /3 min timer: [23]:\d\d left/);
    await tap(tid(page, 'sheet.close'));
    await expectText(tid(page, 'timers.pill'), /3 min timer · [23]:\d\d/);
    // Pause from the sheet the pill opens; the pill says so.
    await tap(tid(page, 'timers.pill'));
    await tap(page.locator('[flt-semantics-identifier^="timer."][flt-semantics-identifier$=".pause"]'));
    await tap(tid(page, 'sheet.close'));
    await expectText(tid(page, 'timers.pill'), 'paused');
    await tap(tid(page, 'timers.pill'));
    await tap(page.locator('[flt-semantics-identifier^="timer."][flt-semantics-identifier$=".cancel"]'));
    await tap(tid(page, 'sheet.close'));
    await expect(tid(page, 'timers.pill')).toHaveCount(0);
  });
});
