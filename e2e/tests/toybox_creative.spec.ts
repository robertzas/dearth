import { expect, Page, test } from '@playwright/test';
import { expectText, openToyboxGame, tap, textOf, tid } from './helpers';

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
});
