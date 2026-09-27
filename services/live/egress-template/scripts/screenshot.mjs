/**
 * Renders the recorded stage for every layout preset in demo mode and saves PNGs — a way to
 * look at what a recording will look like without LiveKit or Egress.
 *
 *   pnpm --filter @tihe/live-egress-template screenshot [outDir]
 *
 * Uses the Chromium that ships with Playwright; set CHROMIUM_PATH to use another one.
 */
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { chromium } from 'playwright-core';
import { preview } from 'vite';

const outDir = resolve(process.argv[2] ?? 'screenshots');
mkdirSync(outDir, { recursive: true });

const server = await preview({ preview: { port: 0, host: '127.0.0.1' }, logLevel: 'silent' });
const base = server.resolvedUrls.local[0];
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium',
});
try {
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  for (const layout of ['lecture', 'presentation', 'whiteboard', 'discussion', 'split', 'qa']) {
    await page.goto(`${base}?demo&layout=${layout}`);
    await page.waitForSelector('body[data-ready="true"]');
    const file = `${outDir}/recording-${layout}.png`;
    await page.screenshot({ path: file });
    console.log(file);
  }
} finally {
  await browser.close();
  server.httpServer.close();
}
