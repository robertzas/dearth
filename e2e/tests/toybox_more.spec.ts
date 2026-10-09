import { expect, test } from '@playwright/test';
import { expectCheered, expectText, idsUnder, openToyboxGame, tap, textOf, tid } from './helpers';

// The Toybox's second set of number and letter games (SPEC FR-TOY-03),
// built on the games played most, played from what the screen shows
// (labels). The widget tests check which clips play.

test.describe('Toybox second set', () => {
  test('FR-TOY-03: Cookie Count — she puts as many cookies on the plate as the monster asks for and rings the bell', async ({ page }) => {
    await openToyboxGame(page, 'cookies');
    await expectText(tid(page, 'cookies.ask'), /^I want \d+ cookies?$/);
    const want = Number((await textOf(tid(page, 'cookies.ask'))).match(/I want (\d+)/)![1]);
    expect(want).toBeGreaterThanOrEqual(1);
    for (let n = 1; n <= want; n++) {
      await tap(tid(page, 'cookies.jar'));
      // One cookie a tap: wait for it to land before the next.
      await expectText(tid(page, 'cookies.plate'), `Plate: ${n} cookie${n === 1 ? '' : 's'}`);
    }
    await tap(tid(page, 'cookies.bell'));
    // A lasting label: it stays until the next order.
    await expectText(tid(page, 'cookies.ask'), `Yum! ${want} cookie${want === 1 ? '' : 's'}`);
    await expectCheered(page);
  });

  test('FR-TOY-03: Letter Monster — she feeds the monster the letter it asks for', async ({ page }) => {
    await openToyboxGame(page, 'lettermonster');
    await expectText(tid(page, 'lettermonster.ask'), /^I want the letter [A-Z]$/);
    const letter = (await textOf(tid(page, 'lettermonster.ask'))).trim().slice(-1);
    const foods = await idsUnder(page, 'lettermonster.food.');
    expect(foods).toHaveLength(3);
    let right = '';
    for (const id of foods) if ((await textOf(tid(page, id))).trim() === `Letter ${letter}`) right = id;
    expect(right).not.toBe('');
    await tap(tid(page, right));
    // A lasting label: it stays until the next tray.
    await expectText(tid(page, 'lettermonster.ask'), `Yum! ${letter}`);
    await expectCheered(page);
  });

  test('FR-TOY-03: Bus Stop — kids climb on, and she picks how many are on the bus now', async ({ page }) => {
    await openToyboxGame(page, 'busstop');
    await expectText(tid(page, 'busstop.ask'), 'Here comes the bus');
    // The question comes once the last kid has climbed on.
    await expectText(tid(page, 'busstop.ask'), 'How many kids are on the bus now?', 30_000);
    const now = Number((await textOf(tid(page, 'busstop.bus'))).match(/Bus: (\d+) kids?/)![1]);
    const cards = await idsUnder(page, 'busstop.card.');
    expect(cards).toHaveLength(3);
    let right = '';
    for (const id of cards) if ((await textOf(tid(page, id))).trim() === `${now}`) right = id;
    expect(right).not.toBe('');
    await tap(tid(page, right));
    // A lasting label: it stays until the bus drives off.
    await expectText(tid(page, 'busstop.ask'), `${now} kid${now === 1 ? '' : 's'} on the bus`);
    await expectCheered(page);
  });
});
