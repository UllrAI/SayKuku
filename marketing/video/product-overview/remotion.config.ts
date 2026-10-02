import {Config} from '@remotion/cli/config';

// Headless Linux has no GPU-backed ANGLE; SwiftShader keeps WebGL deterministic there.
Config.setChromiumOpenGlRenderer(process.platform === 'darwin' ? 'angle' : 'swangle');
Config.setVideoImageFormat('png');
Config.setConcurrency(3);
