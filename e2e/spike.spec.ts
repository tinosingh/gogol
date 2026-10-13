import { expect, test } from '@playwright/test';

interface Result {
  count?: number;
  cspInherited?: boolean;
  error?: string;
  paused?: boolean;
}

async function settled(page: import('@playwright/test').Page): Promise<Result> {
  const result = page.locator('#result[data-state="done"]');
  await expect(result).toBeVisible();
  return JSON.parse((await result.textContent()) ?? '') as Result;
}

test('OPFS database persists through reload', async ({ page }) => {
  await page.goto('/spike.html');
  expect((await settled(page)).count).toBe(1);
  await page.reload();
  expect((await settled(page)).count).toBe(2);
});

test('pauseVfs hands the database to a second tab', async ({ browser }) => {
  const context = await browser.newContext();
  const first = await context.newPage();
  const second = await context.newPage();

  await first.goto('/spike.html');
  expect((await settled(first)).count).toBeGreaterThan(0);

  // Two connections to one sahpool VFS must fail while the first tab holds the handles.
  await second.goto('/spike.html');
  expect((await settled(second)).error).toBeTruthy();

  await first.evaluate(() => window.spike.send('pause'));
  const takeover = await second.evaluate(() => window.spike.send('run'));
  expect(takeover).toMatchObject({ op: 'run' });
  expect((takeover as Result).error).toBeUndefined();

  await context.close();
});

test('a blob worker does not inherit the page CSP', async ({ page }) => {
  await page.goto('/spike.html?mode=blob');
  expect((await settled(page)).cspInherited).toBe(true);
});

test('the database worker runs from a blob URL and keeps its CSP', async ({
  page,
}) => {
  await page.goto('/spike.html?mode=blobdb');
  const result = (await settled(page)) as Result & { error?: string };
  expect(result.error).toBeUndefined();
  expect(result.count).toBe(1);
  expect(result.cspInherited).toBe(true);
});
