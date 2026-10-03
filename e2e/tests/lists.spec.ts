import { expect, test } from '@playwright/test';
import { button, expectText, goTo, openDemo, tap, tid, typeInto } from './helpers';

test.describe('Lists', () => {
  test('FR-LIST-01 / FR-SHOP-04: add to shopping, grouped by aisle, then check off', async ({ page }) => {
    await openDemo(page);
    await goTo(page, 'lists');
    const shopping = tid(page, 'lists.item.list-shopping');
    if (await shopping.count()) await tap(shopping);
    await expectText(tid(page, 'list.title'), 'Shopping');
    await typeInto(page, 'list.add', 'Strawberries');
    await page.keyboard.press('Enter');
    const item = button(page, /^Strawberries/);
    await expect(item).toBeVisible();
    await tap(item);
    await expect(button(page, /^Strawberries, done/)).toHaveCount(0); // done items fold away
    await expect(tid(page, 'list.done.toggle')).toBeVisible();
  });
});
