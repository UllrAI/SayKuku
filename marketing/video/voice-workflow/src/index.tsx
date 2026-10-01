import { registerRoot, Composition } from "remotion";
import { PromoReal } from "./PromoReal";
registerRoot(() => (
  <Composition
    id="SayKukuFinal"
    component={PromoReal}
    width={1920}
    height={1080}
    fps={60}
    durationInFrames={900}
  />
));
