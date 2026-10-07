import { expect, Page, test } from '@playwright/test';
import { expectText, openToyboxGame, tap, textOf, tid, tids } from './helpers';

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
    // Try each choice in turn, as she would, until one goes on.
    const choices = await tids(page, 'dress.item.').evaluateAll((els) => els.map((e) => e.getAttribute('flt-semantics-identifier')!));
    for (const id of choices) {
      await tap(tid(page, id));
      await page.waitForTimeout(600);
      if ((await label(page, 'dress.buddy')).startsWith('Buddy: 1 of 1')) break;
    }
    await expectText(tid(page, 'dress.buddy'), /^Buddy: 1 of 1 dressed, \w+/);
    await expectText(tid(page, 'dress.ask'), 'Ready to go outside');
  });
});
