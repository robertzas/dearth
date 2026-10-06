import { expect, Page, test } from '@playwright/test';
import { expectCheered, expectText, idsUnder, openToyboxGame, tap, textOf, tid } from './helpers';

// The Toybox's voice games (SPEC FR-TOY-03), played from what the screen
// shows (labels). The voice itself can't be heard here; the widget tests
// check which clips play. Ava is 2½ in the demo, so each game is opened
// early from Settings first.

const label = async (page: Page, id: string): Promise<string> => (await textOf(tid(page, id))).trim();

/** Draws a finger through the current stroke's waypoints, as she would. */
async function traceStroke(page: Page): Promise<void> {
  const points: { x: number; y: number }[] = [];
  for (let i = 0; await tid(page, `trace.point.${i}`).count(); i++) {
    const b = (await tid(page, `trace.point.${i}`).first().boundingBox())!;
    points.push({ x: b.x + b.width / 2, y: b.y + b.height / 2 });
  }
  await page.mouse.move(points[0].x, points[0].y);
  await page.mouse.down();
  // Waypoints are close enough for one step each (and every step is a
  // frame: headless Chrome draws a wall-sized board slowly).
  for (const p of points.slice(1)) await page.mouse.move(p.x, p.y, { steps: 2 });
  await page.mouse.up();
}

/** Traces the glyph on the board, stroke by stroke. */
async function traceGlyph(page: Page): Promise<void> {
  for (let s = 0; s < 8 && !(await label(page, 'trace.board')).endsWith('traced'); s++) {
    await traceStroke(page);
    await page.waitForTimeout(300);
  }
  await expectText(tid(page, 'trace.board'), 'traced');
}

test.describe('Toybox voice games', () => {
  test('FR-TOY-03: Letter Sounds — she taps each letter to hear it and see its picture', async ({ page }) => {
    await openToyboxGame(page, 'letters', true);
    await expectText(tid(page, 'letters.ask'), 'Tap a letter');
    for (const id of await idsUnder(page, 'letters.letter.')) {
      await tap(tid(page, id));
      await expectText(tid(page, id), 'heard');
    }
    await expectCheered(page, 10_000);
  });

  test('FR-TOY-03: Rhyme Time — she listens to the pictures until she finds the rhyme', async ({ page }) => {
    await openToyboxGame(page, 'rhymes', true);
    await expectText(tid(page, 'rhymes.ask'), /What rhymes with \w+\?/);
    for (const id of await idsUnder(page, 'rhymes.choice.')) {
      if ((await label(page, 'rhymes.ask')).includes('they rhyme')) break;
      await tap(tid(page, id));
      await page.waitForTimeout(300);
    }
    await expectText(tid(page, 'rhymes.ask'), 'they rhyme!');
  });

  test('FR-TOY-03: I Spy — she finds the thing of the color the voice spies', async ({ page }) => {
    await openToyboxGame(page, 'ispy', true);
    await expectText(tid(page, 'ispy.ask'), /I spy something \w+/);
    const color = (await label(page, 'ispy.ask')).split(' ').pop()!;
    const things = await idsUnder(page, 'ispy.thing.');
    expect(things.length).toBe(4);
    for (const id of things) {
      if ((await label(page, id)).split(', ').includes(color)) {
        await tap(tid(page, id));
        break;
      }
    }
    await expectText(tid(page, 'ispy.ask'), 'You found it');
    await expectCheered(page);
  });

  test('FR-TOY-03: Letter & Name Tracing — a scribble draws nothing, a finger along the dots traces the line', async ({ page }) => {
    await openToyboxGame(page, 'tracing', true);
    await expectText(tid(page, 'tracing.ask'), 'Trace the line');
    await expectText(tid(page, 'trace.board'), /: 0 of \d done/);
    await traceGlyph(page);
    // The cheer can be over before a slow drag ends; the pill stays a while.
    await expectText(tid(page, 'tracing.ask'), 'All traced!');
  });

  test('FR-TOY-03: Number Tracing — the number is traced, then counted out', async ({ page }) => {
    await openToyboxGame(page, 'numbers', true);
    await expectText(tid(page, 'numbers.ask'), /Trace \d/);
    const n = (await label(page, 'numbers.ask')).replace('Trace ', '');
    await traceGlyph(page);
    await expectText(tid(page, 'numbers.ask'), `${n}!`);
    await expectText(tid(page, 'numbers.count'), `${n} of ${n}`);
  });

  test('FR-TOY-03: Breathing Buddy — a tap on the balloon starts slow breaths', async ({ page }) => {
    await openToyboxGame(page, 'breathe', true);
    await expectText(tid(page, 'breathe.ask'), 'Tap the balloon');
    await tap(tid(page, 'breathe.balloon'));
    await expectText(tid(page, 'breathe.ask'), 'Breathe in', 10_000);
    await expectText(tid(page, 'breathe.flower'), 'now');
    await expectText(tid(page, 'breathe.ask'), 'Breathe out', 10_000);
    await expectText(tid(page, 'breathe.candle'), 'now');
    await expectText(tid(page, 'breathe.dots'), '1 of 3 breaths', 12_000);
  });
});
