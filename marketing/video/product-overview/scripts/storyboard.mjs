// Renders key frames for one language and tiles them into a storyboard sheet.
// Usage: node scripts/storyboard.mjs <zh|en> [frame ...]
import {execFileSync} from 'node:child_process';
import {mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {bundle} from '@remotion/bundler';
import {renderStill, selectComposition} from '@remotion/renderer';

const [lang = 'zh', ...picked] = process.argv.slice(2);
const frames = picked.length ? picked.map(Number) : [20, 110, 172, 188, 250, 400, 488, 575, 640, 700, 768, 800, 880, 960, 1000, 1052, 1112, 1142, 1215, 1380];
const root = fileURLToPath(new URL('..', import.meta.url));
const out = fileURLToPath(new URL(`../../../../Dist/marketing/storyboard-${lang}/`, import.meta.url));
mkdirSync(out, {recursive: true});

const serveUrl = await bundle({entryPoint: `${root}src/index.tsx`});
const id = `SayKuku-${lang}`;
const composition = await selectComposition({serveUrl, id});
const gl = process.platform === 'darwin' ? 'angle' : 'swangle';
for (const frame of frames) {
  const output = `${out}f${String(frame).padStart(4, '0')}.png`;
  await renderStill({serveUrl, composition, frame, output, chromiumOptions: {gl}});
  console.log(output);
}

// 4-column sheet, each tile labelled with its timecode.
const inputs = frames.flatMap(frame => ['-i', `${out}f${String(frame).padStart(4, '0')}.png`]);
const labelled = frames.map((frame, i) => `[${i}]scale=480:-1,drawtext=text='${(frame / 60).toFixed(2)}s':x=10:y=10:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6[t${i}]`);
const layout = frames.map((_, i) => `${(i % 4) * 480}_${Math.floor(i / 4) * 270}`).join('|');
const graph = `${labelled.join(';')};${frames.map((_, i) => `[t${i}]`).join('')}xstack=inputs=${frames.length}:layout=${layout}:fill=black`;
execFileSync('ffmpeg', ['-loglevel', 'error', '-y', ...inputs, '-filter_complex', graph, `${out}../SayKuku-storyboard-${lang}.jpg`]);
console.log(`${out}../SayKuku-storyboard-${lang}.jpg`);
