// Records each mockup's scripted walkthrough to videos/<name>.mp4 and its last frame to renders/<name>.png.
// Usage: node record.cjs [name ...]   (names without .html; default: all numbered mockups)
const path = require('path');
const fs = require('fs');
const { execFileSync } = require('child_process');
const { chromium } = require(path.join(process.env.HOME, 'Desktop/scripts/node_modules/playwright-core'));

const dir = __dirname;
const exe = path.join(process.env.HOME, '.cache/ms-playwright/chromium-1243/chrome-linux64/chrome');
const names = process.argv.slice(2).length ? process.argv.slice(2)
  : fs.readdirSync(dir).filter((f) => /^\d-.*\.html$/.test(f)).map((f) => f.replace('.html', ''));

(async () => {
  const browser = await chromium.launch({ executablePath: exe });
  await Promise.all(names.map(async (name) => {
    const tmp = fs.mkdtempSync('/tmp/onb-rec-');
    const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, recordVideo: { dir: tmp, size: { width: 1920, height: 1080 } } });
    const page = await ctx.newPage();
    const t0 = Date.now();
    await page.goto('file://' + path.join(dir, name + '.html') + '?raw&rec');
    await page.waitForFunction('window.__done === true', null, { timeout: 180000, polling: 200 });
    await page.screenshot({ path: path.join(dir, 'renders', name + '.png') });
    const video = page.video();
    await ctx.close();
    const webm = await video.path();
    // Trim the blank load frames, encode H.264 for wide playback.
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-ss', '0.6', '-i', webm, '-c:v', 'libx264', '-preset', 'slow', '-crf', '22',
      '-pix_fmt', 'yuv420p', '-r', '30', '-movflags', '+faststart', path.join(dir, 'videos', name + '.mp4')]);
    fs.rmSync(tmp, { recursive: true, force: true });
    console.log(`${name}: ${((Date.now() - t0) / 1000).toFixed(1)}s`);
  }));
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
