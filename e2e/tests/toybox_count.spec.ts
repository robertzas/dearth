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

  test('FR-TOY-03: Snack Snap — she taps the plate with the number of treats the monster asks for', async ({ page }) => {
    await openToyboxGame(page, 'snacksnap');
    await expectText(tid(page, 'snacksnap.ask'), /^Snack: (\d+) treats?$/);
    const want = (await textOf(tid(page, 'snacksnap.ask'))).match(/^Snack: (\d+) treats?$/)![1];
    // The plates are labelled by what they hold.
    const plates = await idsUnder(page, 'snacksnap.plate.');
    const wanted = `Plate with ${want} treat${want === '1' ? '' : 's'}`;
    const target = (await Promise.all(plates.map(async (id) => [id, await textOf(tid(page, id))] as const))).find(([, label]) => label === wanted)![0];
    await tap(tid(page, target));
    await expectText(tid(page, 'snacksnap.ask'), /^Yum! /);
    await expectCheered(page);
  });
});
