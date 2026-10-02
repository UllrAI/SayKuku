import '@fontsource-variable/source-serif-4/opsz.css';
import '@fontsource-variable/inter/index.css';
import '@fontsource/noto-serif-sc/900.css';
import '@fontsource/noto-sans-sc/400.css';
import '@fontsource/noto-sans-sc/500.css';
import '@fontsource/noto-sans-sc/600.css';
import '@fontsource/noto-sans-sc/700.css';
import {useEffect, useState} from 'react';
import {useDelayRender} from 'remotion';

// Fonts ship through npm (SIL OFL), so renders match on any machine.
const FACES = [
  '700 64px "Source Serif 4 Variable"', '900 64px "Source Serif 4 Variable"',
  '400 32px "Inter Variable"', '600 32px "Inter Variable"', '900 64px "Noto Serif SC"',
  '400 32px "Noto Sans SC"', '500 32px "Noto Sans SC"', '600 32px "Noto Sans SC"', '700 32px "Noto Sans SC"',
];

/** Holds the frame until every face has the glyphs this version draws. */
export const useFonts = (text: string) => {
  const {delayRender, continueRender, cancelRender} = useDelayRender();
  const [handle] = useState(() => delayRender('Loading fonts'));
  useEffect(() => {
    Promise.all(FACES.map(face => document.fonts.load(face, text)))
      .then(() => document.fonts.ready)
      .then(() => continueRender(handle))
      .catch(cancelRender);
  }, [text, handle, continueRender, cancelRender]);
};
