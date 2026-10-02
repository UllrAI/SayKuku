import {Composition, registerRoot} from 'remotion';
import {Film} from './Film';
import {T} from './theme';

const Root = () => <>
  <Composition id="SayKuku-zh" component={Film} defaultProps={{lang: 'zh' as const}} width={1920} height={1080} fps={T.fps} durationInFrames={T.durationInFrames} />
  <Composition id="SayKuku-en" component={Film} defaultProps={{lang: 'en' as const}} width={1920} height={1080} fps={T.fps} durationInFrames={T.durationInFrames} />
</>;

registerRoot(Root);
