import {Composition, registerRoot} from 'remotion';
import {SayKukuFilm} from './SayKukuFilm';

const Root = () => <Composition id="SayKuku" component={SayKukuFilm} width={1920} height={1080} fps={60} durationInFrames={1200} />;

registerRoot(Root);
