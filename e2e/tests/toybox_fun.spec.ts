import { expect, test } from '@playwright/test';
import { expectCheered, expectText, idsUnder, openToyboxGame, tap, textOf, tid } from './helpers';

// The Toybox's fourth set (SPEC FR-TOY-03, 2026-10-13): four number games
// for fun, played from what the screen shows (labels). The widget tests
// check which clips play.

test.describe('Toybox fourth set', () => {
  test('FR-TOY-03: Dice Dash — she rolls, and hops her buddy one square per dot', async ({ page }) => {
    await openToyboxGame(page, 'dice');
    await expectText(tid(page, 'dice.token'), 'On the start');
    await tap(tid(page, 'dice.die'));
    await expectText(tid(page, 'dice.ask'), /^Hop \d+ more$/);
    const n = Number((await textOf(tid(page, 'dice.ask'))).match(/Hop (\d+) more/)![1]);
    for (let k = 1; k <= n; k++) {
      await tap(tid(page, `dice.square.${k}`));
      await expectText(tid(page, 'dice.token'), `On square ${k}`);
    }
    await expectText(tid(page, 'dice.ask'), 'Roll the dice');
  });

  test('FR-TOY-03: Block Tower — she stacks as many blocks as asked and rings the bell', async ({ page }) => {
    await openToyboxGame(page, 'tower');
    await expectText(tid(page, 'tower.ask'), /^Build a tower \d+ blocks tall$/);
    const n = Number((await textOf(tid(page, 'tower.ask'))).match(/(\d+)/)![1]);
    for (let k = 1; k <= n; k++) {
      await tap(tid(page, 'tower.pile'));
      await expectText(tid(page, 'tower.tower'), `Tower: ${k} block`);
    }
    await tap(tid(page, 'tower.bell'));
    await expectCheered(page);
  });

  test('FR-TOY-03: Drum Count — the bear drums, and she picks how many beats', async ({ page }) => {
    test.setTimeout(90_000);
    await openToyboxGame(page, 'drums');
    await expectText(tid(page, 'drums.ask'), 'How many beats?', 40_000);
    const n = Number((await textOf(tid(page, 'drums.drum'))).match(/the bear played (\d+)/)![1]);
    await tap(tid(page, `drums.choice.${n}`));
    await expectCheered(page);
  });

  test('FR-TOY-03: Peekaboo Pals — some friends hide, and she says how many', async ({ page }) => {
    test.setTimeout(90_000);
    await openToyboxGame(page, 'peekaboo');
    await expectText(tid(page, 'peekaboo.ask'), /How many are hiding\? \d+ showing/, 60_000);
    const showing = Number((await textOf(tid(page, 'peekaboo.ask'))).match(/(\d+) showing/)![1]);
    const total = (await idsUnder(page, 'peekaboo.friend.')).length;
    expect(total).toBeGreaterThan(showing);
    await tap(tid(page, `peekaboo.choice.${total - showing}`));
    await expectCheered(page);
  });
});
