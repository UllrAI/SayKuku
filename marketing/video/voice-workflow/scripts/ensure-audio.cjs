const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
if (!fs.existsSync(path.join(root, 'public/score-final.wav'))) {
  const result = spawnSync('python3', [path.join(__dirname, 'make_score_final.py')], {stdio: 'inherit', cwd: root});
  if (result.error) console.error('Audio generation requires Python 3, NumPy, SciPy and FFmpeg:', result.error.message);
  process.exit(result.status ?? 1);
}
