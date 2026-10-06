import { expect, test } from '@playwright/test';
import { expectText, idsUnder, openToyboxGame, tap, textOf, tid } from './helpers';

// The Toybox's number and letter games (SPEC FR-TOY-03), played from what
// the screen shows (labels). The voice itself can't be heard here; the
// widget tests check which clips play. Ava is 2½ in the demo, so each game
// is opened early from Settings first.

test.describe('Toybox number and letter games', () => {
  test('FR-TOY-03: Dot-to-Dot — she joins the dots in order and the picture appears', async ({ page }) => {
    await openToyboxGame(page, 'dots', true);
    await expectText(tid(page, 'dots.ask'), 'Start at 1');
    await expectText(tid(page, 'dots.board'), 'Join the dots: 0 of 5');
    const dots = await idsUnder(page, 'dots.dot.');
    expect(dots).toEqual(['dots.dot.1', 'dots.dot.2', 'dots.dot.3', 'dots.dot.4', 'dots.dot.5']);
    for (const id of dots) {
      await tap(tid(page, id));
      await expectText(tid(page, id), 'joined');
    }
    // The cheer can be over before a slow run reaches it; the label stays
    // until the next picture.
    await expectText(tid(page, 'dots.ask'), /^It's (a|an|the) [a-z ]+!$/);
  });

  test('FR-TOY-03: Big & Little Letters — each small letter finds its capital', async ({ page }) => {
    await openToyboxGame(page, 'biglittle', true);
    await expectText(tid(page, 'biglittle.ask'), 'Little letters find big letters');
    const bigs = await idsUnder(page, 'biglittle.big.');
    const littles = await idsUnder(page, 'biglittle.little.');
    expect(bigs).toHaveLength(3);
    expect(littles).toHaveLength(3);
    const capitals = new Map<string, string>();
    for (const id of bigs) capitals.set((await textOf(tid(page, id))).trim().replace('Big ', ''), id);
    for (const id of littles) {
      const letter = (await textOf(tid(page, id))).trim().replace('Little ', '');
      const card = capitals.get(letter.toUpperCase())!;
      await tap(tid(page, id));
      await tap(tid(page, card));
      await expectText(tid(page, card), `Big ${letter.toUpperCase()}, little ${letter}`);
    }
    // A lasting label: the cheer can be over before a slow run gets there.
    await expectText(tid(page, 'biglittle.ask'), 'All found!');
  });
});
