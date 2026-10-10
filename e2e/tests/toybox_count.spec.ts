import { expect, test } from '@playwright/test';
import { expectCheered, expectText, openToyboxGame, tap, textOf, tid } from './helpers';

// The Toybox's third set, six number games built on her longest-played
// games (SPEC FR-TOY-03), played from what the screen shows (labels). The
// widget tests check which clips play.

test.describe('Toybox third set', () => {
  test('FR-TOY-03: Creature Count — she gives the creature as many parts as the voice asks for and makes it dance', async ({ page }) => {
    await openToyboxGame(page, 'creaturecount');
    await expectText(tid(page, 'creaturecount.ask'), /^Give it \d+ (eye|leg|horn|spot)s?$/);
    const [, n, part] = (await textOf(tid(page, 'creaturecount.ask'))).match(/Give it (\d+) (eye|leg|horn|spot)/)!;
    for (let i = 1; i <= Number(n); i++) {
      await tap(tid(page, `creaturecount.add.${part}s`));
      // One part a tap: wait for it to land before the next.
      await expectText(tid(page, 'creaturecount.creature'), `Creature: ${i} ${part}${i === 1 ? '' : 's'}`);
    }
    await tap(tid(page, 'creaturecount.dance'));
    // A lasting label: it stays until the next creature.
    await expectText(tid(page, 'creaturecount.ask'), /^Yay! /);
    await expectCheered(page);
  });
});
