import { expect, Page, test } from '@playwright/test';
import { expectCheered, expectRoundFinished, expectText, openToyboxGame, tap, textOf, tid, tids } from './helpers';

// The Toybox's make-and-move games (SPEC FR-TOY-03), played from what the
// screen shows (labels). The voice can't be heard here; the widget tests
// check which clips play.

const label = async (page: Page, id: string): Promise<string> => (await textOf(tid(page, id))).trim();

/** "Wobblesaurus, pink: a round body, googly eyes[, dancing]" in parts. */
function creature(text: string): { name: string; paint: string; parts: string[] } {
  const [head, parts] = text.split(': ');
  const [name, paint] = head.split(', ');
  return { name, paint, parts: parts.replace(/, dancing$/, '').split(', ') };
}

test.describe('Toybox make-and-move games', () => {
  test('FR-TOY-03: Build-a-Creature — she gives it a new face and a new paint, then it dances', async ({ page }) => {
    await openToyboxGame(page, 'creature');
    await expectText(tid(page, 'creature.me'), /^\w+, \w+: /);
    const before = creature(await label(page, 'creature.me'));
    await tap(tid(page, 'creature.part.face'));
    await expect.poll(async () => creature(await label(page, 'creature.me')).parts[1]).not.toBe(before.parts[1]);
    const after = creature(await label(page, 'creature.me'));
    expect(after.parts[0]).toBe(before.parts[0]); // the same body
    expect(after.name).not.toBe(before.name); // the face is the end of its name

    // Level 1 has four paints; pick one it isn't wearing.
    const paints = ['pink', 'blue', 'green', 'purple'];
    const next = (paints.indexOf(after.paint) + 1) % paints.length;
    await tap(tid(page, `creature.color.${next}`));
    await expectText(tid(page, 'creature.me'), `, ${paints[next]}: `);

    await tap(tid(page, 'creature.dance'));
    await expectText(tid(page, 'creature.me'), 'dancing');
    await expect.poll(() => label(page, 'creature.me'), { timeout: 15_000 }).not.toContain('dancing');
  });

  test('FR-TOY-03: Freeze Dance — the buddy dances, freezes when the music stops, and dances again', async ({ page }) => {
    await openToyboxGame(page, 'freeze');
    await expectText(tid(page, 'freeze.state'), /^Dancing/);
    await expectText(tid(page, 'freeze.state'), 'Frozen', 25_000);
    await expectText(tid(page, 'freeze.state'), /^Dancing/, 15_000);
  });

  test('FR-TOY-03: Music Sequencer — the playhead loops and she lights a square for the cat', async ({ page }) => {
    await openToyboxGame(page, 'sequencer');
    await expectText(tid(page, 'seq.board'), /^Step \d of 4$/);
    await expectText(tid(page, 'seq.cell.cat.1'), 'Cat 2: off');
    await tap(tid(page, 'seq.cell.cat.1'));
    await expectText(tid(page, 'seq.cell.cat.1'), 'Cat 2: on');
    // Still looping after the change.
    const first = await label(page, 'seq.board');
    await expect.poll(() => label(page, 'seq.board')).not.toBe(first);
  });

  test('FR-TOY-03: Weather Dress-Up — she dresses Buddy for the day, trying things until one suits', async ({ page }) => {
    await openToyboxGame(page, 'dressup');
    await expectText(tid(page, 'dress.buddy'), 'Buddy: 0 of 1 dressed');
    // Try each choice she hasn't tried yet, as she would, until one goes on
    // (a few passes: on a slow runner a tap can land before the round settles).
    for (let pass = 0; pass < 3 && !(await label(page, 'dress.buddy')).startsWith('Buddy: 1 of 1'); pass++) {
      const choices = await tids(page, 'dress.item.').evaluateAll((els) => els.map((e) => e.getAttribute('flt-semantics-identifier')!));
      for (const id of choices) {
        if ((await label(page, id)).endsWith('tried')) continue;
        await tap(tid(page, id));
        await page.waitForTimeout(600);
        if ((await label(page, 'dress.buddy')).startsWith('Buddy: 1 of 1')) break;
      }
    }
    await expectText(tid(page, 'dress.buddy'), /^Buddy: 1 of 1 dressed, \w+/);
    await expectText(tid(page, 'dress.ask'), 'Ready to go outside');
  });

  test("FR-TOY-03: Who's That? — the voice asks for someone and she finds their face", async ({ page }) => {
    // The demo family with face photos (no Hub: they draw as their emoji).
    await openToyboxGame(page, 'whosthat', 'faces=1');
    const ask = await label(page, 'who.ask');
    expect(ask).toMatch(/^Where (are you|is (Mom|Dad|Biscuit))\?$/);
    const who = ask === 'Where are you?' ? 'p-ava' : { 'Where is Mom?': 'p-mom', 'Where is Dad?': 'p-dad', 'Where is Biscuit?': 'p-biscuit' }[ask]!;
    await tap(tid(page, `who.face.${who}`));
    // The next round comes in three seconds: the lasting cheer count, not the "found" labels.
    await expectCheered(page);
  });

  test('FR-TOY-03: Story Time — she picks a book, turns every page, and it ends', async ({ page }) => {
    await openToyboxGame(page, 'storytime');
    await expectText(tid(page, 'story.ask'), 'Pick a story');
    await tap(tid(page, 'story.book.duck'));
    await expectText(tid(page, 'story.page'), 'Page 1 of 4: Duck goes for a walk.');
    for (const n of [2, 3, 4]) {
      await tap(tid(page, 'story.next'));
      await expectText(tid(page, 'story.page'), new RegExp(`^Page ${n} of 4: `));
    }
    // Read to the end, quietly: no cheer, but the round is recorded.
    await expectRoundFinished(page);
    await tap(tid(page, 'story.shelf'));
    await expectText(tid(page, 'story.ask'), 'Pick a story');
  });
});
