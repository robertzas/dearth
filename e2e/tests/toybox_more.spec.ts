import { expect, test } from '@playwright/test';
import { expectCheered, expectText, idsUnder, openToyboxGame, tap, textOf, tid, tids } from './helpers';

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

  test('FR-TOY-03: Word Pop — she pops three bubbles that say the word the voice asks for', async ({ page }) => {
    // Moving targets on a slow headless renderer: room for a few retries.
    test.setTimeout(240_000);
    await openToyboxGame(page, 'wordpop');
    await expectText(tid(page, 'wordpop.ask'), /^Pop the word \S+: 0 of 3$/);
    const word = (await textOf(tid(page, 'wordpop.ask'))).match(/Pop the word (\S+):/)![1];
    const height = page.viewportSize()!.height;
    // Headless frames are slow, so bubbles rise slowly and a tap can land
    // where one just was: find one in view, tap, and try again if the count
    // didn't move. Every bubble is read in one go and tapped by position: a
    // locator on a bubble that floats away or pops in between waits for it
    // to come back, forever.
    for (let k = 1; k <= 3; k++) {
      const want = k < 3 ? `Pop the word ${word}: ${k} of 3` : `Popped ${word}: 3 of 3`;
      await expect
        .poll(
          async () => {
            if ((await textOf(tid(page, 'wordpop.ask'))).includes(want)) return true;
            const bubbles = await tids(page, 'wordpop.bubble.').evaluateAll((els) =>
              els.map((e) => {
                const r = e.getBoundingClientRect();
                return { text: [e.getAttribute('aria-label'), e.textContent].filter(Boolean).join(' ').trim(), x: r.x + r.width / 2, y: r.y + r.height / 2 };
              }),
            );
            const hit = bubbles.find((b) => b.text === word && b.y > height * 0.2 && b.y < height * 0.92);
            if (!hit) return false;
            await page.mouse.click(hit.x, hit.y);
            await page.waitForTimeout(1500);
            return (await textOf(tid(page, 'wordpop.ask'))).includes(want);
          },
          { timeout: 90_000, intervals: [500] },
        )
        .toBe(true);
    }
    await expectCheered(page);
  });

  test('FR-TOY-03: Rocket Countdown — she taps the stars from five down to one and the rocket blasts off', async ({ page }) => {
    await openToyboxGame(page, 'rocket');
    await expectText(tid(page, 'rocket.ask'), 'Count down from 5: next 5');
    for (const n of [5, 4, 3, 2, 1]) {
      await tap(tid(page, `rocket.star.${n}`));
      await expectText(tid(page, `rocket.star.${n}`), `${n}, lit`);
    }
    // A lasting label: it stays until the next rocket rolls out.
    await expectText(tid(page, 'rocket.ask'), 'Blast off!');
    await expectCheered(page);
  });

  test('FR-TOY-03: Alphabet Train — she puts the letter that comes next into the empty carriage', async ({ page }) => {
    await openToyboxGame(page, 'train');
    await expectText(tid(page, 'train.ask'), /^What comes next\? [A-Z], [A-Z], _$/);
    const [first] = (await textOf(tid(page, 'train.ask'))).match(/[A-Z](?=,)/)!;
    const next = String.fromCharCode(first.charCodeAt(0) + 2);
    const blocks = await idsUnder(page, 'train.block.');
    let right = '';
    for (const id of blocks) if ((await textOf(tid(page, id))).trim() === next) right = id;
    expect(right).not.toBe('');
    await tap(tid(page, right));
    await expectText(tid(page, 'train.car.2'), next);
    await expectCheered(page);
  });

  test('FR-TOY-03: Number Fishing — she catches the fish with the number the voice calls', async ({ page }) => {
    await openToyboxGame(page, 'fishing');
    await expectText(tid(page, 'fishing.ask'), /^Find the number [1-5]$/);
    const n = (await textOf(tid(page, 'fishing.ask'))).trim().slice(-1);
    // The fish swim slowly; a tap that lands where it just was is tried again.
    await expect
      .poll(
        async () => {
          await tap(tid(page, `fishing.fish.${n}`));
          await page.waitForTimeout(800);
          return (await textOf(tid(page, 'fishing.ask'))).includes(`Caught ${n}`);
        },
        { timeout: 60_000, intervals: [500] },
      )
      .toBe(true);
    await expectCheered(page);
  });

  test('FR-TOY-03: Letter Creatures — she picks each part by its first sound and the creature dances', async ({ page }) => {
    await openToyboxGame(page, 'lettercreature');
    const words: Record<string, string[]> = {
      body: ['a round body', 'an egg body', 'a pear body', 'a square body', 'a fluffy body'],
      eyes: ['googly eyes', 'sleepy eyes', 'happy eyes', 'long eyelashes'],
    };
    for (const part of ['body', 'eyes']) {
      await expectText(tid(page, 'lettercreature.ask'), new RegExp(`^Find (a )?${part}: [A-Z]$`));
      const letter = (await textOf(tid(page, 'lettercreature.ask'))).trim().slice(-1).toLowerCase();
      // The part whose key word (the one that isn't "a" or "an") starts with the letter.
      let right = '';
      for (const id of await idsUnder(page, 'lettercreature.option.')) {
        const name = (await textOf(tid(page, id))).trim();
        const key = name.split(' ').filter((w) => w !== 'a' && w !== 'an')[0];
        if (words[part].includes(name) && key[0] === letter) right = id;
      }
      expect(right).not.toBe('');
      await tap(tid(page, right));
    }
    await expectText(tid(page, 'lettercreature.ask'), /^I'm a [A-Z][a-z]+$/);
    await expectCheered(page);
  });
});
